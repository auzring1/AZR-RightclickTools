# Lab test checklist (M1 to M3)

Everything below needs a real lab: a ConfigMgr site, a console, a few test clients, an AD domain, and optionally an Entra ID tenant. CI cannot cover it. Tick items as you go and note the console/ConfigMgr/Windows versions. Report what failed together with the newest `azr-*.log` and `audit-*.jsonl` lines (never paste key or password values).

Use a **dedicated test collection** with two or three disposable VMs. Take snapshots before the destructive items.

## 0. Install and menu
- [ ] Clone the repo, open an elevated PowerShell, run `.\installer\Install-AZRRightClickTools.ps1`; see `Module check OK` and two `Menu XML:` lines
- [ ] `.\tools\Get-AZRConsoleNodes.ps1` lists the Device and Device Collection GUIDs from `src\Nodes.psd1`; note any difference and the placeholders it shows (`Name`, `ResourceID`, `CollectionID`, `__Server`, `__Namespace` must appear for the right nodes)
- [ ] Restart the console: **AZR Tools** appears on a device and on a collection, with the groups from the README, `&&` shown as `&`
- [ ] A device item runs (try *Ping / WinRM Test*): the launcher window does not flash errors, result window opens, **Export CSV/JSON/Copy** work, filter box filters
- [ ] `%LOCALAPPDATA%\AZR-RightClickTools\Logs` has `azr-*.log` and `audit-*.jsonl` with the run

## 1. Client actions and tools (device, then collection of 2-3)
- [ ] Each schedule action succeeds and the matching client log shows it (InventoryAgent, PolicyAgent, ScanAgent...). Confirm the schedule IDs `…0010, …0031, …0032, …0071, …0111` do what the menu says
- [ ] Collection run asks for a count confirmation, shows one result row per device, honours `MaxParallel`
- [ ] Run Client Health Check starts the *Configuration Manager Health Evaluation* task (CcmEval.log)
- [ ] View Client Cache lists the cache config and content; Set Client Cache Size changes the size (verify in Control Panel > Configuration Manager > Cache); Clear Client Cache empties it (CacheMgr.log)
- [ ] Repair Client: `SMS_Client.RepairClient` accepted (or falls back to `ccmrepair.exe`); asks for the typed device name
- [ ] Uninstall Client (on a throwaway VM): typed confirmation, `ccmsetup.exe /uninstall` runs
- [ ] Stop and Restart ConfigMgr Client Service
- [ ] `Reset-AZRExecutionHistory -ComputerName <vm> -PackageId <ID>`: backup JSON appears in the log folder, the package runs again after policy retrieval

## 2. Power and messages
- [ ] Wake-on-LAN for a powered-off VM/PC on the same subnet (needs WoL enabled and the MAC in ConfigMgr); for another subnet use `Send-AZRWakeOnLan -BroadcastAddress <subnet broadcast>`
- [ ] Restart and Shut Down: typed confirmation; the user sees the 60 s warning with the message; Cancel Pending Restart/Shutdown aborts it
- [ ] Group Policy Update; Send Message to User shows a message on a logged-on session (check `msg` is allowed and the session is reachable)
- [ ] Collection restart asks to type the device count

## 3. Collections and status
- [ ] Show Collections of Device matches the console
- [ ] Add to Collection / Remove from Collection (direct rule) on a test collection; membership changes after evaluation; user collections are refused
- [ ] Status Messages shows recent messages for the device (check `SMS_StatMsgWithInsStrings` severity mapping: Error/Warning/Informational)
- [ ] Collection Health Summary numbers match the console; Export Members to CSV opens a sane file
- [ ] Delete Device from ConfigMgr on a throwaway record: typed confirmation, record gone

## 4. System information window
- [ ] Each tab loads (Software, Services, Processes, Updates, Profiles, Sessions, LocalAdmins, Batteries, Disks, Network) and matches the machine; note the load time of *Software* on a client with many apps
- [ ] Start/Stop service, End process, Delete profile (not loaded; refused if signed in), Uninstall (MSI) each confirm and audit

## 5. Security (use test accounts and a test device; never share real keys/passwords)
- [ ] BitLocker Details shows volumes, protectors, method; TPM state is correct
- [ ] BitLocker Recovery Key from **AD** (RSAT installed, rights to read `msFVE-RecoveryInformation`): asks Yes/No then a reason, shows key ID and key in the secret window, Copy works, clipboard clears after 30 s and on close; audit shows reason and count but no key; log has no key
- [ ] Same from **Entra ID** (`Microsoft.Graph.Authentication` installed, `BitLockerKey.Read.All` + `Device.Read.All` consented): device found by display name, key shown
- [ ] LAPS Status for Windows LAPS and (if present) legacy LAPS; LAPS Password shows the password in the secret window only (also test Entra LAPS with `DeviceLocalCredential.Read.All`); Force LAPS Password Rotation changes the expiry and the client rotates at its next policy cycle
- [ ] Windows Security window tabs: Summary, Defender (a test VM with real-time protection off shows it), Exclusions, Firewall, Firewall rules, Device Guard, Boot (Secure Boot/UEFI), BitLocker
- [ ] Local Administrators on a device and on a collection; CSV export OK
- [ ] BitLocker Compliance (live) on a collection shows plausible statuses, including `Unreachable` for a powered-off VM

## 6. Foundations
- [ ] Machine policy file overrides user settings (set `RequireReasonForSecrets` false in user, true in machine; the reason prompt still appears)
- [ ] `Save-AZRCredential` + `DefaultCredentialName` makes CIM sessions use the stored credential (test against a device in another domain if available)
- [ ] `UseAdminService = true` with `AdminServiceServer` set returns collection members via the AdminService; stop the service to see the SMS Provider fallback
- [ ] Windows PowerShell 5.1 and PowerShell 7 both work for the module functions; WPF windows open from both

## Known assumptions to confirm
Node GUIDs and `ResourceID`/`CollectionID` placeholders; `SMS_Client.RepairClient` method name; client cache classes under `root\ccm\SoftMgmtAgent`; status message severity bits; Graph endpoints `informationProtection/bitlocker/recoveryKeys` and `directory/deviceLocalCredentials`; tab loaders run on the UI thread, so large tabs freeze the window until loaded.
