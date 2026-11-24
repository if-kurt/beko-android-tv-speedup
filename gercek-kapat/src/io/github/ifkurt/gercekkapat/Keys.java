package io.github.ifkurt.gercekkapat;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.RSAKeyGenParameterSpec;
import java.security.spec.X509EncodedKeySpec;

/** The app's own ADB key, created once and kept in its private files folder. */
final class Keys {
    private Keys() {}

    static boolean exist(File dir) {
        return new File(dir, "adbkey.pk8").isFile() && new File(dir, "adbkey.x509").isFile();
    }

    static synchronized KeyPair loadOrCreate(File dir) throws GeneralSecurityException, IOException {
        File privateFile = new File(dir, "adbkey.pk8");
        File publicFile = new File(dir, "adbkey.x509");
        KeyFactory factory = KeyFactory.getInstance("RSA");
        if (privateFile.isFile() && publicFile.isFile()) {
            return new KeyPair(
                    factory.generatePublic(new X509EncodedKeySpec(readAll(publicFile))),
                    factory.generatePrivate(new PKCS8EncodedKeySpec(readAll(privateFile))));
        }
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(new RSAKeyGenParameterSpec(2048, RSAKeyGenParameterSpec.F4));
        KeyPair pair = generator.generateKeyPair();
        writeAll(privateFile, pair.getPrivate().getEncoded());
        writeAll(publicFile, pair.getPublic().getEncoded());
        return pair;
    }

    private static byte[] readAll(File file) throws IOException {
        InputStream in = new FileInputStream(file);
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int r;
            while ((r = in.read(buffer)) > 0) {
                out.write(buffer, 0, r);
            }
            return out.toByteArray();
        } finally {
            in.close();
        }
    }

    private static void writeAll(File file, byte[] data) throws IOException {
        FileOutputStream out = new FileOutputStream(file);
        try {
            out.write(data);
            out.getFD().sync();
        } finally {
            out.close();
        }
    }
}
