<#
.SYNOPSIS
    apply.ps1'in yaptıklarını geri alır.

.DESCRIPTION
    packages.ps1'deki paketleri geri açar, Google ana ekranını geri getirir, log seviyesini ve
    animasyonları varsayılana döndürür, Gerçek Kapat'ı kaldırır. -RemoveApps ile Couchy ve TV Bro da kaldırılır.
    HbbTV'yi istersen TV menüsünden kendin geri aç.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1 -TvIp 192.168.1.50
#>
param(
    [Parameter(Mandatory = $true)][string]$TvIp,
    [switch]$RemoveApps
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'packages.ps1')

$Target = "$($TvIp):5555"

Assert-Command 'adb' 'Android SDK Platform-Tools kurulu ve PATH''te olmalı.'
Connect-Tv

Write-Step 'Paketler geri açılıyor'
foreach ($pkg in $BekoPackages.Keys) {
    Write-Host "   $(Invoke-AdbShell "pm enable $pkg")"
}

Write-Step 'Ana ekran: Google'
Write-Host "   $(Invoke-AdbShell 'cmd package set-home-activity com.google.android.tvlauncher/.MainActivity')"

Write-Step 'Log seviyesi ve animasyonlar varsayılana'
Invoke-AdbShell "setprop persist.log.tag ''" | Out-Null
foreach ($key in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
    Invoke-AdbShell "settings put global $key 1.0" | Out-Null
}

Write-Step 'Gerçek Kapat kaldırılıyor'
Write-Host "   $((& adb -s $Target uninstall io.github.ifkurt.gercekkapat 2>&1 | Out-String).Trim())"
if ($RemoveApps) {
    foreach ($pkg in 'com.conreo.couchytv', 'com.phlox.tvwebbrowser') {
        Write-Host "   $pkg : $((& adb -s $Target uninstall $pkg 2>&1 | Out-String).Trim())"
    }
}
Invoke-AdbShell 'input keyevent KEYCODE_HOME' | Out-Null

Write-Step 'Notlar'
Write-Host '   - HbbTV: canlı TV açıkken MENU > Gelişmiş Seçenekler > HbbTV Ayarları.'
Write-Host '   - Gerçek Kapat''ın ADB izni TV''de kayıtlı kalır. Silmek için Geliştirici seçenekleri >'
Write-Host '     "USB hata ayıklama yetkilerini kaldır" (bilgisayarın iznini de siler).'
