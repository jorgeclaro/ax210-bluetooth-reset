<#
.SYNOPSIS
    Installs the AX210 Bluetooth resume-reset task.
.DESCRIPTION
    - Finds the Bluetooth adapter's instance ID (or uses -InstanceId)
    - Copies the scripts to -InstallDir with that ID filled in
    - Registers the Task Scheduler task for the current user, run on resume
    Self-elevates if not running as Administrator.

    With -GenerateOnly it only writes the filled-in scripts and task XML to -OutputDir
    (default: .\generated) and changes nothing on the system. No admin rights needed.
.EXAMPLE
    .\install.ps1
    .\install.ps1 -InstanceId 'USB\VID_8087&PID_0029\<your-instance-id>' -InstallDir 'D:\Tools\AX210'
    .\install.ps1 -GenerateOnly
    .\install.ps1 -GenerateOnly -OutputDir C:\Temp\ax210
#>
param(
    [string]$InstanceId,
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'AX210BluetoothReset'),
    [string]$HardwareIdPattern = 'USB\VID_8087&PID_0029*',   # Intel AX210 Bluetooth
    [switch]$GenerateOnly,
    [string]$OutputDir = (Join-Path $PSScriptRoot 'generated')
)

$ErrorActionPreference = 'Stop'
$TaskName = 'AX210 Bluetooth Resume Reset'

# --- self-elevate (not needed for -GenerateOnly) ---
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $GenerateOnly) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-InstallDir', "`"$InstallDir`"", '-HardwareIdPattern', "`"$HardwareIdPattern`"")
    if ($InstanceId) { $argList += @('-InstanceId', "`"$InstanceId`"") }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait
    return
}

try {
    # --- detect this machine ---
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $os = Get-CimInstance Win32_OperatingSystem

    $adapter = $null
    if ($InstanceId) {
        $adapter = Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
    } else {
        $found = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like $HardwareIdPattern })
        if ($found.Count -ne 1) {
            Write-Host "Expected exactly one device matching $HardwareIdPattern, found $($found.Count)." -ForegroundColor Red
            Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Format-Table Status, FriendlyName, InstanceId -AutoSize
            Write-Host "Re-run with -InstanceId '<id from the list above>'." -ForegroundColor Yellow
            return
        }
        $adapter = $found[0]
        $InstanceId = $adapter.InstanceId
    }

    Write-Host 'Detected:'
    Write-Host "  Computer : $env:COMPUTERNAME ($($os.Caption), build $($os.BuildNumber))"
    Write-Host "  User     : $($user.Name)  ($($user.User.Value))"
    Write-Host "  Adapter  : $(if ($adapter) { $adapter.FriendlyName } else { '(not currently present)' })"
    Write-Host "  Instance : $InstanceId"
    Write-Host "  Install  : $InstallDir"

    # Where the filled-in files go: the install folder, or -OutputDir with -GenerateOnly.
    $targetDir = if ($GenerateOnly) { $OutputDir } else { $InstallDir }

    # --- write scripts, filling in the instance ID ---
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    foreach ($name in 'ResetAX210Bluetooth.ps1', 'ResetAX210Bluetooth_Enhanced.ps1') {
        $text = Get-Content (Join-Path $PSScriptRoot $name) -Raw
        if (-not $text.Contains('__ADAPTER_INSTANCE_ID__')) { throw "Placeholder __ADAPTER_INSTANCE_ID__ not found in $name" }
        Set-Content -Path (Join-Path $targetDir $name) -Value $text.Replace('__ADAPTER_INSTANCE_ID__', $InstanceId) -Encoding UTF8
        Write-Host "Wrote $targetDir\$name"
    }

    # --- fill in the task XML (it points at the scripts in $InstallDir) ---
    $xml = Get-Content (Join-Path $PSScriptRoot 'AX210 Bluetooth Resume Reset.xml') -Raw
    $xml = $xml.Replace('__USER_SID__', $user.User.Value).
                Replace('__USER_NAME__', $user.Name).
                Replace('__DATE__', (Get-Date).ToString('s'))
    $xml = [regex]::Replace($xml, '(?<=-File ")[^"]*(?=")', { Join-Path $InstallDir 'ResetAX210Bluetooth_Enhanced.ps1' })

    if ($GenerateOnly) {
        $xmlPath = Join-Path $targetDir 'AX210 Bluetooth Resume Reset.xml'
        Set-Content -Path $xmlPath -Value $xml -Encoding Unicode   # Task Scheduler XML is UTF-16
        Write-Host "Wrote $xmlPath"
        Write-Host 'Generate only: nothing was installed or registered.' -ForegroundColor Green
    } else {
        Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
        Write-Host "Registered task '$TaskName' (runs on resume, event ID 107)." -ForegroundColor Green
    }
}
catch {
    Write-Host "Install failed: $_" -ForegroundColor Red
}
finally {
    if (-not $GenerateOnly) { Read-Host 'Press Enter to close' }
}
