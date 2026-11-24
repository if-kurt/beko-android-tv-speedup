# apply.ps1 ve restore.ps1'in ortak yardımcıları. $Target ("ip:5555") çağıran betikte tanımlı olmalı.

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Invoke-AdbShell([string]$Command) {
    return (& adb -s $Target shell $Command 2>&1 | Out-String).Trim()
}

function Assert-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name bulunamadı. $Hint"
    }
}

function Connect-Tv {
    Write-Step "TV'ye bağlanılıyor: $Target"
    $deadline = (Get-Date).AddSeconds(120)
    $hinted = $false
    while ($true) {
        & adb connect $Target 2>&1 | Out-Null
        $state = (& adb -s $Target get-state 2>&1 | Out-String).Trim()
        if ($state -eq 'device') {
            Write-Host '   bağlandı'
            return
        }
        if ((Get-Date) -gt $deadline) {
            throw "TV'ye bağlanılamadı ($state). TV açık mı, Geliştirici seçenekleri'nde USB hata ayıklama açık mı, IP doğru mu?"
        }
        if (-not $hinted) {
            Write-Host "   TV'de 'USB hata ayıklamaya izin verilsin mi?' penceresi çıkarsa 'Her zaman izin ver' ile onayla."
            $hinted = $true
        }
        Start-Sleep -Seconds 5
    }
}
