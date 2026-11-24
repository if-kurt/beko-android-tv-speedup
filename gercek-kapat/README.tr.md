# Gerçek Kapat

[English](README.md) | **Türkçe**

Beko (Skyworth, MStar/MediaTek, Android TV 9) için küçük bir yardımcı uygulama. Güç tuşuna tek basınca TV normalde
RAM'de uyuyor (STR) ve haftalarca yeniden başlamadan ağırlaşıyor. Bu uygulama, tuşa basıldığı anda koşullar
uygunsa TV'yi uyutmak yerine gerçekten kapatıyor (`reboot -p`). Evdekilerin alışkanlığı değişmiyor.

Simgesi yok, ana ekranda görünmüyor. Sadece ADB ile yönetiliyor. APK ~20 KB, root gerekmiyor.

## Nasıl karar veriyor

Ekran kapanınca (güç tuşu, otomatik kapanma vb.):

- Saat **23:00–06:00** arasındaysa ve TV en az **72 saattir** gerçekten kapanmadıysa → gerçek kapatma.
- TV **120 saatten** (5 gün) uzun süredir hiç kapanmadıysa → saatten bağımsız gerçek kapatma.
- Diğer durumlarda → normal uyku (anında açılış).

Gerçek kapatmadan önce 3 saniye bekliyor ve şu durumlarda vazgeçiyor: ekran tekrar açıldıysa, arada TV uyuduysa
(20 saniyeden fazla gecikme), ses çalıyorsa ya da ADB izni yoksa. En kötü sonuç TV'nin normal uykuya geçmesi.

## Nasıl çalışıyor

- `WatchService` ön plan servisi olarak çalışıyor, açılışta `BOOT_COMPLETED` ile kendiliğinden başlıyor.
- Ekran kapanınca `Policy` karar veriyor. Kapatılacaksa bir wake lock tutup TV'nin uykuya geçmesini birkaç saniye
  erteliyor.
- `AdbClient`, ADB'nin TCP protokolünü (CNXN/AUTH/OPEN) konuşan küçük bir istemci. TV'nin kendi adbd'sine
  `127.0.0.1:5555` üzerinden bağlanıp `shell:reboot -p` çalıştırıyor. Bu firmware'de `svc power shutdown` yutuluyor,
  `reboot -p` çalışıyor.
- Uygulamanın 2048 bitlik RSA anahtarı ilk eşleştirmede üretiliyor ve özel klasöründe duruyor. TV ilk seferde
  "USB hata ayıklamaya izin verilsin mi?" diye soruyor.
- Servis yalnızca `android.permission.DUMP` sahiplerine (ADB kabuğu, sistem) açık; başka uygulamalar onu tetikleyemiyor.
- Olaylar küçük bir dosyaya yazılıyor; `dumpsys` ile okunuyor, kapanmadan önceki kayıtlar da korunuyor.

## Kurulum

APK'yı [Releases](https://github.com/if-kurt/beko-android-tv-speedup/releases) sayfasından indir:

```
adb install gercek-kapat-1.1.apk
adb shell am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.PAIR
```

TV'de "USB hata ayıklamaya izin verilsin mi?" penceresi çıkıyor. "Her zaman izin ver" kutusunu işaretleyip onayla.
Penceredeki parmak izi, durum çıktısındaki "anahtar" satırıyla aynı olmalı.

## Durum ve kayıtlar

```
adb shell dumpsys activity service io.github.ifkurt.gercekkapat/.WatchService
```

Örnek: gerçek TV'deki testin kayıtları, 1.1'in biçiminde:

```
2026-11-24 19:00:36  TEST armed: the next power button press will really power off
2026-11-24 19:01:12  screen off: real power-off (test) in 3000 ms
2026-11-24 19:01:15  sending reboot -p
2026-11-24 19:01:15  reboot -p finished
2026-11-24 19:02:46  service started 1.1, TV booted 0 h 1 min ago
```

Kayıtlar 1.1 sürümünden itibaren İngilizce yazılıyor.

## Test

Bir sonraki güç tuşu basışında koşullara bakmadan gerçek kapatma yapar (tek seferlik):

```
adb shell am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.TEST
```

## Ayarlar

```
adb shell am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.CONFIG --ei nightStart 23 --ei nightEnd 6 --ei nightMinHours 72 --ei anyMinHours 120 --ei graceMs 3000
```

Kapatmak için `--ez enabled false`, açmak için `--ez enabled true`. Sadece verdiğin değerler değişiyor.

## Kaldırma

```
adb uninstall io.github.ifkurt.gercekkapat
```

Uygulamanın ADB anahtarı TV'de onaylı kalıyor. Onu da silmek için Geliştirici seçenekleri → "USB hata ayıklama
yetkilerini kaldır" (bilgisayarın iznini de siler; bilgisayar bir sonraki bağlantıda tekrar onay ister).

## Derleme

Gradle gerekmiyor. Ubuntu/Debian'da (WSL de olur):

```
sudo apt install android-sdk-platform-23 aapt dalvik-exchange zipalign apksigner default-jdk
keytool -genkeypair -keystore release.jks -storetype PKCS12 -alias gercekkapat -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Gercek Kapat"
KS_PASS='keystore-sifren' sh build.sh
```

Çıktı: `build/gercek-kapat-<sürüm>.apk`. Kendi anahtarınla imzaladığın APK, Releases'teki APK'nın üzerine
güncelleme olarak kurulamaz; önce onu kaldır.

## Testler

`test/` klasöründeki `mock_adbd.py`, gerçek adbd gibi davranan katı bir sahte sunucu. Çerçeve yapısını, sağlama
toplamını, imzayı ve anahtar biçimini denetliyor. `AdbClientTest.java` istemciyi ona karşı çalıştırıyor, karar
kurallarını da sınıyor. Anahtar biçimi ve imzalar, gerçek cihazlara bağlanan
[adb-shell](https://github.com/JeffLIrion/adb_shell) kütüphanesinin ürettiğiyle bayt bayt aynı.

```
mkdir -p /tmp/gk && javac -d /tmp/gk src/io/github/ifkurt/gercekkapat/{Base64,AdbClient,Keys,Policy}.java test/AdbClientTest.java
python3 test/mock_adbd.py 47555 &
java -cp /tmp/gk io.github.ifkurt.gercekkapat.AdbClientTest 47555 /tmp/gk-keys
```
