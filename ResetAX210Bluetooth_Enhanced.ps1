# ResetAX210Bluetooth_Enhanced.ps1 - Fixed version for 0x80041001 error
# Run as ADMINISTRATOR

$bt = "__ADAPTER_INSTANCE_ID__"   # filled in by install.ps1

# Function to safely disable/enable using multiple methods
function Reset-DeviceHard {
    param([string]$InstanceId)
    
    Write-Host "Attempting to reset device: $InstanceId"
    
    # Method 1: Try DevCon if available (most reliable)
    $devConPath = "C:\Windows\System32\devcon.exe"
    if (Test-Path $devConPath) {
        Write-Host "Using DevCon method..."
        & $devConPath disable $InstanceId
        Start-Sleep 2
        & $devConPath enable $InstanceId
        return
    }
    
    # Method 2: WMI/CIM with different approach
    Write-Host "Using WMI method..."
    
    # Disable
    $device = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPDeviceID -eq $InstanceId }
    if ($device) {
        # Try CIM method instead of PnpDevice
        $result = Invoke-CimMethod -InputObject $device -MethodName Disable
        if ($result.ReturnValue -ne 0) {
            Write-Host "Disable returned: $($result.ReturnValue)"
        }
        Start-Sleep 2
        
        # Enable
        $result = Invoke-CimMethod -InputObject $device -MethodName Enable
        if ($result.ReturnValue -ne 0) {
            Write-Host "Enable returned: $($result.ReturnValue)"
        }
    }
}

# Method 3: Last resort - restart Bluetooth services
function Restart-BluetoothServices {
    Write-Host "Restarting Bluetooth services..."
    
    $services = @(
        "BTAGService",  # Bluetooth Audio Gateway
        "bthserv",      # Bluetooth Support Service
        "BluetoothUserService"  # Bluetooth User Support
    )
    
    foreach ($service in $services) {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Host "Restarting $service..."
            Stop-Service $service -Force -ErrorAction SilentlyContinue
            Start-Sleep 1
            Start-Service $service -ErrorAction SilentlyContinue
        }
    }
}

# Method 4: USB hub reset (alternative approach)
function Reset-USBHub {
    Write-Host "Resetting USB hub..."
    
    # Find the USB hub that contains our device
    $hub = Get-CimInstance -ClassName Win32_USBHub | Where-Object { 
        $_.PNPDeviceID -like "*ROOT_HUB*" 
    } | Select-Object -First 1
    
    if ($hub) {
        $hubDevice = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { 
            $_.PNPDeviceID -eq $hub.PNPDeviceID 
        }
        if ($hubDevice) {
            Invoke-CimMethod -InputObject $hubDevice -MethodName Disable
            Start-Sleep 3
            Invoke-CimMethod -InputObject $hubDevice -MethodName Enable
        }
    }
}

# Main execution with elevated privileges check
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "=== AX210 Bluetooth Reset ===" -ForegroundColor Cyan

# Try different methods in sequence
$methods = @(
    { Reset-DeviceHard -InstanceId $bt },
    { Reset-USBHub },
    { Restart-BluetoothServices }
)

foreach ($method in $methods) {
    Write-Host "`nTrying next method..." -ForegroundColor Yellow
    & $method
    Start-Sleep 3
    
    # Check if device is working
    $status = Get-PnpDevice -InstanceId $bt -ErrorAction SilentlyContinue
    if ($status.Status -eq "OK") {
        Write-Host "`nSUCCESS: Device is now working!" -ForegroundColor Green
        break
    }
}

# Final cleanup - re-enable any unknown devices
Write-Host "`nCleaning up unknown devices..." -ForegroundColor Yellow
Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | 
    Where-Object { $_.Status -eq "Unknown" } | 
    ForEach-Object {
        $unknownId = $_.InstanceId
        Write-Host "Found unknown: $($_.FriendlyName)"
        try {
            Enable-PnpDevice -InstanceId $unknownId -Confirm:$false -ErrorAction Stop
        } catch {
            # Try CIM method as fallback
            $dev = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPDeviceID -eq $unknownId }
            if ($dev) {
                Invoke-CimMethod -InputObject $dev -MethodName Enable
            }
        }
    }

Write-Host "`nProcess complete. Check Bluetooth functionality." -ForegroundColor Cyan