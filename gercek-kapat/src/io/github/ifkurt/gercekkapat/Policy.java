package io.github.ifkurt.gercekkapat;

/** Decides, at the moment the screen goes off, whether to really power off or let the TV sleep (STR). */
final class Policy {
    private Policy() {}

    /** True if hour is in [start, end), wrapping past midnight when start > end. start == end means all day. */
    static boolean inWindow(int hour, int start, int end) {
        if (start == end) {
            return true;
        }
        return start < end ? hour >= start && hour < end : hour >= start || hour < end;
    }

    /** Returns the reason for a real shutdown, or null to let the TV go to sleep as usual. */
    static String decide(boolean enabled, boolean testOnce, long uptimeMs, int hour,
                         int nightStart, int nightEnd, int nightMinHours, int anyMinHours) {
        if (testOnce) {
            return "test";
        }
        if (!enabled) {
            return null;
        }
        long hours = uptimeMs / 3600000L;
        if (hours >= anyMinHours) {
            return "TV " + hours + " saattir hiç kapanmadı";
        }
        if (inWindow(hour, nightStart, nightEnd) && hours >= nightMinHours) {
            return "gece saati ve TV " + hours + " saattir açık";
        }
        return null;
    }
}
