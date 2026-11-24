# Packages disabled on the Beko Android TV (Skyworth, MStar m5621, Android TV 9).
# apply.ps1 disables them, restore.ps1 enables them again. Delete a line, or put # in front of it, to keep that app.
# Nothing is uninstalled: "pm disable-user" turns a package off, "pm enable" brings it back.

$BekoPackages = [ordered]@{
    # Home screen: Couchy is installed and made the home screen first, then these go off.
    'com.google.android.tvlauncher'                = 'Google home screen: ad and recommendation rows (replaced by Couchy)'
    'com.google.android.tvrecommendations'         = 'Android TV Core Services: home screen recommendations'
    'com.mediatek.wwtv.tvrecommendation'           = 'MediaTek live TV recommendation row'

    # Google
    'com.google.android.katniss'                   = 'Google app: voice search and Assistant (~155 MB)'
    'com.google.android.speech.pumpkin'            = 'Offline speech recognition (goes with katniss)'
    'com.google.android.apps.mediashell'           = 'Chromecast: casting from a phone'
    'com.google.android.tv.remote.service'         = 'Phone-as-remote service'
    'com.android.vending'                          = 'Play Store (apply.ps1 leaves it alone if the TV has a Google account)'
    'com.google.android.youtube.tvmusic'           = 'YouTube Music'
    'com.google.android.backdrop'                  = 'Screensaver that downloads photos'
    'com.google.android.apps.nbu.smartconnect.tv'  = 'Data Saver: VPN-based data saving'

    # Manufacturer
    'fusion.android.tv.demo'                       = 'Store demo app'
    'com.smartdevice.common.demonow'               = 'Store demo app'
    'com.Smartdevice.emanual'                      = 'E-manual'
    'com.airoha.ble.ota'                           = 'RC Upgrade: firmware updater for Bluetooth remotes'
    'com.mstar.netflixobserver'                    = 'MStar Netflix helper (when Netflix is not installed)'
    'com.mstar.android.tv.disclaimercustomization' = 'MStar disclaimer tool'
}
