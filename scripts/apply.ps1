<#
.SYNOPSIS
    Beko Android TV (Skyworth, MStar m5621, Android TV 9) hızlandırma ayarlarını ADB ile uygular.

.DESCRIPTION
    Sırasıyla:
      1. TV'ye ağ üzerinden bağlanır ve modeli kontrol eder.
      2. Mevcut durumu bir yedek dosyasına yazar.
      3. Couchy Launcher, TV Bro ve Gerçek Kapat'ı indirip kurar.
      4. Couchy'yi ana ekran yapar, packages.ps1'deki paketleri kapatır (silmez).
      5. Log seviyesini W yapar, animasyon sürelerini yarıya indirir.
      6. Gerçek Kapat'ı TV ile eşleştirir (TV'de izin penceresi çıkar).
    Elle yapılacak birkaç adım en sonda yazılır. Hepsi restore.ps1 ile geri alınır.

.PARAMETER TvIp
    TV'nin IP adresi (TV'de Ayarlar > Ağ ve İnternet).

.PARAMETER KeepVoiceSearch
    Google uygulamasını (sesli arama) kapatma. Kumandada mikrofon tuşu varsa bunu kullan.

.PARAMETER KeepCast
    Chromecast'i kapatma. Telefondan TV'ye yansıtma kullanılıyorsa bunu kullan.

.PARAMETER SkipGercekKapat
    Gerçek Kapat'ı kurma.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\apply.ps1 -TvIp 192.168.1.50
#>
param(
    [Parameter(Mandatory = $true)][string]$TvIp,
    [switch]$KeepVoiceSearch,
    [switch]$KeepCast,
    [switch]$SkipGercekKapat
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'packages.ps1')

$Target = "$($TvIp):5555"
$ThisRepo = 'if-kurt/beko-android-tv-speedup'
$Work = Join-Path ([System.IO.Path]::GetTempPath()) 'beko-tv-speedup'

function Get-LatestGitHubAsset([string]$Repo, [string]$Pattern, [string]$Fallback) {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
            -Headers @{ 'User-Agent' = 'beko-tv-speedup' } -TimeoutSec 30
        $asset = $release.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
        if ($asset) { return $asset.browser_download_url }
    } catch { }
    return $Fallback
}

function Get-LatestFDroidApk([string]$AppId, [string]$Fallback) {
    try {
        $info = Invoke-RestMethod -Uri "https://f-droid.org/api/v1/packages/$AppId" -TimeoutSec 30
        if ($info.suggestedVersionCode) { return "https://f-droid.org/repo/$($AppId)_$($info.suggestedVersionCode).apk" }
    } catch { }
    return $Fallback
}

function Save-File([string]$Url, [string]$Name) {
    $path = Join-Path $Work $Name
    Write-Host "   indiriliyor: $Url"
    & curl.exe -fsSL --retry 2 -o $path $Url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $path) -or (Get-Item $path).Length -lt 10000) {
        throw "İndirilemedi: $Url"
    }
    return $path
}

function Install-Apk([string]$Path) {
    $out = (& adb -s $Target install -r $Path 2>&1 | Out-String).Trim()
    if ($out -notmatch 'Success') { throw "Kurulamadı ($Path): $out" }
    Write-Host "   kuruldu: $(Split-Path $Path -Leaf)"
}

Assert-Command 'adb' 'Android SDK Platform-Tools kurulu ve PATH''te olmalı.'
Assert-Command 'curl.exe' 'Windows 10 (1803) ve sonrasıyla birlikte gelir.'

Connect-Tv

Write-Step 'Model kontrolü'
$model = Invoke-AdbShell 'getprop ro.product.model'
$platform = Invoke-AdbShell 'getprop ro.board.platform'
$sdk = Invoke-AdbShell 'getprop ro.build.version.sdk'
Write-Host "   model: $model, çip: $platform, API: $sdk"
if ($model -ne 'Beko Android TV' -or $platform -ne 'm5621' -or $sdk -ne '28') {
    Write-Warning 'Bu betik yalnızca Beko Android TV (MStar m5621, Android 9) üzerinde denendi. packages.ps1 listesini kendi TV''ne göre kontrol et.'
    if ((Read-Host 'Yine de devam edilsin mi? (e/h)') -ne 'e') { exit 1 }
}

Write-Step 'Yedek'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path (Get-Location) ('yedek-{0}-{1}.txt' -f ($TvIp -replace '\.', '-'), $stamp)
@(
    "# $Target  $(Get-Date -Format s)",
    '# kapalı paketler',
    (Invoke-AdbShell 'pm list packages -d'),
    '# ana ekran',
    (Invoke-AdbShell 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'),
    '# animasyonlar ve log seviyesi',
    (Invoke-AdbShell 'settings get global window_animation_scale; settings get global transition_animation_scale; settings get global animator_duration_scale; getprop persist.log.tag')
) | Set-Content -Path $backupFile -Encoding UTF8
Write-Host "   $backupFile"

Write-Step 'Uygulamalar indiriliyor'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$couchy = Save-File (Get-LatestFDroidApk 'com.conreo.couchytv' 'https://f-droid.org/repo/com.conreo.couchytv_7.apk') 'couchy.apk'
$tvbro = Save-File (Get-LatestGitHubAsset 'truefedex/tv-bro' '*-generic-geckoExcluded.apk' `
        'https://github.com/truefedex/tv-bro/releases/download/v3.0.7/tvbro-3.0.7-generic-geckoExcluded.apk') 'tvbro.apk'
if (-not $SkipGercekKapat) {
    $gercekKapat = Save-File (Get-LatestGitHubAsset $ThisRepo 'gercek-kapat-*.apk' `
            "https://github.com/$ThisRepo/releases/download/v1.0/gercek-kapat-1.0.apk") 'gercek-kapat.apk'
}

Write-Step 'Uygulamalar kuruluyor'
Install-Apk $couchy
Install-Apk $tvbro
if (-not $SkipGercekKapat) { Install-Apk $gercekKapat }

Write-Step 'Ana ekran: Couchy'
Write-Host "   $(Invoke-AdbShell 'cmd package set-home-activity com.conreo.couchytv/.MainActivity')"

Write-Step 'Paketler kapatılıyor (silinmiyor)'
$skip = @()
if ($KeepVoiceSearch) { $skip += 'com.google.android.katniss', 'com.google.android.speech.pumpkin' }
if ($KeepCast) { $skip += 'com.google.android.apps.mediashell' }
if ((Invoke-AdbShell 'dumpsys account | grep -m1 Accounts:') -match 'Accounts:\s*[1-9]') {
    $skip += 'com.android.vending'
    Write-Host '   TV''de Google hesabı var: Play Store açık bırakılıyor.'
}
$installed = @{}
foreach ($line in ((Invoke-AdbShell 'pm list packages') -split "`r?`n")) {
    if ($line -match '^package:(.+)$') { $installed[$Matches[1].Trim()] = $true }
}
foreach ($pkg in $BekoPackages.Keys) {
    $note = $BekoPackages[$pkg]
    if ($skip -contains $pkg) { Write-Host "   atlandı:    $pkg ($note)"; continue }
    if (-not $installed.ContainsKey($pkg)) { Write-Host "   yok:        $pkg"; continue }
    $result = Invoke-AdbShell "pm disable-user --user 0 $pkg"
    if ($result -match 'disabled') { Write-Host "   kapatıldı:  $pkg ($note)" }
    else { Write-Warning "$pkg kapatılamadı: $result" }
}

Write-Step 'Log seviyesi ve animasyonlar'
Invoke-AdbShell 'setprop persist.log.tag W' | Out-Null
foreach ($key in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
    Invoke-AdbShell "settings put global $key 0.5" | Out-Null
}
Write-Host "   persist.log.tag = $(Invoke-AdbShell 'getprop persist.log.tag'), animasyonlar 0.5"
Invoke-AdbShell 'input keyevent KEYCODE_HOME' | Out-Null

if (-not $SkipGercekKapat) {
    Write-Step 'Gerçek Kapat eşleştiriliyor'
    Invoke-AdbShell 'am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.PAIR' | Out-Null
    Write-Host "   TV'de izin penceresi çıkacak: 'Her zaman izin ver' kutusunu işaretleyip onayla."
    $paired = $false
    $deadline = (Get-Date).AddSeconds(150)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        if ((Invoke-AdbShell 'dumpsys activity service io.github.ifkurt.gercekkapat/.WatchService') -match 'tamam \(ok') {
            $paired = $true
            break
        }
    }
    if ($paired) { Write-Host '   eşleştirme tamam' }
    else {
        Write-Warning ('Eşleştirme doğrulanamadı. Tekrar dene: adb shell am startservice -n ' +
            'io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.PAIR')
    }
}

Write-Step 'Elle yapılacaklar'
Write-Host '   1. TV''de Couchy''nin kurulum adımlarını bitir (VPN adımında "Atla"), gereksiz kutucukları gizle.'
Write-Host '   2. Canlı TV açıkken MENU > Gelişmiş Seçenekler > HbbTV Ayarları > HbbTV Desteği: Kapalı.'
Write-Host '   3. TV Bro''yu bir kez aç: Ad blocking açık, Updates > Auto check for updates kapalı.'
Write-Host '   4. TV''yi bir kez yeniden başlat: adb reboot'
Write-Host ''
Write-Host "Yedek dosyası: $backupFile"
Write-Host "Geri almak için: powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1 -TvIp $TvIp"
