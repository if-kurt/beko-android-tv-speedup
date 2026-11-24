# Beko Android TV (Skyworth, MStar m5621, Android TV 9) üzerinde kapatılan paketler.
# apply.ps1 kapatır, restore.ps1 geri açar. Kullandığın bir şey varsa o satırı sil ya da başına # koy.
# Hiçbiri silinmez: "pm disable-user" ile kapatılır, "pm enable" ile geri gelir.

$BekoPackages = [ordered]@{
    # Ana ekran: önce Couchy kurulup ana ekran yapılır, sonra bunlar kapanır.
    'com.google.android.tvlauncher'                = 'Google ana ekranı: reklam ve öneri satırları (yerine Couchy)'
    'com.google.android.tvrecommendations'         = 'Android TV Core Services: ana ekran önerileri'
    'com.mediatek.wwtv.tvrecommendation'           = 'MediaTek canlı TV öneri satırı'

    # Google
    'com.google.android.katniss'                   = 'Google uygulaması: sesli arama ve Asistan (~155 MB)'
    'com.google.android.speech.pumpkin'            = 'Çevrimdışı ses tanıma (katniss ile birlikte)'
    'com.google.android.apps.mediashell'           = 'Chromecast: telefondan yansıtma'
    'com.google.android.tv.remote.service'         = 'Telefondan kumanda servisi'
    'com.android.vending'                          = 'Play Store (TV''de Google hesabı varsa apply.ps1 dokunmaz)'
    'com.google.android.youtube.tvmusic'           = 'YouTube Music'
    'com.google.android.backdrop'                  = 'İnternetten fotoğraf çeken ekran koruyucu'
    'com.google.android.apps.nbu.smartconnect.tv'  = 'Data Saver: VPN tabanlı veri tasarrufu'

    # Üretici
    'fusion.android.tv.demo'                       = 'Mağaza demo uygulaması'
    'com.smartdevice.common.demonow'               = 'Mağaza demo uygulaması'
    'com.Smartdevice.emanual'                      = 'E-kılavuz'
    'com.airoha.ble.ota'                           = 'RC Upgrade: Bluetooth kumanda yazılım güncelleyici'
    'com.mstar.netflixobserver'                    = 'MStar Netflix yardımcısı (Netflix kurulu değilse)'
    'com.mstar.android.tv.disclaimercustomization' = 'MStar yasal uyarı aracı'
}
