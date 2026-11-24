package io.github.ifkurt.gercekkapat;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.Charset;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;

/**
 * Minimal client for the classic ADB-over-TCP protocol (CNXN / AUTH / OPEN / OKAY / WRTE / CLSE),
 * the same one "adb connect host:5555" speaks. Plain Java, no Android imports, so it can be tested on a PC.
 */
final class AdbClient implements Closeable {
    static final int A_CNXN = 0x4e584e43;
    static final int A_AUTH = 0x48545541;
    static final int A_OPEN = 0x4e45504f;
    static final int A_OKAY = 0x59414b4f;
    static final int A_CLSE = 0x45534c43;
    static final int A_WRTE = 0x45545257;

    static final int A_VERSION = 0x01000000;
    static final int MAX_PAYLOAD = 4096;

    static final int AUTH_TOKEN = 1;
    static final int AUTH_SIGNATURE = 2;
    static final int AUTH_RSAPUBLICKEY = 3;

    private static final Charset ASCII = Charset.forName("US-ASCII");
    private static final Charset UTF8 = Charset.forName("UTF-8");

    /** DER prefix of a SHA-1 DigestInfo. adbd checks RSA_verify(NID_sha1, token, ...), so the token is signed as the digest. */
    private static final byte[] SHA1_DIGEST_INFO = {
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};

    /** The TV does not (or not yet) trust our key. */
    static final class NotAuthorizedException extends IOException {
        NotAuthorizedException(String message) {
            super(message);
        }
    }

    static final class Message {
        final int command;
        final int arg0;
        final int arg1;
        final byte[] data;

        Message(int command, int arg0, int arg1, byte[] data) {
            this.command = command;
            this.arg0 = arg0;
            this.arg1 = arg1;
            this.data = data;
        }
    }

    private final Socket socket;
    private final InputStream in;
    private final OutputStream out;
    private int nextLocalId = 1;
    final String deviceBanner;

    private AdbClient(Socket socket, InputStream in, OutputStream out, String deviceBanner) {
        this.socket = socket;
        this.in = in;
        this.out = out;
        this.deviceBanner = deviceBanner;
    }

    /**
     * Connects and authenticates with our key.
     *
     * @param allowPrompt if the key is unknown, send it so the TV shows "Allow USB debugging?" and wait
     *                    up to approvalTimeoutMs for the user. If false, an unknown key fails at once.
     */
    static AdbClient connect(String host, int port, KeyPair keys, String keyName, boolean allowPrompt,
                             int timeoutMs, int approvalTimeoutMs) throws IOException, GeneralSecurityException {
        Socket socket = new Socket();
        boolean connected = false;
        boolean sentKey = false;
        try {
            socket.connect(new InetSocketAddress(host, port), timeoutMs);
            socket.setTcpNoDelay(true);
            socket.setSoTimeout(timeoutMs);
            InputStream in = new BufferedInputStream(socket.getInputStream());
            OutputStream out = new BufferedOutputStream(socket.getOutputStream());

            write(out, A_CNXN, A_VERSION, MAX_PAYLOAD, "host::\0".getBytes(ASCII));
            boolean sentSignature = false;
            while (true) {
                Message m = read(in);
                if (m.command == A_CNXN) {
                    connected = true;
                    return new AdbClient(socket, in, out, new String(m.data, ASCII).trim());
                }
                if (m.command != A_AUTH || m.arg0 != AUTH_TOKEN) {
                    continue;
                }
                if (!sentSignature) {
                    write(out, A_AUTH, AUTH_SIGNATURE, 0, sign(keys.getPrivate(), m.data));
                    sentSignature = true;
                } else if (allowPrompt && !sentKey) {
                    write(out, A_AUTH, AUTH_RSAPUBLICKEY, 0,
                            publicKeyPayload((RSAPublicKey) keys.getPublic(), keyName));
                    sentKey = true;
                    socket.setSoTimeout(approvalTimeoutMs);
                } else {
                    throw new NotAuthorizedException(sentKey
                            ? "the TV refused the key"
                            : "the key is not authorized on the TV");
                }
            }
        } catch (SocketTimeoutException e) {
            if (sentKey) {
                throw new NotAuthorizedException("nobody approved the key on the TV in time");
            }
            throw e;
        } finally {
            if (!connected) {
                try {
                    socket.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    /** Runs a command through the "shell:" service and returns what it printed. */
    String shell(String command, int timeoutMs) throws IOException {
        int localId = nextLocalId++;
        socket.setSoTimeout(timeoutMs);
        write(out, A_OPEN, localId, 0, ("shell:" + command + "\0").getBytes(UTF8));
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        while (true) {
            Message m = read(in);
            if (m.arg1 != localId) {
                continue;
            }
            if (m.command == A_WRTE) {
                output.write(m.data);
                write(out, A_OKAY, localId, m.arg0, null);
            } else if (m.command == A_CLSE) {
                return new String(output.toByteArray(), UTF8);
            }
            // A_OKAY: the stream is open, keep reading.
        }
    }

    @Override
    public void close() throws IOException {
        socket.close();
    }

    // ---- wire format ----

    static void write(OutputStream out, int command, int arg0, int arg1, byte[] data) throws IOException {
        int length = data == null ? 0 : data.length;
        int checksum = 0;
        for (int i = 0; i < length; i++) {
            checksum += data[i] & 0xff;
        }
        ByteBuffer header = ByteBuffer.allocate(24).order(ByteOrder.LITTLE_ENDIAN);
        header.putInt(command).putInt(arg0).putInt(arg1).putInt(length).putInt(checksum).putInt(~command);
        out.write(header.array());
        if (length > 0) {
            out.write(data);
        }
        out.flush();
    }

    static Message read(InputStream in) throws IOException {
        ByteBuffer header = ByteBuffer.wrap(readFully(in, 24)).order(ByteOrder.LITTLE_ENDIAN);
        int command = header.getInt();
        int arg0 = header.getInt();
        int arg1 = header.getInt();
        int length = header.getInt();
        header.getInt(); // checksum, not needed for reading
        int magic = header.getInt();
        if (magic != ~command) {
            throw new IOException("bad ADB header");
        }
        if (length < 0 || length > (1 << 20)) {
            throw new IOException("bad ADB payload length " + length);
        }
        return new Message(command, arg0, arg1, length == 0 ? new byte[0] : readFully(in, length));
    }

    private static byte[] readFully(InputStream in, int n) throws IOException {
        byte[] buffer = new byte[n];
        int offset = 0;
        while (offset < n) {
            int r = in.read(buffer, offset, n - offset);
            if (r < 0) {
                throw new EOFException("connection closed");
            }
            offset += r;
        }
        return buffer;
    }

    // ---- crypto ----

    static byte[] sign(PrivateKey key, byte[] token) throws GeneralSecurityException {
        Signature signature = Signature.getInstance("NONEwithRSA");
        signature.initSign(key);
        signature.update(SHA1_DIGEST_INFO);
        signature.update(token);
        return signature.sign();
    }

    static byte[] publicKeyPayload(RSAPublicKey key, String name) {
        return (Base64.encode(publicKeyBlob(key)) + " " + name + "\0").getBytes(ASCII);
    }

    /** Android's adb public key format (the RSAPublicKey struct of libcrypto_utils/android_pubkey). */
    static byte[] publicKeyBlob(RSAPublicKey key) {
        final int words = 64;
        BigInteger n = key.getModulus();
        if (n.bitLength() != words * 32) {
            throw new IllegalArgumentException("ADB needs a 2048-bit RSA key");
        }
        BigInteger r32 = BigInteger.ONE.shiftLeft(32);
        BigInteger n0inv = n.mod(r32).modInverse(r32).negate().mod(r32);
        BigInteger rr = BigInteger.ONE.shiftLeft(words * 32 * 2).mod(n);
        ByteBuffer b = ByteBuffer.allocate(4 + 4 + words * 4 * 2 + 4).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(words);
        b.putInt(n0inv.intValue());
        putWords(b, n, words);
        putWords(b, rr, words);
        b.putInt(key.getPublicExponent().intValue());
        return b.array();
    }

    private static void putWords(ByteBuffer b, BigInteger value, int words) {
        BigInteger mask = BigInteger.ONE.shiftLeft(32).subtract(BigInteger.ONE);
        for (int i = 0; i < words; i++) {
            b.putInt(value.shiftRight(32 * i).and(mask).intValue());
        }
    }

    /** The MD5 fingerprint the TV shows in its "Allow USB debugging?" dialog. */
    static String fingerprint(RSAPublicKey key) throws GeneralSecurityException {
        byte[] digest = MessageDigest.getInstance("MD5").digest(publicKeyBlob(key));
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < digest.length; i++) {
            if (i > 0) {
                sb.append(':');
            }
            sb.append(String.format("%02X", digest[i] & 0xff));
        }
        return sb.toString();
    }
}
