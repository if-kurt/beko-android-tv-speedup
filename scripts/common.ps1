# Helpers shared by apply.ps1 and restore.ps1. The calling script must define $Target ("ip:5555").

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Invoke-AdbShell([string]$Command) {
    return (& adb -s $Target shell $Command 2>&1 | Out-String).Trim()
}

function Assert-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name not found. $Hint"
    }
}

function Connect-Tv {
    Write-Step "Connecting to the TV: $Target"
    $deadline = (Get-Date).AddSeconds(120)
    $hinted = $false
    while ($true) {
        & adb connect $Target 2>&1 | Out-Null
        $state = (& adb -s $Target get-state 2>&1 | Out-String).Trim()
        if ($state -eq 'device') {
            Write-Host '   connected'
            return
        }
        if ((Get-Date) -gt $deadline) {
            throw "Could not connect to the TV ($state). Is the TV on, is USB debugging on in Developer options, is the IP right?"
        }
        if (-not $hinted) {
            Write-Host "   If the TV asks 'Allow USB debugging?', tick 'Always allow' and confirm."
            $hinted = $true
        }
        Start-Sleep -Seconds 5
    }
}
