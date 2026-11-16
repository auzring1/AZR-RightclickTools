# Architecture notes

## Console extension mechanism
The ConfigMgr console loads XML from `<AdminConsole>\XmlStorage\Extensions\Actions\<node GUID>\*.xml`. Each file describes `ActionDescription` entries; `Class="Executable"` entries launch a program, and `Class="Group"` creates a submenu. Placeholders such as `##SUB:Name##`, `##SUB:CollectionID##`, `##SUB:__Server##` and `##SUB:__Namespace##` are replaced by the console from the selected object. See Microsoft's [console extension docs](https://learn.microsoft.com/mem/configmgr/develop/core/servers/console/console-extension-deployment).

## Manifest v2 and nodes
* `src/Actions.psd1` (schema version 2) lists every menu item: `Id`, `Name`, `Targets`, `Description`, `Risk` (`Read`/`Change`/`Destructive`/`Secret`), optional `Confirm` (`Auto`/`None`), `Requires` (`AD`, `Graph`, `AdminSvc`, `ConfigMgrModule`, `SmsProvider`) and `Ui` (`None`/`Grid`/`Window:<name>`).
* `src/Nodes.psd1` lists the console nodes: GUID, the launcher arguments that pass the selected object, and the placeholders that node supports. Only `Device` and `Collection` have GUIDs today; the other planned nodes (`User`, `UserCollection`, `Application`, `SoftwareUpdate`, `DistributionPoint`, `DPGroup`) are listed with no GUID and are skipped until discovered.
* `tools/Build-ConsoleExtension.ps1` validates the manifest against the nodes (unknown targets, missing GUID, bad risk, `Confirm=None` on destructive/secret actions, placeholders a node does not support, secret actions on collections) and writes one XML file per node that has a GUID and actions. A bad manifest stops the build with every problem listed.
* Adding an action = one manifest entry + one handler in `Private/ActionRegistry.ps1` (+ the function it calls). A CI test fails if a manifest id has no handler or a declared target has no handler scope.

### Node GUIDs and placeholders (assumption to verify in a lab)
The Device and Device Collection GUIDs (`ed9dee86-eadd-4ac8-82a1-7234a4646e62`, `3fd01cd1-9e01-461e-92cd-94866b8d1f39`) come from published community examples. Run `tools\Get-AZRConsoleNodes.ps1` on a machine with the console: it lists every node GUID folder, the placeholders used by the XML shipped there, and sample menu names so you can recognise the node. Update `src/Nodes.psd1` and set `Verified = $true` once confirmed.

## Dispatch, confirmation and audit
`Invoke-AZRAction` is the single entry point used by the generated menu:

1. Look up the handler in `Get-AZRActionTable` (unknown id = error) and the manifest definition (risk, confirm).
2. Validate the target (`Assert-AZRComputerName`, collection id, site code). For a collection, resolve members through the SMS Provider (or AdminService when `UseAdminService` is on).
3. Confirmation by risk (`Get-AZRConfirmationPlan`, pure and unit-tested): `Read` none (bulk: count prompt), `Change` Yes/No (`Confirm = None` skips it for a single device), `Destructive` typed device name or typed device count, `Secret` Yes/No plus reason.
4. Run the handler. Bulk work goes through `Invoke-AZRBulk` / `Invoke-AZRParallel` (runspace pool, `MaxParallel` default 10, per-device result rows, Ctrl+C/window close stops outstanding work).
5. Write an audit entry (`audit-YYYYMM.jsonl`: time, user, machine, action, risk, outcome, targets, reason). Secret handlers audit themselves with counts and reason only.

## Transport
* Client actions: `Invoke-CimMethod root\ccm:SMS_Client.TriggerSchedule`.
* Client tools: `root\ccm\SoftMgmtAgent` (`CacheConfig`, `CacheInfoEx`), `SMS_Client.RepairClient`, and fixed command templates run through `Win32_Process.Create` (`ccmsetup /uninstall`, health-evaluation scheduled task, `gpupdate`, `msg`, `shutdown`, `msiexec /x`, a fixed cache-clear script). `Private/Process.ps1` is the only place commands are assembled; free text only enters through validated parameters (`Assert-AZRMessageText` allows letters, digits, spaces and `. , : ; ! ? ( ) - _ ' /`).
* Registry reads/deletes use `StdRegProv` over CIM (no Remote Registry service needed).
* System info: `Win32_*` classes; software list from the Uninstall registry keys (not `Win32_Product`, which triggers MSI repairs).
* Device info / BitLocker / TPM: `root\cimv2\Security\MicrosoftVolumeEncryption`, `Win32_Tpm`. Windows Security: `root\Microsoft\Windows\Defender`, `root\StandardCimv2`, `root\Microsoft\Windows\DeviceGuard`, registry for Secure Boot/firmware type.
* Collection membership, status messages and quick queries: SMS Provider classes (`SMS_FullCollectionMembership`, `SMS_StatMsgWithInsStrings`, `SMS_R_System`, `SMS_Collection`). WQL is built only by `New-AZRWql` from allow-listed class/property names and validated values.
* `Invoke-AZRAdminService`: REST client with paging, same-host paging check and path validation. Used for collection members when `UseAdminService` is on, with SMS Provider fallback.
* `Connect-AZRGraph` / `Invoke-AZRGraph`: wrappers over `Microsoft.Graph.Authentication`; delegated interactive sign-in, least-privilege scopes per feature (`Get-AZRGraphScope`): BitLocker keys `BitLockerKey.Read.All` + `Device.Read.All`, LAPS `DeviceLocalCredential.Read.All` + `Device.Read.All`.
* Sessions try WSMan first, then DCOM, and use the credential named by `DefaultCredentialName` when set.

## Secrets
Recovery keys and LAPS passwords travel as `SecureString`, are shown only by `Show-AZRSecretWindow` (read-only text boxes, Copy button, clipboard cleared after `SecretClipboardClearSeconds` and on close if it still holds the value), are redacted by `Write-AZRAudit` by name, are replaced with `[hidden]` in every grid and export, and are never put on a command line. A static Pester test fails if a secret-looking variable is passed to `Write-AZRLog` or `Write-AZRAudit`. Not implemented: ConfigMgr BitLocker-management and MBAM key sources (the API shapes were not verified); AD and Entra ID are.

There is no role enforcement. Anyone who can launch the tool can do what their own AD/ConfigMgr/Windows rights allow, which is also what protects the secrets (AD ACLs on recovery information and LAPS attributes, Graph consent).

## WPF host
`New-AZRWindowObject` (XAML in `Private/Window.ps1`, no third-party UI) provides tabs of data grids with filter box, CSV/JSON/clipboard export, lazy tab loaders and optional action buttons (per tab). Button clicks go through `Confirm-AZRRisk` and write audit entries. WPF needs an STA thread: the generated menu launches `powershell.exe -STA`, and `Invoke-AZRSta` re-hosts the call on an STA runspace when started from PowerShell 7. Tab loaders run on the UI thread in this version, so a slow target blocks the window until the tab finishes loading.

## Planned (see FEATURES.md and ROADMAP-FULL.md)
Remote GUI tools (file explorer, registry, event viewer), content/application/user nodes, Intune/Entra/Autopilot actions, dashboards, workflows.
