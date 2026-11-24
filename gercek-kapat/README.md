# Gerçek Kapat

**English** | [Türkçe](README.tr.md)

A small helper app for a Beko Android TV (Skyworth, MStar/MediaTek, Android TV 9). A single press of the power button
normally suspends the TV to RAM (STR), so it can go weeks without a reboot and grow sluggish. When conditions are met,
this app powers the TV off for real (`reboot -p`) at the moment the button is pressed. Nobody at home has to change
how they turn the TV off.

No icon and nothing on the home screen. It is managed over ADB only. The APK is ~20 KB and needs no root.

## How it decides

When the screen turns off (power button, auto power-off, …):

- Between **23:00 and 06:00**, if the TV hasn't really been off for at least **72 hours** → real power-off.
- If the TV hasn't been off for more than **120 hours** (5 days) → real power-off at any hour.
- Otherwise → normal sleep (instant wake-up).

Before a real power-off it waits 3 seconds and gives up if the screen comes back on, if the TV slept in between (more
than 20 seconds late), if audio is playing, or if it has no ADB permission. The worst case is that the TV just sleeps
as usual.

## How it works

- `WatchService` runs as a foreground service and starts by itself at boot through `BOOT_COMPLETED`.
- When the screen turns off, `Policy` decides. If the TV should power off, the service holds a wake lock so the TV
  doesn't suspend for those few seconds.
- `AdbClient` is a small client for ADB's TCP protocol (CNXN/AUTH/OPEN). It connects to the TV's own adbd at
  `127.0.0.1:5555` and runs `shell:reboot -p`. On this firmware `svc power shutdown` is swallowed, while `reboot -p`
  works.
- The app's 2048-bit RSA key is created at first pairing and kept in its private folder. The first time, the TV asks
  "Allow USB debugging?".
- The service is only open to holders of `android.permission.DUMP` (the ADB shell and the system), so other apps can't
  trigger it.
- Events go to a small file that `dumpsys` reads, so the lines written right before a power-off are kept too.

## Install

Download the APK from [Releases](https://github.com/if-kurt/beko-android-tv-speedup/releases):

```
adb install gercek-kapat-1.1.apk
adb shell am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.PAIR
```

The TV shows "Allow USB debugging?". Tick "Always allow" and confirm. The fingerprint in the prompt should match the
"key" line of the status output.

## Status and events

```
adb shell dumpsys activity service io.github.ifkurt.gercekkapat/.WatchService
```

Example: the events from the test on the real TV, in 1.1's format:

```
2026-11-24 19:00:36  TEST armed: the next power button press will really power off
2026-11-24 19:01:12  screen off: real power-off (test) in 3000 ms
2026-11-24 19:01:15  sending reboot -p
2026-11-24 19:01:15  reboot -p finished
2026-11-24 19:02:46  service started 1.1, TV booted 0 h 1 min ago
```

## Test

Makes the next power button press a real power-off, whatever the conditions (one time only):

```
adb shell am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.TEST
```

## Settings

```
adb shell am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.CONFIG --ei nightStart 23 --ei nightEnd 6 --ei nightMinHours 72 --ei anyMinHours 120 --ei graceMs 3000
```

`--ez enabled false` turns it off, `--ez enabled true` turns it back on. Only the values you pass change.

## Uninstall

```
adb uninstall io.github.ifkurt.gercekkapat
```

The app's ADB key stays approved on the TV. To remove it as well: Developer options → "Revoke USB debugging
authorizations" (this also removes your computer's permission; it will ask again on the next connection).

## Build

No Gradle needed. On Ubuntu/Debian (WSL works too):

```
sudo apt install android-sdk-platform-23 aapt dalvik-exchange zipalign apksigner default-jdk
keytool -genkeypair -keystore release.jks -storetype PKCS12 -alias gercekkapat -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Gercek Kapat"
KS_PASS='your-keystore-password' sh build.sh
```

Output: `build/gercek-kapat-<version>.apk`. An APK signed with your own key can't be installed as an update over the
APK from Releases; uninstall that one first.

## Tests

`test/mock_adbd.py` is a strict fake adbd. It checks the message framing, checksums, signatures and the key format.
`AdbClientTest.java` runs the client against it and also checks the decision rules. The key format and signatures are
byte-for-byte identical to those of [adb-shell](https://github.com/JeffLIrion/adb_shell), a library used with real
devices.

```
mkdir -p /tmp/gk && javac -d /tmp/gk src/io/github/ifkurt/gercekkapat/{Base64,AdbClient,Keys,Policy}.java test/AdbClientTest.java
python3 test/mock_adbd.py 47555 &
java -cp /tmp/gk io.github.ifkurt.gercekkapat.AdbClientTest 47555 /tmp/gk-keys
```
