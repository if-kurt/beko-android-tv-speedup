<#
.SYNOPSIS
    Undoes what apply.ps1 did.

.DESCRIPTION
    Enables the packages in packages.ps1 again, brings back the Google home screen, resets the log level and
    animation scales, and uninstalls Gerçek Kapat. With -RemoveApps it also uninstalls Couchy and TV Bro.
    Turn HbbTV back on from the TV menu yourself if you want it.

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

Assert-Command 'adb' 'Android SDK Platform-Tools must be installed and on PATH.'
Connect-Tv

Write-Step 'Enabling packages again'
foreach ($pkg in $BekoPackages.Keys) {
    Write-Host "   $(Invoke-AdbShell "pm enable $pkg")"
}

Write-Step 'Home screen: Google'
Write-Host "   $(Invoke-AdbShell 'cmd package set-home-activity com.google.android.tvlauncher/.MainActivity')"

Write-Step 'Log level and animations back to defaults'
Invoke-AdbShell "setprop persist.log.tag ''" | Out-Null
foreach ($key in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
    Invoke-AdbShell "settings put global $key 1.0" | Out-Null
}

Write-Step 'Uninstalling Gerçek Kapat'
Write-Host "   $((& adb -s $Target uninstall io.github.ifkurt.gercekkapat 2>&1 | Out-String).Trim())"
if ($RemoveApps) {
    foreach ($pkg in 'com.conreo.couchytv', 'com.phlox.tvwebbrowser') {
        Write-Host "   $pkg : $((& adb -s $Target uninstall $pkg 2>&1 | Out-String).Trim())"
    }
}
Invoke-AdbShell 'input keyevent KEYCODE_HOME' | Out-Null

Write-Step 'Notes'
Write-Host '   - HbbTV: with live TV on, MENU > Advanced Options > HbbTV Settings.'
Write-Host '   - Gerçek Kapat''s ADB key stays approved on the TV. To remove it: Developer options >'
Write-Host '     "Revoke USB debugging authorizations" (this also removes your computer''s permission).'
