# AZR-RightClickTools

Free, open-source right-click tools for the Microsoft Configuration Manager (SCCM / ConfigMgr) console, MIT licensed. Everything is plain PowerShell, so you can read, audit and extend it. It is an independent project and is not affiliated with or derived from any commercial product.

> **Status: MVP (v0.1.0).** The code was written and reviewed without access to a Windows/ConfigMgr lab, so treat it as untested against a live site until you have tried it in a lab. See [Testing](#testing).

## What you get today

Right-click a **device** (or a **device collection** for the bulk-capable ones) and use the **AZR Tools** menu:

| Group | Actions |
|---|---|
| Client Actions | Machine/User policy, Hardware & Software inventory, Discovery, Software Updates scan/evaluation, Application evaluation, restart CcmExec |
| Remote Tools | Ping + WinRM test, RDP (normal/admin), Remote PowerShell, Browse C$, open client logs, services grid, recent System errors, Computer Management |
| Device Info | Logged-on user, last boot / uptime, OS, model, serial, IP/MAC, free disk, client version, pending reboot, BitLocker status |

Collection targets run client actions and Ping across all members, after a confirmation prompt, and show a result grid. The full roadmap is in [docs/FEATURES.md](docs/FEATURES.md).

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
* Security: every value coming from the console is validated against strict allow-lists (host names, collection IDs, site codes) before use, nothing is built with string concatenation into commands except those validated values, and actions are logged to `%LOCALAPPDATA%\AZR-RightClickTools\Logs`.

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

Restart the console. Use `-ConsoleDir` if the console is not auto-detected. Remove with `.\installer\Uninstall-AZRRightClickTools.ps1`.

Requirements: Windows PowerShell 5.1+, ConfigMgr console, and on targets: WinRM or DCOM/RPC reachable plus admin rights, as for any remote WMI tooling.

## Testing

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester -Path tests -Output Detailed
```

The Pester suite covers input validation, the action manifest, and generated XML. CI (`.github/workflows/test.yml`) runs it on Windows. Remote operations need a lab to verify.

## Contributing

Issues and PRs welcome. Please write original code and keep new actions behind the manifest and validation helpers.
