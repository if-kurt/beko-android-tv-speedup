package io.github.ifkurt.gercekkapat;

import android.app.Notification;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;

import java.io.File;
import java.io.FileDescriptor;
import java.io.IOException;
import java.io.PrintWriter;
import java.security.KeyPair;
import java.security.interfaces.RSAPublicKey;
import java.util.Calendar;

/**
 * Watches the screen. When the power button puts the TV to sleep and the policy says so, it keeps the TV awake
 * for a moment and asks adbd on 127.0.0.1:5555 to run "reboot -p", which is a real power-off.
 */
public final class WatchService extends Service {
    static final String ACTION_PAIR = "io.github.ifkurt.gercekkapat.PAIR";
    static final String ACTION_TEST = "io.github.ifkurt.gercekkapat.TEST";
    static final String ACTION_CONFIG = "io.github.ifkurt.gercekkapat.CONFIG";

    private static final String HOST = "127.0.0.1";
    private static final int PORT = 5555;
    private static final String KEY_NAME = "gercekkapat@tv";
    /** If more time than this passed since the screen went off, the TV slept in between: do nothing. */
    private static final long MAX_LATE_MS = 20000;

    private Handler worker;
    private HandlerThread workerThread;
    private PowerManager.WakeLock wakeLock;
    private EventLog log;
    private volatile boolean pending;
    private volatile long screenOffAt;

    private final BroadcastReceiver screenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (Intent.ACTION_SCREEN_OFF.equals(intent.getAction())) {
                onScreenOff();
            } else if (Intent.ACTION_SCREEN_ON.equals(intent.getAction())) {
                onScreenOn();
            }
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        log = new EventLog(new File(getFilesDir(), "events.log"));
        workerThread = new HandlerThread("gercekkapat");
        workerThread.start();
        worker = new Handler(workerThread.getLooper());
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "gercekkapat:shutdown");
        wakeLock.setReferenceCounted(false);
        IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_OFF);
        filter.addAction(Intent.ACTION_SCREEN_ON);
        registerReceiver(screenReceiver, filter);
        startForeground(1, buildNotification());
        log.add("service started " + versionName() + ", TV booted " + formatUptime(SystemClock.elapsedRealtime()) + " ago");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_PAIR.equals(action)) {
            worker.post(pairTask);
        } else if (ACTION_TEST.equals(action)) {
            Config c = Config.load(this);
            c.testOnce = true;
            c.save(this);
            log.add("TEST armed: the next power button press will really power off");
        } else if (ACTION_CONFIG.equals(action)) {
            applyConfig(intent);
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        unregisterReceiver(screenReceiver);
        workerThread.quit();
        releaseWakeLock();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ---- screen events ----

    private void onScreenOff() {
        long now = SystemClock.elapsedRealtime();
        Config c = Config.load(this);
        int hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        String reason = Policy.decide(c.enabled, c.testOnce, now, hour,
                c.nightStart, c.nightEnd, c.nightMinHours, c.anyMinHours);
        if (reason == null) {
            log.add("screen off: normal sleep (TV up " + formatUptime(now) + ", hour " + hour + ")");
            return;
        }
        if (c.testOnce) {
            c.testOnce = false;
            c.save(this);
        }
        wakeLock.acquire(60000);
        screenOffAt = now;
        pending = true;
        log.add("screen off: real power-off (" + reason + ") in " + c.graceMs + " ms");
        worker.postDelayed(shutdownTask, c.graceMs);
    }

    private void onScreenOn() {
        if (pending) {
            pending = false;
            worker.removeCallbacks(shutdownTask);
            releaseWakeLock();
            log.add("screen back on: power-off cancelled");
        }
    }

    private final Runnable shutdownTask = new Runnable() {
        @Override
        public void run() {
            try {
                if (!pending) {
                    return;
                }
                pending = false;
                PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
                if (pm.isInteractive()) {
                    log.add("cancelled: the screen is on");
                    return;
                }
                long late = SystemClock.elapsedRealtime() - screenOffAt;
                if (late > MAX_LATE_MS) {
                    log.add("cancelled: " + late + " ms late, the TV must have slept in between");
                    return;
                }
                AudioManager audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
                if (audio != null && audio.isMusicActive()) {
                    log.add("cancelled: audio is playing (maybe someone is listening with the screen off)");
                    return;
                }
                KeyPair keys = Keys.loadOrCreate(getFilesDir());
                AdbClient adb = AdbClient.connect(HOST, PORT, keys, KEY_NAME, false, 5000, 5000);
                try {
                    log.add("sending reboot -p");
                    adb.shell("reboot -p", 15000);
                    log.add("reboot -p finished");
                } catch (IOException e) {
                    log.add("connection dropped, the TV should be powering off (" + e.getMessage() + ")");
                } finally {
                    adb.close();
                }
            } catch (AdbClient.NotAuthorizedException e) {
                log.add("no ADB permission, run PAIR: " + e.getMessage());
            } catch (Exception e) {
                log.add("error, the TV will sleep normally: " + e);
            } finally {
                releaseWakeLock();
            }
        }
    };

    // ---- pairing and settings ----

    private final Runnable pairTask = new Runnable() {
        @Override
        public void run() {
            try {
                KeyPair keys = Keys.loadOrCreate(getFilesDir());
                log.add("pairing started, key fingerprint "
                        + AdbClient.fingerprint((RSAPublicKey) keys.getPublic())
                        + "; approve the prompt on the TV if it appears");
                AdbClient adb = AdbClient.connect(HOST, PORT, keys, KEY_NAME, true, 5000, 120000);
                try {
                    String answer = adb.shell("echo ok", 5000).trim();
                    log.add("pairing done (" + answer + ", " + adb.deviceBanner + ")");
                } finally {
                    adb.close();
                }
            } catch (Exception e) {
                log.add("pairing failed: " + e);
            }
        }
    };

    private void applyConfig(Intent intent) {
        Config c = Config.load(this);
        if (intent.hasExtra("enabled")) {
            c.enabled = intent.getBooleanExtra("enabled", c.enabled);
        }
        c.nightStart = hourExtra(intent, "nightStart", c.nightStart);
        c.nightEnd = hourExtra(intent, "nightEnd", c.nightEnd);
        c.nightMinHours = rangeExtra(intent, "nightMinHours", c.nightMinHours, 0, 24 * 60);
        c.anyMinHours = rangeExtra(intent, "anyMinHours", c.anyMinHours, 1, 24 * 60);
        c.graceMs = rangeExtra(intent, "graceMs", c.graceMs, 0, 15000);
        c.save(this);
        log.add("settings: " + c.describe());
    }

    private static int hourExtra(Intent intent, String key, int current) {
        return rangeExtra(intent, key, current, 0, 23);
    }

    private static int rangeExtra(Intent intent, String key, int current, int min, int max) {
        if (!intent.hasExtra(key)) {
            return current;
        }
        int value = intent.getIntExtra(key, current);
        return value < min || value > max ? current : value;
    }

    // ---- status: adb shell dumpsys activity service io.github.ifkurt.gercekkapat/.WatchService ----

    @Override
    protected void dump(FileDescriptor fd, PrintWriter pw, String[] args) {
        Config c = Config.load(this);
        long now = SystemClock.elapsedRealtime();
        int hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        String reason = Policy.decide(c.enabled, false, now, hour,
                c.nightStart, c.nightEnd, c.nightMinHours, c.anyMinHours);
        pw.println("Gerçek Kapat " + versionName());
        pw.println("TV up: " + formatUptime(now));
        pw.println("settings: " + c.describe());
        pw.println("if turned off now: " + (reason == null ? "normal sleep" : "real power-off (" + reason + ")"));
        try {
            pw.println("key: " + (Keys.exist(getFilesDir())
                    ? AdbClient.fingerprint((RSAPublicKey) Keys.loadOrCreate(getFilesDir()).getPublic())
                    : "none yet (run PAIR)"));
        } catch (Exception e) {
            pw.println("could not read the key: " + e);
        }
        pw.println("recent events:");
        for (String line : log.lines()) {
            pw.println("  " + line);
        }
    }

    // ---- helpers ----

    private String versionName() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "?";
        }
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
    }

    private Notification buildNotification() {
        return new Notification.Builder(this)
                .setSmallIcon(android.R.drawable.ic_lock_power_off)
                .setContentTitle("Gerçek Kapat")
                .setContentText("Watching the power button")
                .setPriority(Notification.PRIORITY_MIN)
                .setOngoing(true)
                .build();
    }

    static String formatUptime(long ms) {
        long minutes = ms / 60000L;
        long days = minutes / (24 * 60);
        long hours = (minutes / 60) % 24;
        long mins = minutes % 60;
        return days > 0 ? days + " d " + hours + " h" : hours + " h " + mins + " min";
    }
}
