package io.github.ifkurt.gercekkapat;

/** Standard Base64 (RFC 4648) with padding and no line breaks. Kept tiny so the ADB code stays plain Java. */
final class Base64 {
    private static final char[] ALPHABET =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toCharArray();

    private Base64() {}

    static String encode(byte[] data) {
        StringBuilder sb = new StringBuilder((data.length + 2) / 3 * 4);
        int i = 0;
        for (; i + 2 < data.length; i += 3) {
            int v = ((data[i] & 0xff) << 16) | ((data[i + 1] & 0xff) << 8) | (data[i + 2] & 0xff);
            sb.append(ALPHABET[(v >>> 18) & 63]).append(ALPHABET[(v >>> 12) & 63])
              .append(ALPHABET[(v >>> 6) & 63]).append(ALPHABET[v & 63]);
        }
        int rest = data.length - i;
        if (rest == 1) {
            int v = (data[i] & 0xff) << 16;
            sb.append(ALPHABET[(v >>> 18) & 63]).append(ALPHABET[(v >>> 12) & 63]).append("==");
        } else if (rest == 2) {
            int v = ((data[i] & 0xff) << 16) | ((data[i + 1] & 0xff) << 8);
            sb.append(ALPHABET[(v >>> 18) & 63]).append(ALPHABET[(v >>> 12) & 63])
              .append(ALPHABET[(v >>> 6) & 63]).append('=');
        }
        return sb.toString();
    }
}
