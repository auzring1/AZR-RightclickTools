# AZR-RightClickTools

Free, open-source right-click tools for the Microsoft Configuration Manager (SCCM / ConfigMgr) console, MIT licensed. Everything is plain PowerShell, so you can read, audit and extend it. It is an independent project and is not affiliated with or derived from any commercial product.

> **Status: v0.2.0.** Logic is unit-tested in CI, but the code was written without access to a Windows/ConfigMgr lab: **nothing has been run against a real site yet.** Use [docs/LAB-TESTS.md](docs/LAB-TESTS.md) to verify it step by step in a lab before using it in production.

## What you get today

Right-click a **device** or a **device collection** and use the **AZR Tools** menu. Bulk-capable items run across all collection members with throttled concurrency (default 10) after a confirmation.

| Group | Actions |
|---|---|
| Client Actions | Machine/User policy, Hardware & Software inventory, Discovery, Software Updates scan/evaluation, Application evaluation, File collection, Software metering usage, Windows Installer source list, Send unsent state messages, Baseline evaluation, Refresh update compliance |
| Client Tools | Client health check, view/clear/resize client cache, restart/stop CcmExec, repair client, uninstall client |
| Power and Messages | Wake-on-LAN (MAC from ConfigMgr), restart/shut down with 60 s warning, cancel pending shutdown, gpupdate, send message to user |
| Collections and Status | Show a device's collections, add/remove device to a collection, status messages (last 24 h), collection health summary, export members to CSV, delete device from ConfigMgr |
| Remote Tools | Ping + WinRM test, RDP, Remote PowerShell, C$, client logs, services, recent System errors, Computer Management, **System Information window** (software, services, processes, updates, profiles, sessions, local admins, disks, network, with service/process/profile/MSI-uninstall actions) |
| Security | BitLocker details, **BitLocker recovery key** (AD / Entra ID), LAPS status, **LAPS password** (Windows LAPS, legacy LAPS, Entra ID), force LAPS rotation, **Windows Security window** (Defender, exclusions, firewall, Device Guard/VBS, Secure Boot, TPM, BitLocker), local administrators report, live BitLocker compliance for a collection |
| Device Info | Logged-on user, last boot / uptime, OS, model, serial, IP/MAC, free disk, client version, pending reboot, BitLocker |

Every result window can be filtered and exported (CSV, JSON, clipboard). Secrets (recovery keys, LAPS passwords) are shown only in a dedicated window, are never logged or exported, and every reveal asks for a reason and is written to the audit log. The roadmap for what comes next is in [docs/ROADMAP-FULL.md](docs/ROADMAP-FULL.md); what is verified versus lab-only is in [docs/LAB-TESTS.md](docs/LAB-TESTS.md).

**Out of scope by design:** no agent, no management server, no role enforcement (anyone who can run the tool can do what their own Windows/ConfigMgr rights allow), no commercial support.

## Architecture

```
ConfigMgr console right-click
  -> XmlStorage\Extensions\Actions\<node GUID>\AZR-RightClickTools.xml   (generated)
  -> powershell.exe Launcher\Invoke-AZRLauncher.ps1 -Action X -ComputerName ##SUB:Name## ...
  -> Module AZR.RightClickTools :: Invoke-AZRAction (validate -> dispatch -> log)
  -> CIM/WMI (WSMan, DCOM fallback), WinRM, SMS Provider, mstsc/explorer
```

* `src/Actions.psd1` is the single manifest of menu items; `tools/Build-ConsoleExtension.ps1` turns it into console XML, so adding an action means one manifest entry plus one function.
* `src/AZR.RightClickTools` is the module (`Public/` = tools, `Private/` = CIM sessions, input validation, logging, UI helpers). Everything also works from a normal PowerShell prompt, e.g. `Invoke-AZRClientAction -ComputerName PC01 -Action HardwareInventory`.
* No agent, server component, database or extra service. Operations run as the console user, so ConfigMgr RBAC and Windows permissions on the target still apply.
* Each action has a **Risk** class in the manifest (`Read`, `Change`, `Destructive`, `Secret`) that drives confirmation: nothing for single-device reads, Yes/No for changes and any bulk run, a typed device name (or device count) for destructive actions, and Yes/No plus a reason for secrets.
* Security: every value coming from the console is validated against strict allow-lists (host names, collection IDs, site codes, MACs, product codes, message text) before use. Remote commands are built only from fixed templates plus validated parameters. Actions are logged to `%LOCALAPPDATA%\AZR-RightClickTools\Logs` (diagnostic log plus a JSON-lines audit file `audit-YYYYMM.jsonl`).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details and known assumptions.

## Install

On a workstation with the ConfigMgr console:

1. Clone the repository (`git clone https://github.com/auzring1/AZR-RightclickTools`) or download and extract the ZIP.
2. Open an **elevated** PowerShell (Run as administrator).
3. `cd` into the repository folder.
4. Run the installer **as a file**. Do not paste its contents into the console; it needs to know where the repo is and will refuse to run otherwise.

```powershell
cd C:\path\to\AZR-RightclickTools
.\installer\Install-AZRRightClickTools.ps1          # add -WhatIf to preview
```

If script execution is blocked, bypass the policy for that one process only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\Install-AZRRightClickTools.ps1
```

If you downloaded a ZIP, run `Get-ChildItem -Recurse | Unblock-File` in the extracted folder first.

The installer ends with a self-check (it loads the installed module and lists the menu XML files it wrote). A healthy run prints `Module check OK` and two `Menu XML:` lines. **Close and reopen the ConfigMgr console**, then right-click a device.

Use `-ConsoleDir` if the console is not auto-detected. Remove with `.\installer\Uninstall-AZRRightClickTools.ps1`.

Requirements: Windows PowerShell 5.1+, ConfigMgr console, and on targets: WinRM or DCOM/RPC reachable plus admin rights, as for any remote WMI tooling. Optional: RSAT *ActiveDirectory* module (AD key/LAPS lookups), the Windows LAPS module (Windows LAPS), `Microsoft.Graph.Authentication` (Entra ID keys/LAPS; `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`).

### Troubleshooting

| Symptom | Fix |
|---|---|
| `must be run as a file` | You pasted the script into a console. Run it from the cloned folder, as above. |
| `running scripts is disabled` | Use the `-ExecutionPolicy Bypass -File` form shown above, and `Unblock-File` for a ZIP download. |
| `ConfigMgr console not found` | Install the console first or pass `-ConsoleDir 'C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole'` (the folder that contains `XmlStorage`). |
| Installed, but no **AZR Tools** menu | Fully close the console and reopen it. If still missing, the node GUIDs differ on your console version: run `.\tools\Get-AZRConsoleNodes.ps1`, compare with `src\Nodes.psd1`, fix the GUID, run the installer again. Generated XML is in `<Console>\XmlStorage\Extensions\Actions\<GUID>\AZR-RightClickTools.xml`. |
| Menu is there but an item does nothing | Open `%LOCALAPPDATA%\AZR-RightClickTools\Logs\azr-<date>.log` (diagnostics) and `audit-<month>.jsonl` (what was run, by whom, outcome). |
| `Module check FAILED` | Read the warning text; usually a blocked file (`Get-ChildItem -Recurse | Unblock-File`) or PowerShell older than 5.1. |

## Settings

Optional JSON file per user (`%APPDATA%\AZR-RightClickTools\settings.json`) and an optional machine policy file (`%ProgramData%\AZR-RightClickTools\settings.json`, or a UNC path in the `AZR_SETTINGS_MACHINE` environment variable) that overrides the user file. Invalid values are ignored and logged. Keys: `MaxParallel` (1-64, default 10), `BulkConfirmThreshold`, `UseWpfResults`, `ExportDirectory`, `AuditToFile`, `AuditPath`, `AuditToEventLog`, `RequireReasonForSecrets` (default true), `SecretClipboardClearSeconds` (default 30), `DefaultCredentialName`, `UseAdminService`, `AdminServiceServer`, `AdServer`. Alternate credentials: `Save-AZRCredential -Name Corp -Credential (Get-Credential)` (stored DPAPI-encrypted for your user on your machine only), then set `DefaultCredentialName` to `Corp`.

## Testing

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester -Path tests -Output Detailed
```

The Pester suite covers validation, manifest and generated XML, settings, credentials, audit redaction, the parallel runner, exports, the AdminService and Graph clients (mocked), command templates, the confirmation policy, the dispatcher, and every feature's logic with mocked CIM/AD/Graph calls, including checks that secrets never reach logs, audit entries or exports. CI (`.github/workflows/test.yml`) runs it on Windows with PSScriptAnalyzer. **Calls against real ConfigMgr, clients, AD and Entra ID are lab-only**; the checklist is [docs/LAB-TESTS.md](docs/LAB-TESTS.md).

## Contributing

Issues and PRs welcome. Please write original code and keep new actions behind the manifest and validation helpers.
