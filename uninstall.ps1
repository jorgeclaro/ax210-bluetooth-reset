<#
.SYNOPSIS
    Removes the AX210 Bluetooth resume-reset task and the installed scripts.
.EXAMPLE
    .\uninstall.ps1
    .\uninstall.ps1 -InstallDir 'D:\Tools\AX210'
#>
param([string]$InstallDir = (Join-Path $env:ProgramFiles 'AX210BluetoothReset'))

$TaskName = 'AX210 Bluetooth Resume Reset'
$ScriptNames = 'ResetAX210Bluetooth.ps1', 'ResetAX210Bluetooth_Enhanced.ps1'

# --- self-elevate ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-InstallDir', "`"$InstallDir`""
    return
}

try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed task '$TaskName'."
    } else {
        Write-Host "Task '$TaskName' not found."
    }

    # Remove only our own files, then the folder if it ended up empty.
    foreach ($name in $ScriptNames) {
        $p = Join-Path $InstallDir $name
        if (Test-Path $p) { Remove-Item $p; Write-Host "Removed $p" }
    }
    if ((Test-Path $InstallDir) -and -not (Get-ChildItem $InstallDir -Force)) {
        Remove-Item $InstallDir
        Write-Host "Removed empty folder $InstallDir"
    }
}
catch {
    Write-Host "Uninstall failed: $_" -ForegroundColor Red
}
finally {
    Read-Host 'Press Enter to close'
}
