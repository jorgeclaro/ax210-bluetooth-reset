# ax210-bluetooth-reset

Automatically resets the Intel AX210 Bluetooth adapter on Windows after the PC resumes from sleep.

## The problem

After sleep/resume, the AX210's Bluetooth side can come back broken: paired devices don't reconnect, or the
adapter shows up as `Unknown` in Device Manager. Toggling the adapter off and on fixes it, but doing that by
hand after every resume is tedious.

## How it works

1. Windows logs System event ID **107** (Kernel-Power) when it resumes from sleep.
2. A Task Scheduler task listens for that event and runs a PowerShell script (hidden, highest privileges,
   `WakeToRun`, retries 3 times at 1-minute intervals on failure).
3. The script disables and re-enables the adapter, then re-enables any Bluetooth devices left in `Unknown` state.

## Files

| File | Purpose |
|---|---|
| `install.ps1` | Installer: finds the adapter, copies the scripts, registers the task. Self-elevates. |
| `uninstall.ps1` | Removes the task and the installed scripts. |
| `ResetAX210Bluetooth.ps1` | Simple reset: disable/enable (3 retries) + re-enable `Unknown` Bluetooth devices. |
| `ResetAX210Bluetooth_Enhanced.ps1` | Fallback chain for error `0x80041001` (see below). The task runs this one. |
| `AX210 Bluetooth Resume Reset.xml` | Task Scheduler definition used as a template by the installer. |

### Enhanced script: fallback order

Each step is followed by a check that the adapter reports `OK`; it stops at the first success.

1. **DevCon** (`C:\Windows\System32\devcon.exe`) disable/enable, if present; otherwise CIM `Disable`/`Enable`
   on the device (`Disable-PnpDevice` can fail with `0x80041001`).
2. **USB root hub reset** (disable/enable the first `ROOT_HUB` found).
3. **Restart Bluetooth services** (`BTAGService`, `bthserv`, `BluetoothUserService`).

It finishes by re-enabling any Bluetooth devices left in `Unknown` state. It must be run as Administrator.

## Install

From PowerShell in the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer:

- looks for the adapter by hardware ID (`USB\VID_8087&PID_0029*`, the AX210) among `Get-PnpDevice -Class Bluetooth`;
  if it finds none or several it lists the Bluetooth devices and asks you to pass `-InstanceId`;
- copies the two scripts to `C:\Program Files\AX210BluetoothReset` (writable by admins only, which matters because the task runs them elevated) with the adapter's instance ID filled in;
- registers the task **`AX210 Bluetooth Resume Reset`** for the current user,
  replacing an existing task of that name.

Options:

```powershell
.\install.ps1 -InstanceId 'USB\VID_8087&PID_0029\<your-instance-id>'   # skip auto-detection
.\install.ps1 -InstallDir 'D:\Tools\AX210'                                # install somewhere else
.\install.ps1 -HardwareIdPattern 'USB\VID_8087&PID_0026*'          # a different Intel adapter
```

## Generate files without installing

`-GenerateOnly` runs the same detection but only writes the filled-in files, so you can inspect them or install by
hand. It changes nothing on the system, needs no admin rights, and doesn't register the task.

```powershell
.\install.ps1 -GenerateOnly                          # writes to .\generated (git-ignored)
.\install.ps1 -GenerateOnly -OutputDir C:\Temp\ax210 # or somewhere else
```

Output: both scripts with the adapter's instance ID filled in, and the task XML with your user and SID. The XML
still points at the install folder (`-InstallDir`), so import it only after copying the scripts there:
`schtasks /create /tn "AX210 Bluetooth Resume Reset" /xml "AX210 Bluetooth Resume Reset.xml"`.

## Test

Run the task by hand, or run the script from an elevated PowerShell:

```powershell
Start-ScheduledTask -TaskName 'AX210 Bluetooth Resume Reset'
# or
powershell -ExecutionPolicy Bypass -File "C:\Program Files\AX210BluetoothReset\ResetAX210Bluetooth_Enhanced.ps1"
```

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## Notes

- Nothing machine-specific is stored in the repo. The scripts and the task XML contain placeholders
  (`__ADAPTER_INSTANCE_ID__`, `__USER_SID__`, `__USER_NAME__`, `__DATE__`) that `install.ps1` fills in from the
  machine it runs on. For that reason the scripts in the repo folder are templates: run the installed copies.
- The installer prints what it detected (computer, Windows build, user and SID, adapter name and instance ID,
  install folder) before changing anything.
- The adapter's instance ID includes a port-specific part (for example `USB\VID_8087&PID_0029\7&...&0&4`), so it
  changes if the adapter moves to a different USB port. Re-run `install.ps1` to refresh it.
