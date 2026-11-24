<#
.SYNOPSIS
    Applies the speed-up settings to a Beko Android TV (Skyworth, MStar m5621, Android TV 9) over ADB.

.DESCRIPTION
    In order:
      1. Connects to the TV over the network and checks the model.
      2. Writes the current state to a backup file.
      3. Downloads and installs Couchy Launcher, TV Bro and Gerçek Kapat.
      4. Makes Couchy the home screen and disables the packages in packages.ps1 (nothing is uninstalled).
      5. Sets the log level to W and halves animation durations.
      6. Pairs Gerçek Kapat with the TV (the TV shows a permission prompt).
    A few manual steps are printed at the end. restore.ps1 undoes everything.

.PARAMETER TvIp
    The TV's IP address (on the TV: Settings > Network & Internet).

.PARAMETER KeepVoiceSearch
    Keep the Google app (voice search). Use it if the remote has a microphone.

.PARAMETER KeepCast
    Keep Chromecast. Use it if anyone casts from a phone.

.PARAMETER SkipGercekKapat
    Do not install Gerçek Kapat.

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
    Write-Host "   downloading: $Url"
    & curl.exe -fsSL --retry 2 -o $path $Url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $path) -or (Get-Item $path).Length -lt 10000) {
        throw "Download failed: $Url"
    }
    return $path
}

function Install-Apk([string]$Path) {
    $out = (& adb -s $Target install -r $Path 2>&1 | Out-String).Trim()
    if ($out -notmatch 'Success') { throw "Install failed ($Path): $out" }
    Write-Host "   installed: $(Split-Path $Path -Leaf)"
}

Assert-Command 'adb' 'Android SDK Platform-Tools must be installed and on PATH.'
Assert-Command 'curl.exe' 'It ships with Windows 10 (1803) and later.'

Connect-Tv

Write-Step 'Model check'
$model = Invoke-AdbShell 'getprop ro.product.model'
$platform = Invoke-AdbShell 'getprop ro.board.platform'
$sdk = Invoke-AdbShell 'getprop ro.build.version.sdk'
Write-Host "   model: $model, SoC: $platform, API: $sdk"
if ($model -ne 'Beko Android TV' -or $platform -ne 'm5621' -or $sdk -ne '28') {
    Write-Warning 'This script was only tested on a Beko Android TV (MStar m5621, Android 9). Check packages.ps1 against your TV.'
    if ((Read-Host 'Continue anyway? (y/n)') -ne 'y') { exit 1 }
}

Write-Step 'Backup'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path (Get-Location) ('backup-{0}-{1}.txt' -f ($TvIp -replace '\.', '-'), $stamp)
@(
    "# $Target  $(Get-Date -Format s)",
    '# disabled packages',
    (Invoke-AdbShell 'pm list packages -d'),
    '# home screen',
    (Invoke-AdbShell 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'),
    '# animation scales and log level',
    (Invoke-AdbShell 'settings get global window_animation_scale; settings get global transition_animation_scale; settings get global animator_duration_scale; getprop persist.log.tag')
) | Set-Content -Path $backupFile -Encoding UTF8
Write-Host "   $backupFile"

Write-Step 'Downloading apps'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$couchy = Save-File (Get-LatestFDroidApk 'com.conreo.couchytv' 'https://f-droid.org/repo/com.conreo.couchytv_7.apk') 'couchy.apk'
$tvbro = Save-File (Get-LatestGitHubAsset 'truefedex/tv-bro' '*-generic-geckoExcluded.apk' `
        'https://github.com/truefedex/tv-bro/releases/download/v3.0.7/tvbro-3.0.7-generic-geckoExcluded.apk') 'tvbro.apk'
if (-not $SkipGercekKapat) {
    $gercekKapat = Save-File (Get-LatestGitHubAsset $ThisRepo 'gercek-kapat-*.apk' `
            "https://github.com/$ThisRepo/releases/download/v1.1/gercek-kapat-1.1.apk") 'gercek-kapat.apk'
}

Write-Step 'Installing apps'
Install-Apk $couchy
Install-Apk $tvbro
if (-not $SkipGercekKapat) { Install-Apk $gercekKapat }

Write-Step 'Home screen: Couchy'
Write-Host "   $(Invoke-AdbShell 'cmd package set-home-activity com.conreo.couchytv/.MainActivity')"

Write-Step 'Disabling packages (not uninstalling)'
$skip = @()
if ($KeepVoiceSearch) { $skip += 'com.google.android.katniss', 'com.google.android.speech.pumpkin' }
if ($KeepCast) { $skip += 'com.google.android.apps.mediashell' }
if ((Invoke-AdbShell 'dumpsys account | grep -m1 Accounts:') -match 'Accounts:\s*[1-9]') {
    $skip += 'com.android.vending'
    Write-Host '   The TV has a Google account: leaving Play Store on.'
}
$installed = @{}
foreach ($line in ((Invoke-AdbShell 'pm list packages') -split "`r?`n")) {
    if ($line -match '^package:(.+)$') { $installed[$Matches[1].Trim()] = $true }
}
foreach ($pkg in $BekoPackages.Keys) {
    $note = $BekoPackages[$pkg]
    if ($skip -contains $pkg) { Write-Host "   kept:        $pkg ($note)"; continue }
    if (-not $installed.ContainsKey($pkg)) { Write-Host "   not found:   $pkg"; continue }
    $result = Invoke-AdbShell "pm disable-user --user 0 $pkg"
    if ($result -match 'disabled') { Write-Host "   disabled:    $pkg ($note)" }
    else { Write-Warning "Could not disable $($pkg): $result" }
}

Write-Step 'Log level and animations'
Invoke-AdbShell 'setprop persist.log.tag W' | Out-Null
foreach ($key in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
    Invoke-AdbShell "settings put global $key 0.5" | Out-Null
}
Write-Host "   persist.log.tag = $(Invoke-AdbShell 'getprop persist.log.tag'), animation scales 0.5"
Invoke-AdbShell 'input keyevent KEYCODE_HOME' | Out-Null

if (-not $SkipGercekKapat) {
    Write-Step 'Pairing Gerçek Kapat'
    Invoke-AdbShell 'am startservice -n io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.PAIR' | Out-Null
    Write-Host "   The TV will show a permission prompt: tick 'Always allow' and confirm."
    $paired = $false
    $deadline = (Get-Date).AddSeconds(150)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        if ((Invoke-AdbShell 'dumpsys activity service io.github.ifkurt.gercekkapat/.WatchService') -match 'pairing done \(ok|tamam \(ok') {
            $paired = $true
            break
        }
    }
    if ($paired) { Write-Host '   paired' }
    else {
        Write-Warning ('Could not confirm pairing. Try again: adb shell am startservice -n ' +
            'io.github.ifkurt.gercekkapat/.WatchService -a io.github.ifkurt.gercekkapat.PAIR')
    }
}

Write-Step 'Manual steps'
Write-Host '   1. On the TV, finish Couchy''s first-run steps ("Skip" at the VPN step) and hide the tiles you do not need.'
Write-Host '   2. With live TV on: MENU > Advanced Options > HbbTV Settings > HbbTV Support: Off'
Write-Host '      (Turkish menu: Gelişmiş Seçenekler > HbbTV Ayarları > HbbTV Desteği; English names may differ slightly).'
Write-Host '   3. Open TV Bro once: Ad blocking on, Updates > Auto check for updates off.'
Write-Host '   4. Reboot the TV once: adb reboot'
Write-Host ''
Write-Host "Backup file: $backupFile"
Write-Host "To undo: powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1 -TvIp $TvIp"
