package io.github.ifkurt.gercekkapat;

import android.content.Context;
import android.content.SharedPreferences;

/** Settings, changed over ADB with the CONFIG action. */
final class Config {
    boolean enabled = true;
    boolean testOnce = false;
    int nightStart = 23;
    int nightEnd = 6;
    int nightMinHours = 72;
    int anyMinHours = 120;
    int graceMs = 3000;

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("config", Context.MODE_PRIVATE);
    }

    static Config load(Context context) {
        SharedPreferences p = prefs(context);
        Config c = new Config();
        c.enabled = p.getBoolean("enabled", c.enabled);
        c.testOnce = p.getBoolean("testOnce", c.testOnce);
        c.nightStart = p.getInt("nightStart", c.nightStart);
        c.nightEnd = p.getInt("nightEnd", c.nightEnd);
        c.nightMinHours = p.getInt("nightMinHours", c.nightMinHours);
        c.anyMinHours = p.getInt("anyMinHours", c.anyMinHours);
        c.graceMs = p.getInt("graceMs", c.graceMs);
        return c;
    }

    void save(Context context) {
        prefs(context).edit()
                .putBoolean("enabled", enabled)
                .putBoolean("testOnce", testOnce)
                .putInt("nightStart", nightStart)
                .putInt("nightEnd", nightEnd)
                .putInt("nightMinHours", nightMinHours)
                .putInt("anyMinHours", anyMinHours)
                .putInt("graceMs", graceMs)
                .commit();
    }

    String describe() {
        return "etkin=" + enabled
                + ", gece " + nightStart + ":00-" + nightEnd + ":00 ve en az " + nightMinHours + " saat"
                + ", ya da her saatte en az " + anyMinHours + " saat"
                + ", bekleme " + graceMs + " ms"
                + (testOnce ? ", TEST kurulu (bir sonraki kapatma gerçek)" : "");
    }
}
