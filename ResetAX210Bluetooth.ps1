$bt = "__ADAPTER_INSTANCE_ID__"   # filled in by install.ps1

# Reset AX210 hardware
for ($i=0; $i -lt 3; $i++) {
    try {
        Disable-PnpDevice -InstanceId $bt -Confirm:$false
        Start-Sleep 2
        Enable-PnpDevice -InstanceId $bt -Confirm:$false
        break
    } catch {
        Start-Sleep 1
    }
}

# Force Windows to refresh the stack
Get-PnpDevice -Class Bluetooth | Where-Object { $_.Status -eq "Unknown" } | ForEach-Object {
    Enable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false
}