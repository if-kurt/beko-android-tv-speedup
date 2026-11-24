# Beko Android TV hızlandırma

Yavaşlayan bir Beko Android TV'yi root'suz, sadece ADB ile nasıl hızlandırdığımızın notları. Bir de işin en inatçı
parçası için küçük bir uygulama: **Gerçek Kapat**. Kumandanın güç tuşuna tek basıldığında TV'yi uyutmak yerine,
gerektiğinde gerçekten kapatıyor.

Hepsi geri alınabilir. Hiçbir sistem uygulaması silinmedi, sadece kapatıldı.

*English summary at the bottom.*

## Televizyon

| | |
|---|---|
| Model | Beko Android TV (`ro.product.name=Beko_EU`, `ro.product.device=shinagawa`) |
| Kartı üreten | Skyworth (`ro.product.manufacturer=skyworth`) |
| Çip | MStar/MediaTek `m5621` |
| RAM | ~1 GB (909 MB görünüyor), Android onu "düşük RAM cihazı" sayıyor (`ro.config.low_ram=true`) |
| Android | Android TV 9 (API 28), yazılım Aralık 2021 (`PT07.211208.001`) |

## Sorun neydi

Belirti: menüler ağır, kumandanın tuşları geç ya da yarım algılanıyor, TV günler geçtikçe daha da yavaşlıyor.

TV 2,5 gündür hiç yeniden başlamamışken ölçtüklerimiz:

- **Bellek bitmişti.** Kullanılabilir RAM 174 MB. 300 MB'lık swap (RAM içinde sıkıştırılmış alan, zram) tamamen
  doluydu, 2 MB kalmıştı. Çekirdeğin bellek temizleyicisi `kswapd0` durmadan çalışıyordu (o an %19 CPU, toplam 26
  dakika). Arayüz bellek bekledikçe kumanda tuşları gecikiyor.
- **Load average 108 yanıltıcıydı.** Bekleme (D) durumundaki ~109 görevin hepsi MStar'ın sürücü thread'leri
  (`VMon_Task`, `DMX_Filt_Task`, `VDEC_*` …). Linux onları load average'a sayıyor ama CPU harcamıyorlar; CPU'nun
  %70'i boştaydı. Bunlar çekirdek seviyesinde, dokunulmadı.
- **RAM'i yiyenler:** Google uygulaması (`katniss`, sesli arama) iki süreçte 155 MB, HbbTV tarayıcısı ~63 MB,
  Play Store'un arka plan süreci 33 MB, Skyworth'un fabrika uygulaması 25 MB, Chromecast 21 MB, ayrıca Google'ın ana
  ekranı, öneri servisleri ve mağaza demo uygulamaları.
- **Log seli:** Dakikada ~12.000 log satırı yazılıyordu, en çok canlı TV uygulaması `tvcenter`. `logd` ile
  üreticinin `k2logcat` servisi birlikte 35 dakika CPU harcamıştı.
- **Güç tuşu TV'yi kapatmıyor, uyutuyor.** Kısa basış TV'yi RAM'de uyutuyor (STR, Suspend to RAM;
  `ro.vendor.mstar.str.enable=user_mode`). Gerçek kapatma için tuşa 5 saniye basılı tutup "Tamam" demek gerekiyor;
  evde kimse öyle kapatmıyor. TV haftalarca yeniden başlamıyor, bellek sorunları birikiyor.

## Ne yaptık, neden

### 1. ADB

Ayarlar → Cihaz Tercihleri → Hakkında → Derleme'ye 7 kez bas, Geliştirici seçenekleri'nden USB hata ayıklamayı aç.
Bu TV'de ağ üzerinden ADB'yi ayrıca açan bir anahtar yok ama 5555 portu kendiliğinden açılıyor
(`service.adb.tcp.port=5555`), kablo gerekmedi. İlk bağlantıda TV'de izin penceresi çıkar.

```
adb connect TV_IP:5555
```

### 2. Paketleri kapatmak

`pm disable-user --user 0 <paket>` ile. Uygulama yerinde kalıyor ama hiçbir parçası çalışmıyor;
`pm enable <paket>` ile geri geliyor. Silmekle (`pm uninstall --user 0`) arasında hız farkı yok: sistem uygulamalarının
dosyası salt okunur bölümde durduğu için silmek yer de açmıyor.

| Paket | Ne | Neden kapatıldı |
|---|---|---|
| `com.google.android.tvlauncher` | Google ana ekranı | Reklam ve öneri satırları, ağır. Yerine Couchy. |
| `com.google.android.tvrecommendations` | Android TV Core Services | Ana ekran önerileri, yeni ana ekranda işe yaramıyor. |
| `com.mediatek.wwtv.tvrecommendation` | MediaTek canlı TV öneri satırı | ~9 MB, sadece ana ekran satırı için. Kanallar etkilenmiyor. |
| `com.google.android.katniss` | Google uygulaması (sesli arama, Asistan) | ~155 MB, sürekli bellekte. Bu kumandada mikrofon tuşu yok. |
| `com.google.android.speech.pumpkin` | Çevrimdışı ses tanıma | katniss ile birlikte. |
| `com.google.android.apps.mediashell` | Chromecast | Kullanılmıyor, ~21 MB. |
| `com.google.android.tv.remote.service` | Telefondan kumanda servisi | Kullanılmıyor, ~12 MB. |
| `com.android.vending` | Play Store | TV'de Google hesabı yok, hiçbir şey kuramıyor; arka plan süreci 33 MB. |
| `com.google.android.youtube.tvmusic` | YouTube Music | Kullanılmıyor. |
| `com.google.android.backdrop` | Ekran koruyucu | İnternetten fotoğraf çekiyor. |
| `com.google.android.apps.nbu.smartconnect.tv` | Data Saver | VPN tabanlı veri tasarrufu, kullanılmıyor. |
| `fusion.android.tv.demo`, `com.smartdevice.common.demonow` | Mağaza demo uygulamaları | Arka planda çalışıyordu. |
| `com.Smartdevice.emanual` | E-kılavuz | Gereksiz kutucuk. |
| `com.airoha.ble.ota` | RC Upgrade | Bluetooth kumandanın yazılım güncelleyicisi; bu kumanda kızılötesi. |
| `com.mstar.netflixobserver` | MStar Netflix yardımcısı | Netflix kurulu değil, ~4 MB. |
| `com.mstar.android.tv.disclaimercustomization` | MStar yasal uyarı aracı | Gereksiz kutucuk. |

Dokunulmayanlar: Google Play Hizmetleri (YouTube buna bağlı), Gboard, canlı TV servisleri (`tvcenter`, `dtv_svc`,
`mtktvapi`, `tvinput`), kumandanın YouTube tuşunu yöneten `com.mediatek.hotkey.dispatcher`, kurulum sihirbazları.

### 3. Ana ekran: Couchy Launcher

[Couchy Launcher](https://f-droid.org/packages/com.conreo.couchytv/) (F-Droid, GPL-3): reklam yok, varsayılan
ayarlarda ağ isteği yok, arka plan servisi yok.

Bu TV'de `cmd package set-home-activity` "Success" dönse de Home tuşu Google'ın ana ekranına sabit kalıyor. Tek
çözüm `tvlauncher`'ı kapatmak; o zaman Home tuşunun açabileceği tek ana ekran Couchy kalıyor. Paket listesinde
görünen eski Leanback ana ekranı bu TV'de ana ekran olarak çalışmıyor (HOME aktivitesi yok).

### 4. Tarayıcı: TV Bro

[TV Bro](https://github.com/truefedex/tv-bro) (açık kaynak, kumanda için yapılmış, reklam engelleyicili).
TV'de Google hesabı olmadığı için Play Store yerine geliştiricinin GitHub sürümü (`generic-geckoExcluded`):
WebView motorunu kullanıyor, geliştirici zayıf cihazlara bunu öneriyor. Ayarlardan reklam engelleyici açık,
otomatik güncelleme denetimi kapalı; evdekilerin karşısına "güncelle/kur" penceresi çıkmıyor.

### 5. HbbTV kapalı

Canlı TV açıkken MENU → Gelişmiş Seçenekler → HbbTV Ayarları → HbbTV Desteği: Kapalı.

HbbTV, kanalların yayınla birlikte gönderdiği, kırmızı tuşla açılan etkileşimli uygulamalar. TV bunun için arka
planda gömülü bir web tarayıcısı çalıştırıyor ve HbbTV'li her kanalda o kanalın uygulamasını bellekte tutuyor.
Kapatınca normal yayın etkilenmiyor. Tarayıcının kendisi (`teatro_tv_browser`, ~33 MB) yine de açılışta MediaTek'in
`app_man` servisi tarafından yükleniyor; root olmadan durdurulamıyor.

### 6. Log seviyesi

```
adb shell setprop persist.log.tag W
```

Android'in log kütüphanesi bu değere bakıp uyarı (W) seviyesinin altındaki satırları hiç yazmadan atıyor.
Uygulamalar etkilenmiyor, ayar kalıcı. **Dakikada ~12.000 satırdan 12 satıra indi.**

### 7. Animasyonlar yarı sürede

```
adb shell settings put global window_animation_scale 0.5
adb shell settings put global transition_animation_scale 0.5
adb shell settings put global animator_duration_scale 0.5
```

### 8. Gerçek Kapat

Güç tuşuna tek basışın davranışı Android'in sistem yapılandırmasında; root olmadan değişmiyor. Bunun yerine küçük
bir uygulama ekran kapandığı anı yakalıyor ve gerekiyorsa TV'yi gerçekten kapatıyor:

- Saat **23:00–06:00** arasıysa ve TV en az **3 gündür** gerçekten kapanmadıysa → gerçek kapatma.
- TV **5 günden** uzun süredir hiç kapanmadıysa → saatten bağımsız gerçek kapatma.
- Diğer durumlarda → normal uyku, anında açılış.

Kapatmayı TV'nin kendi ADB'sine içeriden (`127.0.0.1:5555`) bağlanıp `reboot -p` çalıştırarak yapıyor. Uygulamanın
kendi ADB anahtarı bir kez TV'de onaylanıyor. Simgesi yok, sadece ADB ile yönetiliyor. Soğuk açılış 40–45 saniye
sürdüğü için her basışta değil, aralıklarla kapatıyor.

Kaynak kodu, kurulum ve ayar komutları: [`gercek-kapat/`](gercek-kapat/). APK: [Releases](https://github.com/if-kurt/beko-android-tv-speedup/releases).

### Denenip işe yaramayanlar

- **`svc power shutdown`**: komut hata vermeden yutuluyor, TV kapanmıyor. `reboot -p` çalışıyor.
- **`setprop persist.adb.tcp.port 5555`**: ADB kabuğu bu değeri yazamıyor. Gerek de kalmadı, port açılışta zaten açılıyor.
- **Skyworth'un fabrika uygulaması (`com.coocaa.factory`, ~25 MB)**: kapatılıyor ama TV açılışta onu yeniden
  etkinleştiriyor. Bırakıldı.
- **Eski Leanback ana ekranı**: bu TV'de ana ekran olarak açılmıyor.

## Sonuç

| | Önce (2,5 gün açık) | Sonra |
|---|---|---|
| Kullanılabilir RAM | 174 MB | ~300 MB |
| Boş swap | 2 MB | 106 MB (aynı oturumda, yeniden başlatmadan) |
| Log | ~12.000 satır/dakika | 12 satır/dakika |
| Ana ekran | Google, reklam ve film mağazası satırları | Couchy |
| Güç tuşu | hep uyku | gece ve 3 günde bir gerçek kapatma |

Sırada: Gboard (açılışta ~75 MB) yerine daha hafif bir TV klavyesi.

## Aynı TV'de uygulamak

Windows'ta, [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools) (`adb`)
PATH'teyken, TV'de USB hata ayıklama açıkken:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\apply.ps1 -TvIp 192.168.1.50
```

Betik TV'ye bağlanır ve modeli kontrol eder, mevcut durumu bir yedek dosyasına yazar, Couchy, TV Bro ve Gerçek
Kapat'ı indirip kurar, Couchy'yi ana ekran yapar, [`scripts/packages.ps1`](scripts/packages.ps1)'deki paketleri
kapatır, log seviyesi ve animasyon ayarlarını yapar, Gerçek Kapat'ı eşleştirir. Elle yapılacak birkaç adımı
(HbbTV, Couchy'nin ilk kurulumu, TV Bro ayarları) en sonda yazar.

- `-KeepVoiceSearch`: kumandada mikrofon varsa Google uygulamasını kapatmaz.
- `-KeepCast`: telefondan yansıtma kullanılıyorsa Chromecast'i kapatmaz.
- `-SkipGercekKapat`: Gerçek Kapat'ı kurmaz.
- TV'de Google hesabı varsa Play Store'a dokunmaz.

Geri almak için:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1 -TvIp 192.168.1.50
```

Betik bu modele göre yazıldı. Farklı bir modelde paket listesini kendi TV'ne göre kontrol et.

## Güvenlik

- Gerçek Kapat için ağ üzerinden ADB açık kalıyor. Ağdaki bir cihaz TV'ye bağlanmak isterse TV'de izin penceresi
  çıkar; tanımadığın pencereye izin verme. Modemde 5555 portunu dışarı açma.
- Gerçek Kapat'ın ADB anahtarı uygulamanın özel klasöründe duruyor ve sadece `reboot -p` için kullanılıyor.
- Film sitelerinde açılır pencereler ve sahte "indir/oynat" düğmeleri olur. TV Bro'nun reklam engelleyicisi açık
  kalsın, sitelerin indirttiği hiçbir dosya kurulmasın.

## Teşekkürler

- [couch-tv](https://github.com/Seagey/couch-tv): bu işe başlatan fikir.
- [Couchy Launcher](https://f-droid.org/packages/com.conreo.couchytv/), [TV Bro](https://github.com/truefedex/tv-bro).

## Lisans

[MIT](LICENSE). Couchy Launcher ve TV Bro kendi lisanslarıyla dağıtılıyor; bu repoda kodları yok, betik onları
kendi kaynaklarından indiriyor.

---

## English summary

Notes on speeding up a Beko Android TV (Skyworth board, MStar/MediaTek `m5621`, ~1 GB RAM, Android TV 9) without
root, over ADB only, and **Gerçek Kapat** ("really power off"), a tiny app that turns the remote's single power press
into a real shutdown when the TV has been sleeping for days.

- **Diagnosis:** after 2.5 days without a reboot, 174 MB available RAM and a completely full 300 MB zram swap with
  `kswapd0` constantly busy. The load average of 108 is misleading: ~109 MStar driver kernel threads sit in D state
  while the CPU is 70% idle. Big consumers: Google app `katniss` (155 MB), the HbbTV browser (~63 MB), Play Store
  background (33 MB). Logging ran at ~12,000 lines per minute. The power button only suspends to RAM (STR), so the TV
  never reboots.
- **Fixes:** disable 17 packages (`pm disable-user`, nothing uninstalled; list in `scripts/packages.ps1`), replace the
  Google home with Couchy Launcher (on this TV the Home key stays bound to `tvlauncher` until it is disabled), TV Bro
  as the browser, HbbTV off in the TV menu, `setprop persist.log.tag W` (12,000 → 12 log lines per minute), animation
  scale 0.5.
- **Gerçek Kapat:** on screen-off it checks the time and the uptime (default: between 23:00 and 06:00 after 3 days, or
  any time after 5 days), holds a wake lock, connects to the TV's own adbd at `127.0.0.1:5555` with its own
  authorized key and runs `reboot -p`. `svc power shutdown` is swallowed by this firmware. Source in `gercek-kapat/`,
  APK in Releases.
- **Result:** ~300 MB available RAM instead of 174 MB; the TV now really powers off every few nights.
- `scripts/apply.ps1` applies everything to the same model from Windows; `scripts/restore.ps1` undoes it.
