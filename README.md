# Beko Android TV speed-up

**English** | [Türkçe](README.tr.md)

Notes on how we sped up a sluggish Beko Android TV without root, using only ADB. Plus a small app for the most
stubborn part: **Gerçek Kapat** ("really power off"). When the remote's power button is pressed once, it powers the TV
off for real when needed, instead of letting it sleep.

Everything is reversible. No system app was uninstalled, only disabled.

## The TV

| | |
|---|---|
| Model | Beko Android TV (`ro.product.name=Beko_EU`, `ro.product.device=shinagawa`) |
| Board made by | Skyworth (`ro.product.manufacturer=skyworth`) |
| SoC | MStar/MediaTek `m5621` |
| RAM | ~1 GB (909 MB visible); Android treats it as a low-RAM device (`ro.config.low_ram=true`) |
| Android | Android TV 9 (API 28), firmware from December 2021 (`PT07.211208.001`) |

## What was wrong

Symptoms: sluggish menus, remote presses registered late or only partly, and the TV got slower the longer it ran.

Measured after 2.5 days without a reboot:

- **Memory was exhausted.** 174 MB of available RAM. The 300 MB swap (compressed RAM, zram) was full, with 2 MB
  left. The kernel's memory reclaimer `kswapd0` never stopped (19% CPU at that moment, 26 minutes in total). The UI
  waits for memory, so key presses lag.
- **The load average of 108 was misleading.** All ~109 tasks in uninterruptible (D) state were MStar driver threads
  (`VMon_Task`, `DMX_Filt_Task`, `VDEC_*` …). Linux counts them in the load average, but they use no CPU; the CPU was
  70% idle. They live in the kernel and were left alone.
- **Memory hogs:** the Google app (`katniss`, voice search) at 155 MB across two processes, the HbbTV browser at
  ~63 MB, the Play Store background process at 33 MB, Skyworth's factory app at 25 MB, Chromecast at 21 MB, plus
  Google's home screen, recommendation services and store demo apps.
- **A flood of logs:** ~12,000 log lines per minute, most of them from the live TV app `tvcenter`. `logd` and the
  vendor's `k2logcat` service had used 35 minutes of CPU between them.
- **The power button suspends instead of powering off.** A short press suspends to RAM (STR,
  `ro.vendor.mstar.str.enable=user_mode`). A real shutdown needs a 5-second press and "OK", which nobody at home does.
  The TV went weeks without a reboot and memory problems piled up.

## What we did, and why

### 1. ADB

On the TV: Settings → Device Preferences → About → press Build 7 times, then turn on USB debugging in Developer
options. This TV has no separate network debugging switch, but port 5555 opens by itself
(`service.adb.tcp.port=5555`), so no cable was needed. The TV asks for permission on the first connection.

```
adb connect TV_IP:5555
```

### 2. Disabling packages

With `pm disable-user --user 0 <package>`. The app stays installed but none of its parts run, and
`pm enable <package>` brings it back. Uninstalling (`pm uninstall --user 0`) would be no faster, and it frees no space
either: system apps live on the read-only partition.

| Package | What | Why it was disabled |
|---|---|---|
| `com.google.android.tvlauncher` | Google home screen | Ad and recommendation rows, heavy. Replaced by Couchy. |
| `com.google.android.tvrecommendations` | Android TV Core Services | Home screen recommendations, useless with the new home screen. |
| `com.mediatek.wwtv.tvrecommendation` | MediaTek live TV recommendation row | ~9 MB, only feeds a home screen row. Channels still work. |
| `com.google.android.katniss` | Google app (voice search, Assistant) | ~155 MB, always in memory. Not used here. |
| `com.google.android.speech.pumpkin` | Offline speech recognition | Goes with katniss. |
| `com.google.android.apps.mediashell` | Chromecast | Not used, ~21 MB. |
| `com.google.android.tv.remote.service` | Phone-as-remote service | Not used, ~12 MB. |
| `com.android.vending` | Play Store | No Google account on the TV, so it can't install anything; its background process used 33 MB. |
| `com.google.android.youtube.tvmusic` | YouTube Music | Not used. |
| `com.google.android.backdrop` | Screensaver | Downloads photos from the internet. |
| `com.google.android.apps.nbu.smartconnect.tv` | Data Saver | VPN-based data saving, not used. |
| `fusion.android.tv.demo`, `com.smartdevice.common.demonow` | Store demo apps | Were running in the background. |
| `com.Smartdevice.emanual` | E-manual | Unneeded tile. |
| `com.airoha.ble.ota` | RC Upgrade | Firmware updater for Bluetooth remotes. |
| `com.mstar.netflixobserver` | MStar Netflix helper | Netflix isn't installed, ~4 MB. |
| `com.mstar.android.tv.disclaimercustomization` | MStar disclaimer tool | Unneeded tile. |

Left alone: Google Play services (YouTube depends on it), Gboard, the live TV services (`tvcenter`, `dtv_svc`,
`mtktvapi`, `tvinput`), `com.mediatek.hotkey.dispatcher` (handles the remote's YouTube button), setup wizards.

### 3. Home screen: Couchy Launcher

[Couchy Launcher](https://f-droid.org/packages/com.conreo.couchytv/) (F-Droid, GPL-3): no ads, no network requests
with default settings, no background services.

On this TV `cmd package set-home-activity` returns "Success", yet the Home key stays bound to Google's home screen.
The only fix is disabling `tvlauncher`; then Couchy is the only home screen the Home key can open. The old Leanback
launcher in the package list doesn't work as a home screen here (it has no HOME activity).

### 4. Browser: TV Bro

[TV Bro](https://github.com/truefedex/tv-bro): open source, built for TV remotes, with an ad blocker. With no Google
account on the TV, we skipped Play Store and installed the developer's GitHub build (`generic-geckoExcluded`). It uses
the WebView engine, which the developer recommends for weak devices. Ad blocking is on and the automatic update check
is off, so nobody at home gets an "update/install" prompt.

### 5. HbbTV off

With live TV on: MENU → Advanced Options → HbbTV Settings → HbbTV Support: Off. Our TV's menu is in Turkish
(Gelişmiş Seçenekler → HbbTV Ayarları → HbbTV Desteği); the English names are translations and may read slightly
differently on your TV.

HbbTV is the interactive apps that channels broadcast alongside the program, opened with the red button. The TV runs
an embedded web browser in the background for them and keeps each HbbTV channel's app in memory. Turning it off
doesn't affect normal viewing. The browser shell itself (`teatro_tv_browser`, ~33 MB) is still loaded at boot by
MediaTek's `app_man` service, and it can't be stopped without root.

### 6. Log level

```
adb shell setprop persist.log.tag W
```

Android's log library checks this value and drops every line below warning level before it is written. Apps aren't
affected and the setting survives reboots. **From ~12,000 lines per minute down to 12.**

### 7. Animations at half duration

```
adb shell settings put global window_animation_scale 0.5
adb shell settings put global transition_animation_scale 0.5
adb shell settings put global animator_duration_scale 0.5
```

### 8. Gerçek Kapat

What a single press of the power button does is set in Android's system configuration and can't be changed without
root. Instead, a small app catches the moment the screen turns off and, when needed, powers the TV off for real:

- Between **23:00 and 06:00**, if the TV hasn't really been off for at least **3 days** → real power-off.
- If the TV hasn't been off for more than **5 days** → real power-off at any hour.
- Otherwise → normal sleep, instant wake-up.

It powers off by connecting to the TV's own ADB from inside (`127.0.0.1:5555`) and running `reboot -p`. The app's own
ADB key is approved on the TV once. It has no icon and is managed over ADB only. A cold boot takes 40–45 seconds, which
is why it doesn't power off on every press.

Source, install and settings commands: [`gercek-kapat/`](gercek-kapat/). APK:
[Releases](https://github.com/if-kurt/beko-android-tv-speedup/releases).

### Tried, didn't work

- **`svc power shutdown`**: swallowed without an error; the TV stays on. `reboot -p` works.
- **`setprop persist.adb.tcp.port 5555`**: the ADB shell can't write this property. Not needed anyway, the port opens
  at boot.
- **Skyworth's factory app (`com.coocaa.factory`, ~25 MB)**: it can be disabled, but the TV enables it again at boot.
  Left alone.
- **The old Leanback launcher**: doesn't open as a home screen on this TV.

## Result

| | Before (up 2.5 days) | After |
|---|---|---|
| Available RAM | 174 MB | ~300 MB |
| Free swap | 2 MB | 106 MB (same session, no reboot) |
| Logs | ~12,000 lines/minute | 12 lines/minute |
| Home screen | Google, with ad and movie store rows | Couchy |
| Power button | always sleep | real power-off every few nights |

Next: a lighter TV keyboard instead of Gboard (~75 MB at boot).

## Applying it to the same TV

On Windows, with [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools) (`adb`) on
PATH and USB debugging on:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\apply.ps1 -TvIp 192.168.1.50
```

The script connects to the TV and checks the model, writes the current state to a backup file, downloads and installs
Couchy, TV Bro and Gerçek Kapat, makes Couchy the home screen, disables the packages in
[`scripts/packages.ps1`](scripts/packages.ps1), sets the log level and animations, and pairs Gerçek Kapat. It prints
the few manual steps at the end (HbbTV, Couchy's first run, TV Bro settings).

- `-KeepVoiceSearch`: keeps the Google app, for remotes with a microphone. It took ~155 MB of RAM on our TV, so only
  use it if someone really uses voice search.
- `-KeepCast`: keeps Chromecast, if anyone casts from a phone.
- `-SkipGercekKapat`: doesn't install Gerçek Kapat.
- If the TV has a Google account, Play Store is left alone.

To undo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1 -TvIp 192.168.1.50
```

The scripts were written for this model. On another model, check the package list against your TV first.

## Security

- Gerçek Kapat needs network ADB to stay on. If a device on the network tries to connect, the TV shows a permission
  prompt; don't approve one you don't recognize. Don't forward port 5555 on your router.
- Gerçek Kapat's ADB key stays in the app's private folder and is only used for `reboot -p`.
- Streaming sites are full of pop-ups and fake "download/play" buttons. Keep TV Bro's ad blocker on and never install
  files that a site downloads.

## Credits

- [couch-tv](https://github.com/Seagey/couch-tv): the idea that started this.
- [Couchy Launcher](https://f-droid.org/packages/com.conreo.couchytv/), [TV Bro](https://github.com/truefedex/tv-bro).

## License

[MIT](LICENSE). Couchy Launcher and TV Bro have their own licenses; their code isn't in this repo, the script
downloads them from their own sources.
