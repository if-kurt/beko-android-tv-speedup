package io.github.ifkurt.gercekkapat;

import java.io.EOFException;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.SocketException;
import java.security.KeyPair;
import java.security.SecureRandom;
import java.security.interfaces.RSAPublicKey;

/** Runs AdbClient on a PC against mock_adbd.py, and exports material for a cross-check with adb_shell. */
public class AdbClientTest {
    private static int failures = 0;

    private static void check(boolean ok, String what) {
        System.out.println((ok ? "PASS " : "FAIL ") + what);
        if (!ok) failures++;
    }

    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(args[0]);
        File dir = new File(args[1]);
        dir.mkdirs();

        KeyPair keys = Keys.loadOrCreate(dir);
        KeyPair again = Keys.loadOrCreate(dir);
        check(AdbClient.fingerprint((RSAPublicKey) keys.getPublic())
                .equals(AdbClient.fingerprint((RSAPublicKey) again.getPublic())), "keys reload from disk");

        // Material for the Python cross-check.
        byte[] token = new byte[20];
        new SecureRandom().nextBytes(token);
        write(new File(dir, "token.bin"), token);
        write(new File(dir, "sig.bin"), AdbClient.sign(keys.getPrivate(), token));
        write(new File(dir, "pubkey.txt"), Base64.encode(AdbClient.publicKeyBlob((RSAPublicKey) keys.getPublic())).getBytes("US-ASCII"));
        write(new File(dir, "fingerprint.txt"), AdbClient.fingerprint((RSAPublicKey) keys.getPublic()).getBytes("US-ASCII"));

        // Base64 against the JDK.
        SecureRandom random = new SecureRandom();
        boolean b64 = true;
        for (int len = 0; len < 70; len++) {
            byte[] data = new byte[len];
            random.nextBytes(data);
            b64 &= Base64.encode(data).equals(java.util.Base64.getEncoder().encodeToString(data));
        }
        check(b64, "Base64 matches java.util.Base64 for lengths 0..69");

        // 1) Unknown key and no prompt allowed: must fail fast, without sending the public key.
        try {
            AdbClient.connect("127.0.0.1", port, keys, "test@tv", false, 3000, 3000).close();
            check(false, "unknown key without prompt is refused");
        } catch (AdbClient.NotAuthorizedException e) {
            check(true, "unknown key without prompt is refused (" + e.getMessage() + ")");
        }

        // 2) Pairing: send the key, mock approves, run a command.
        AdbClient c = AdbClient.connect("127.0.0.1", port, keys, "test@tv", true, 3000, 5000);
        check(c.deviceBanner.startsWith("device::"), "pairing connects, banner: " + c.deviceBanner);
        String out = c.shell("echo ok", 3000);
        check("ok\n".equals(out), "shell echo ok returns 'ok\\n' (got '" + out.replace("\n", "\\n") + "')");
        c.close();

        // 3) Known key: signature accepted; reboot -p makes the "device" drop the connection.
        c = AdbClient.connect("127.0.0.1", port, keys, "test@tv", false, 3000, 3000);
        check(true, "known key connects without prompt");
        try {
            c.shell("reboot -p", 3000);
            check(true, "reboot -p: stream closed normally");
        } catch (EOFException e) {
            check(true, "reboot -p: connection dropped as a real power-off would (" + e.getMessage() + ")");
        } catch (SocketException e) {
            check(true, "reboot -p: connection reset as a real power-off would (" + e.getMessage() + ")");
        } catch (IOException e) {
            check(false, "reboot -p unexpected " + e);
        } finally {
            c.close();
        }

        // 4) Policy.
        long h = 3600000L;
        check(Policy.inWindow(23, 23, 6) && Policy.inWindow(0, 23, 6) && Policy.inWindow(5, 23, 6)
                && !Policy.inWindow(6, 23, 6) && !Policy.inWindow(22, 23, 6) && !Policy.inWindow(14, 23, 6),
                "night window 23-06 wraps midnight");
        check(Policy.inWindow(14, 10, 18) && !Policy.inWindow(18, 10, 18), "day window 10-18");
        check(Policy.decide(true, false, 71 * h, 23, 23, 6, 72, 120) == null, "night, 71 h -> sleep");
        check(Policy.decide(true, false, 72 * h, 23, 23, 6, 72, 120) != null, "night, 72 h -> shutdown");
        check(Policy.decide(true, false, 100 * h, 14, 23, 6, 72, 120) == null, "day, 100 h -> sleep");
        check(Policy.decide(true, false, 120 * h, 14, 23, 6, 72, 120) != null, "day, 120 h -> shutdown");
        check(Policy.decide(false, false, 500 * h, 2, 23, 6, 72, 120) == null, "disabled -> sleep");
        check(Policy.decide(false, true, 0, 14, 23, 6, 72, 120) != null, "test overrides everything");

        System.out.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        System.exit(failures == 0 ? 0 : 1);
    }

    private static void write(File f, byte[] data) throws IOException {
        FileOutputStream out = new FileOutputStream(f);
        try {
            out.write(data);
        } finally {
            out.close();
        }
    }
}
