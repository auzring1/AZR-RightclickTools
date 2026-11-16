# AZR-RightClickTools: full feature plan

Status: planning document, no feature code in this change. Everything below is our own design in our own wording; no vendor code, binaries, icons or text are reused, and public vendor documentation was used only to learn *which capabilities exist* (see [Sources](#sources)). Menu names, helper names and workflow formats are ours (`AZR` prefix).

## 1. Scope and ground rules

Goal: cover the capability areas of a commercial "enterprise right-click toolkit" for ConfigMgr and Intune with free, MIT-licensed PowerShell, as far as that is technically and legally possible.

Principles that drive every design choice:

1. **Agentless, serverless.** The MVP has no agent or server and runs as the console user, so ConfigMgr RBAC and Windows ACLs still apply. That is a hard scope decision, not a default: this project will not add its own agent, management server, role-enforcement layer or commercial support. Where a commercial product relies on those, we use an existing channel (ConfigMgr Run Scripts / client notification, WinRM, Graph) or mark the feature out of scope.
2. **One manifest, one function.** New menu items go in `src/Actions.psd1` and a function under `Public/`. The manifest schema is extended (M1) rather than bypassed.
3. **Validate everything from the console.** Reuse `Assert-AZR*`; add validators for new placeholders (UserName, PackageID, DP name, ApplicationName, UPN).
4. **Destructive actions confirm and log.** Anything that deletes, wipes, uninstalls, reboots or reveals a secret shows a confirmation naming the target(s) and count, and writes an audit entry.
5. **No secrets in logs or XML.** Recovery keys and passwords are shown only in a UI window, never written to the log, and never passed on a command line.

## 2. Legend

- **Node**: where the item appears. Existing console extension XML can add items to the context menu and ribbon of *existing* nodes only. It cannot add new nodes or embedded panes (that needs a compiled console snap-in, which we avoid). Dashboards are therefore a **GUI helper**: a WPF window launched from a menu item (see §3.3).
- **Mechanism**: CIM = CIM/WMI over WSMan or DCOM; SMSP = SMS Provider WMI (`root\sms\site_XXX`); AdminSvc = ConfigMgr AdminService REST; CMcmd = ConfigMgr PowerShell module; Graph = Microsoft Graph; ADWS = Active Directory Web Services via RSAT `ActiveDirectory` module.
- **Test**: **CI** = Pester with mocks on `windows-latest` (no real targets); **Lab** = needs a ConfigMgr site, AD, a target client or an Entra/Intune tenant; **Both** = logic unit-tested in CI, behaviour confirmed in lab.
- **Flags**: 🖥 needs GUI helper, ⚠ risk to review, 🚫 cannot be done free / legally / without out-of-scope components, ◐ partial parity.

Common ports (target side): WinRM 5985/5986 (HTTP/HTTPS), RPC 135 + dynamic 49152–65535 (DCOM/RPC), SMB 445 (C$, remote registry via SMB not needed), RDP 3389, ConfigMgr client notification 10123 (fast channel), SMS Provider via RPC/DCOM or HTTPS 443 for AdminService, LDAP 389/636 + ADWS 9389, Graph 443 to `graph.microsoft.com` and `login.microsoftonline.com`.

## 3. Foundations the rest depends on (Milestone 1)

### 3.1 Manifest v2 and multi-node extension generation
Extend `Actions.psd1` and `tools/Build-ConsoleExtension.ps1`:

- `Targets` gains `Device`, `Collection` (existing) plus `User`, `UserCollection`, `Application`, `SoftwareUpdate`, `DistributionPoint`, `DPGroup`, `Monitoring` (launcher-only).
- Per node, record the GUID, and the placeholder set (`##SUB:Name##`, `CollectionID`, `PackageID`, `CI_ID`, `SMSID`, `UniqueUserName`…). The set differs per node and must be checked per console version.
- New field `Requires` (e.g. `Graph`, `AD`, `AdminSvc`, `ConfigMgrModule`) so the launcher can pre-check and give a useful error, and `Risk` (`Read`, `Change`, `Destructive`, `Secret`) which drives confirmation and audit behaviour.
- New field `Ui` (`None`, `Grid`, `Window:<name>`) for GUI helpers.
- Tooling: `tools/Get-AZRConsoleNodes.ps1`, a lab helper that enumerates node GUIDs and available placeholders from the installed console, so we stop relying on assumed GUIDs (the existing ARCHITECTURE.md already flags this).
- Test: **CI** (generated XML schema/escaping, every action maps to a function, every placeholder valid per node). Real menu rendering is **Lab**.

### 3.2 Shared plumbing

| Helper | Purpose | Notes |
|---|---|---|
| `Get-AZRSettings` | JSON settings file (per-user + optional machine/AD-share policy file) | Machine policy overrides user; schema-validated |
| Alternate credentials | `-Credential` through every session helper, stored via DPAPI `Export-Clixml` or Windows Credential Manager, never plain text | Needed for untrusted domains (M8) |
| Parallel bulk runner | Throttled fan-out for collections, per-device result objects, progress, cancel | PS 5.1: runspace pool (no `-Parallel`); keep MVP serial runner as fallback |
| Result export | CSV/JSON/clipboard from any grid | Extend `Show-AZRResult` |
| Structured audit log | JSON lines: time, user, action, target(s), outcome, risk class, never secrets | Windows Event Log source option, file fallback |
| `Invoke-AZRAdminService` | REST client for AdminSvc (Kerberos/NTLM or token), used where SMSP/DCOM is undesirable | Falls back to SMSP |
| `Connect-AZRGraph` | Wrapper over the MIT-licensed `Microsoft.Graph.Authentication` module, delegated interactive auth, least-privilege scope sets per feature | Tenant/app registration documented in `docs/` |
| `New-AZRWindow` | WPF host (XAML in repo, own styling): tabs, filter box, export, action buttons | Powers every 🖥 item; PS 5.1 + .NET Framework WPF, no third-party UI libs |

Risks: DCOM fallback requires wide RPC ranges (document it); Graph delegated scopes can be powerful (document the exact scopes per action); parallel runner must cap concurrency (default 10) to avoid hammering DPs/the site server.

### 3.3 How "dashboards" are done
A dashboard is a WPF window (`New-AZRWindow`) launched from a menu item on the Devices/Device Collections or Monitoring nodes (and optionally a stand-alone `Start-AZRDashboard` shortcut). Data comes from SMSP/AdminSvc SQL-backed views and Graph, cached for a configurable time, exportable to CSV. No new console node is created. Marked 🖥 throughout.

## 4. Feature map

Nodes: **Dev** = Devices, **DevColl** = Device Collections, **User/UserColl**, **App** = Applications, **SU** = Software Updates, **DP** = Distribution Points, **Mon** = Monitoring/launcher.

### 4.1 Device management

| # | Feature | Node | Mechanism | Permissions / ports | Depends on | Risk / notes | Test |
|---|---|---|---|---|---|---|---|
| D1 | Remaining client actions: file collection, send state messages, software metering usage, state-message cache cleanup, Windows Installer source update, deployment re-evaluation | Dev, DevColl | CIM `SMS_Client.TriggerSchedule` with the schedule IDs | Local admin on target; WinRM/RPC | `ClientActions.ps1` (add to action table) | Low. Bulk needs confirm | Both |
| D2 | Client tools: change cache size, clear cache, repair client, uninstall client, run client health check, restart agent host service, stop client activity, refresh update compliance state | Dev, DevColl | CIM `CCM_SoftMgmtAgent`/`CacheConfig` and `CacheInfoEx`; `ccmrepair.exe` / `ccmsetup.exe` via CIM `Win32_Process.Create` or WinRM; service control; `SMS_Client` `RepairClient`; evaluation via `CCM_SoftwareUpdatesManager` | Local admin; ccmsetup source path must be reachable | Session helper, Process helper (new `Private/Process.ps1`) | ⚠ Uninstall/repair destructive: require typed confirmation; Win32_Process.Create is the remote-exec primitive, so log command text (not secrets) | Both |
| D3 | Rerun deployment (applications, packages, TS) | Dev | CIM on `CCM_Scheduler_History` / `CCM_Application` + trigger evaluation; for old packages, remove from execution history key via CIM `StdRegProv` | Local admin | D2 helpers | Registry edits on client: back up value first | Lab |
| D4 | Client information window: general, components, cache contents, applications, execution history, boundaries/boundary groups | Dev | CIM `root\ccm` classes (`CCM_InstalledComponent`, `CacheInfoEx`, `CCM_Application`, `CCM_ExecutionRequestEx`), SMSP for boundaries | Admin; read-only | 🖥 `New-AZRWindow` | Low | Lab (class shape), CI (formatting) |
| D5 | System information window: installed software, services, processes, drivers, updates, user profiles and sessions, local group members, batteries, disks, network. In-window actions: start/stop service, kill process, delete profile, remove software | Dev | CIM `Win32_*`, `Win32_UserProfile` (`Delete()`), `Win32_ComputerSystem`, `Win32_Battery`; local group via ADSI WinNT provider or WinRM `Get-LocalGroupMember` | Admin | 🖥 window; existing `Get-AZRService`, `Get-AZRDeviceInfo` | ⚠ Profile delete and uninstall are destructive; confirm + audit | Both |
| D6 | Power and network: ping/WinRM test (done), wake-on-LAN, restart/shutdown now, scheduled, cancel; gpupdate | Dev, DevColl | WoL: UDP magic packet from console box (needs MAC from SMSP) or ConfigMgr `SMS_ClientOperation` WoL; restart/shutdown: `Win32_OperatingSystem.Win32Shutdown` or `shutdown.exe /m`; gpupdate via `Win32_Process.Create` | Admin; subnet-directed broadcast for WoL | Collection runner | ⚠ Mass reboot is high blast radius: count confirmation, throttle | Both |
| D7 | Interactive tools: cmd prompt, PowerShell prompt, regedit, event viewer, computer management, C$, process list | Dev | `mstsc`/`psexec`-free: `Enter-PSSession`, MMC `compmgmt.msc /computer`, `eventvwr \\host`, `regedit` remote is not reliable, so use D17 | Admin | Existing `RemoteTools.ps1` | Interactive cmd without `psexec` uses WinRM `Enter-PSSession` only | Lab |
| D8 | Remote Software Center: view and act on applications, updates, task sequences and compliance on the user's device | Dev | CIM `root\ccm\ClientSDK` (`CCM_Application`, `CCM_SoftwareUpdate`, `CCM_Program`), methods `Install`/`Uninstall`/`Repair`, `CCM_SoftwareUpdatesManager.InstallUpdates` | Admin; ClientSDK needs a logged-on user context for some calls | 🖥 window | ◐ Some ClientSDK actions only work in a user session; document limits | Lab |
| D9 | Add device(s) to collection; show device's collections (advanced); remove | Dev, DevColl, User | SMSP `SMS_Collection.AddMembershipRules` (direct rule), `SMS_FullCollectionMembership` for list | ConfigMgr role with Modify Resource/Collection | Existing `Get-AZRCollectionMember` | Change class; validate target collection ID | Both |
| D10 | Status message viewer (device, application) and quick query | Dev, App | SMSP `SMS_StatMsgWithInsStrings`/`SMS_StatusMessage`, Quick Query = parameterised WQL against SMSP | Read-only analyst role | SMSP helper | WQL built only from validated input, never raw user text | Both |
| D11 | Delete device from ConfigMgr; disable/enable and delete from AD; delete from Entra | Dev, DevColl | SMSP `SMS_R_System` delete; ADWS `Disable-ADAccount`/`Remove-ADComputer`; Graph `DELETE /devices/{id}` (see I1) | ConfigMgr Delete Resource; delegated AD rights; `Device.ReadWrite.All` | AD/Graph helpers | ⚠ Destructive: typed confirm, count, audit; AD delete off by default via settings | Lab |
| D12 | Send notification (message box to logged-on user) | Dev, DevColl | `msg.exe` via `Win32_Process.Create` (cheap) or ConfigMgr Run Script | Admin | D2 helpers | Escape message text; length limit | Both |
| D13 | AD security group membership view/edit for computer; Entra group add (see I2) | Dev, User | ADWS `Get-ADPrincipalGroupMembership`, `Add-ADGroupMember` | Delegated AD | AD helper | ⚠ Group changes grant access: require confirm + audit | Lab |
| D14 | Collection tools: bulk anything above with throttling, CSV export, collection health summary | DevColl | Parallel runner (M1); SMSP counts | Same as per-device | M1 | See M1 risks | Both |
| D15 | Run script on device/collection with output | Dev, DevColl | ConfigMgr **Run Scripts** via AdminSvc/SMSP (`SMS_Scripts`, `SMS_ClientOperation` `RunScript`) or WinRM `Invoke-Command` | Run Script RBAC permission; script approval separation of duties | AdminSvc helper | ⚠ Highest-impact feature: signed-script option, approver rules, full audit of script hash | Lab |

### 4.2 Remote tools (GUI helpers)

| # | Feature | Node | Mechanism | Permissions / ports | Notes | Test |
|---|---|---|---|---|---|---|
| R1 | Remote file explorer: browse, upload, download, delete, rename, view | Dev | **Agentless path**: SMB admin share `\\host\C$` through `FileSystem` provider or WinRM `Invoke-Command` with `Get-ChildItem`/`Copy-Item -ToSession`. **Agent-free fast channel path**: ConfigMgr Run Scripts for listing only (no transfer) | Admin; SMB 445 or WinRM | 🖥 WPF tree/list. ◐ Without an agent it needs direct network access, the commercial agent removes that; see §6 | Both |
| R2 | Remote registry: browse/edit keys and values | Dev | CIM `StdRegProv` (WSMan/DCOM), no Remote Registry service needed; or WinRM | Admin; RPC or WinRM | 🖥 ⚠ Edits can brick machines: read-only by default, edit mode with confirm, export-before-edit `.reg` backup | Both |
| R3 | Remote event viewer: filter by log/level/time/ID, export | Dev | `Get-WinEvent -ComputerName` (RPC/Event Log Remote Mgmt firewall rule) or CIM `Win32_NTLogEvent`; WinRM `Get-WinEvent` + filter XML | Event Log Readers or admin | 🖥 | Both |
| R4 | Remote processes (view/kill), remote services | Dev | CIM `Win32_Process`, `Win32_Service` | Admin | Folds into D5 | Both |

### 4.3 Security and compliance

| # | Feature | Node | Mechanism | Permissions / ports | Notes | Test |
|---|---|---|---|---|---|---|
| S1 | BitLocker status per device (done) plus detail: volumes, protectors, TPM, encryption method | Dev | CIM `root\cimv2\Security\MicrosoftVolumeEncryption`, `Win32_Tpm` | Admin | Extends existing | Both |
| S2 | BitLocker recovery key lookup: from AD (`msFVE-RecoveryInformation`), ConfigMgr (BitLocker management feature), Entra/Intune (Graph `informationProtection/bitlocker/recoveryKeys`), MBAM database/web service | Dev | ADWS read of child objects of computer; AdminSvc/SMSP recovery-key method; Graph `BitLockerKey.Read.All`; MBAM via its SQL view/service | Delegated AD "read recovery info"; ConfigMgr "BitLocker recovery key" permission; Graph scope; MBAM access | ⚠ **Secret** class: confirm, reason prompt, audit entry (who/what/when/reason, never the key), UI window only, auto-clear clipboard timer | Lab; CI for formatting/redaction |
| S3 | LAPS passwords (Windows LAPS and legacy), view and set expiration | Dev | `Get-LapsADPassword`/`Set-LapsADPasswordExpirationTime` (needs LAPS PowerShell module) or ADWS attribute read (`ms-Mcs-AdmPwd` legacy; `msLAPS-Password`/`msLAPS-EncryptedPassword`); Entra/Intune LAPS via Graph (`deviceLocalCredentials`, scope `DeviceLocalCredential.Read.All`) | Delegated AD read on attribute; encrypted passwords need decrypt right | ⚠ **Secret** class, same controls as S2 | Lab |
| S4 | Remote Windows Security viewer: BitLocker, TPM, firmware/secure boot, virtualization-based security, Defender state/exclusions/signatures, firewall profiles and rules | Dev | CIM `root\Microsoft\Windows\Defender` (`MSFT_MpComputerStatus`, `MSFT_MpPreference`), `root\StandardCimv2` (`MSFT_NetFirewallProfile`/`Rule`), `Win32_DeviceGuard` (`root\Microsoft\Windows\DeviceGuard`), `Confirm-SecureBootUEFI` over WinRM | Admin | 🖥 read-only window; "trend analysis" is a dashboard (Dash) fed by collected snapshots | Both |
| S5 | Local administrators report | Dev, DevColl | Local group query (D5) | Admin | Bulk output CSV | Both |

### 4.4 Content distribution

| # | Feature | Node | Mechanism | Permissions | Notes | Test |
|---|---|---|---|---|---|---|
| C1 | Content status / information for a DP: packages, validation state, last transfer | DP, App, SU | SMSP `SMS_PackageStatusDistPointsSummarizer`, `SMS_DistributionDPStatus`, `SMS_DPContentInfo` | Read-only role | Grid/window | Both |
| C2 | Redistribute failed content for a DP or package: one-click | DP, DPGroup, App | SMSP `SMS_DistributionPoint.RefreshNow` / CMcmd `Invoke-CMContentRedistribution`, targeted at rows where state is failed/in progress-stale | Distribute content permission | ⚠ Change class, throttle to avoid saturating WAN links; confirm with count | Lab |
| C3 | Content distribution monitor dashboard: failed/pending per DP, by age | Mon | SMSP views | Read | 🖥 | Lab |
| C4 | Application deployment launcher, revision history, all status messages | App | SMSP `SMS_Application` lazy props, `SMS_ApplicationRevision`, status messages | Read | | Both |

### 4.5 Users and user collections
| # | Feature | Node | Mechanism | Notes | Test |
|---|---|---|---|---|---|
| U1 | User devices (primary-device relationships), user status messages | User | SMSP `SMS_UserMachineRelationship`, status messages | Read | Both |
| U2 | Unlock/enable/disable account, reset password, email user, security groups | User | ADWS `Unlock-ADAccount`, `Set-ADAccountPassword`; `mailto:`; group APIs | ⚠ Password reset is a privileged act: confirm, audit, never log value | Lab |
| U3 | Add/remove users to collections | User, UserColl | SMSP direct rules | Same as D9 | Both |

### 4.6 Environment health dashboards (all 🖥)
| # | Dashboard | Source | Notes |
|---|---|---|---|
| H1 | BitLocker compliance | ConfigMgr BitLocker inventory/SMSP + AD/Entra key presence | Highlights devices encrypted without escrowed key |
| H2 | LAPS | AD attribute presence and expiry | No password values shown |
| H3 | Software update deployment status | SMSP compliance views; "targeted scan" = trigger D1 scan for non-compliant members | |
| H4 | Active Directory cleanup | ADWS stale computers/users vs ConfigMgr discovery; bulk disable/delete via D11 | ⚠ Dry-run default |
| H5 | Hardware and firmware audit | SMSP hardware inventory classes (`SMS_G_System_COMPUTER_SYSTEM`, `_PC_BIOS`, `_TPM`), BIOS age/versions | |
| H6 | ConfigMgr site/health | `SMS_ComponentSummarizer`, `SMS_SiteSystemSummarizer`, client health (`SMS_G_System_CH_ClientSummary`), DP/MP status | Read-only |
| H7 | Remote Windows Security trend | Stored snapshots of S4 (SQLite or JSON files) | Needs a retention setting |

### 4.7 Intune, Entra and Autopilot
Graph-based, delegated sign-in, least-privilege scopes per action. Devices need to be identified by `azureADDeviceId`/serial from ConfigMgr (co-managed) or by name.

| # | Feature | Node | Graph endpoint (indicative) | Scope | Notes | Test |
|---|---|---|---|---|---|---|
| I1 | Delete device from Intune and/or Entra, multi-device | Dev, DevColl | `DELETE /deviceManagement/managedDevices/{id}`, `DELETE /devices/{id}` | `DeviceManagementManagedDevices.ReadWrite.All`, `Device.ReadWrite.All` | ⚠ Destructive; typed confirm; handle Autopilot record separately | Lab (tenant) |
| I2 | Add device to Entra security group | Dev, DevColl | `POST /groups/{id}/members/$ref` | `GroupMember.ReadWrite.All` | Group picker with search | Lab |
| I3 | Sync app and compliance policy, restart Intune management extension, send notification | Dev, DevColl | `POST .../managedDevices/{id}/syncDevice`; IME service restart via D2; notification D12 | `DeviceManagementManagedDevices.PrivilegedOperations.All` | | Lab |
| I4 | Open Intune remote help | Dev | Launch the documented remote-help URL/app with device ID | Remote Help licence in the tenant | 🚫 Needs Microsoft's Remote Help licence; we only launch it | Lab |
| I5 | Autopilot: register (hardware hash capture over CIM `MDM_DevDetail_Ext01`), remove, set group tag | Dev, DevColl | `POST /deviceManagement/importedWindowsAutopilotDeviceIdentities`, `DELETE .../windowsAutopilotDeviceIdentities/{id}`, `updateDeviceProperties` | `DeviceManagementServiceConfig.ReadWrite.All` | ⚠ Hash import is async; poll status. Hash reading needs admin and a CIM namespace that exists on Win10+ | Lab |
| I6 | Browser extension for Intune admin center | n/a | Own extension against portal DOM | | 🚫 Skip: brittle, depends on portal markup; tenant-side actions are covered by I1–I5 | n/a |

### 4.8 Kiosk manager
| # | Feature | Mechanism | Notes | Test |
|---|---|---|---|---|
| K1 | Unified Write Filter manager: enable/disable, overlay, protect volumes, exclusions, commit | CIM `root\standardcimv2\embedded` (`UWF_Filter`, `UWF_Volume`, `UWF_OverlayConfig`) | Requires UWF feature on target and reboot; ⚠ misconfiguration loses data on reboot | Lab |
| K2 | Kiosk profiles (Assigned Access / Shell Launcher) apply/view/remove | CIM `root\cimv2\mdm\dmmap` `MDM_AssignedAccess` (needs SYSTEM, so applied through ConfigMgr Run Script or a one-shot scheduled task as SYSTEM) | ◐ Needs SYSTEM context | Lab |
| K3 | Scheduled profile deployment | Scheduled task or ConfigMgr deployment of the profile script, window/maintenance schedule | | Lab |

### 4.9 Automation and API
| # | Feature | Design |
|---|---|---|
| A1 | Workflow builder and runner | Own JSON/YAML workflow schema: ordered steps referencing manifest action IDs, targets from a collection or CSV, conditions, throttles, approvals. Runner = `Invoke-AZRWorkflow` (scheduled task or console). Builder = WPF editor (🖥) that only edits the schema |
| A2 | REST API | Optional small local service (`Start-AZRApi`, localhost/TLS, token auth) exposing the same action dispatcher, running as the calling user. ⚠ Audited like any action; off by default; no separate permission layer (ConfigMgr RBAC and Windows rights apply) |
| A3 | MCP/LLM tool surface | Out of scope for now, listed only because the vendor offers it; revisit after A2 |

## 5. Enterprise-only management and security features

Out of scope by decision: a central management server/web console, our own role-based permission enforcement, commercial product support, a hosted cloud edition, and centralised licence management (the project is free). Permissions rely entirely on ConfigMgr RBAC, AD and Windows rights of the signed-in admin; the docs say so plainly.

| # | Capability | Our approach | Honest status |
|---|---|---|---|
| E1 | Auditing and advanced logging | JSON-lines audit (M1), Windows Event Log, optional forwarding (WEF, syslog, Splunk HEC). Not tamper-proof against the local admin; forward to a log collector for that | ◐ |
| E2 | Cloud Management Gateway support | Route through ConfigMgr channels that already traverse the CMG: **Run Scripts, CMPivot, client notification** via AdminSvc over HTTPS. Direct CIM/DCOM cannot reach internet clients | ◐ Subset of actions only (those expressible as Run Scripts); this also serves as the fast-channel option via client notification |
| E3 | Untrusted domain support | Alternate credentials, HTTPS WinRM (5986) or TrustedHosts, Kerberos-with-SPN or NTLM allowances, AD tools take `-Server`/`-Credential` | Doable; test matrix needs a second forest in lab |

## 6. Vendor agent dependency and what we do instead

The commercial product ships an agent and proxy so remote tools work without direct access to the device. We will not build an agent or any equivalent server component. Order of preference:

1. Direct CIM/WinRM/SMB when the admin workstation can reach the device (the MVP model).
2. ConfigMgr channels (Run Scripts / CMPivot / client notification) when the device is on a CMG or behind firewalls; read-oriented and script-shaped actions only.
3. Anything that needs neither path (for example internet-only devices without a CMG) is out of scope.

## 7. Add-on products

| # | Add-on | Plan | Status |
|---|---|---|---|
| X1 | **Insights**: user-installed software, monitors/docks, network drives and printers, ODBC, local admins, update status, BitLocker/TPM, endpoint protection, warranty, SSRS reports, ITSM integration | Hardware-inventory extension MOF (original classes) + a set of original SSRS `.rdl` reports + dashboards (H-series). Warranty via vendor APIs (Dell, Lenovo, HP) using the admin's own API keys | ◐ Doable. ⚠ Vendor API terms and rate limits; keys in the credential store. ServiceNow/ITSM: REST push, own mapping |
| X2 | **Patching**: third-party application updates, scheduling around Patch Tuesday, notifications | **Winget is the source.** Read package metadata from the winget community repository and its manifests (installer URLs, silent switches, hashes, versions, detection hints) and generate ConfigMgr applications/deployments through CMcmd (Intune via Graph later), with version-compare logic, Patch Tuesday window scheduling and SMTP notifications. No self-maintained catalogue | ◐ Quality depends on winget manifests: some lack reliable detection rules, so we add per-app overrides in a small local file. ⚠ Installers are downloaded from vendor URLs and verified against the manifest SHA-256, never redistributed by us; respect the winget repo licence (MIT) and each vendor's terms. Needs a lab for ConfigMgr application creation |

## 8. Milestones (highest value first)

Effort: S ≈ days, M ≈ 1–2 weeks, L ≈ 3+ weeks of focused work, for one developer.

| Milestone | Contents | Effort | Why this order |
|---|---|---|---|
| **M1 Foundations** | §3: manifest v2 + multi-node generator, GUID discovery tool, settings, alt credentials, parallel runner, CSV export, structured audit, WPF host, AdminSvc client | M | Everything else needs it; also removes the "assumed GUIDs" risk |
| **M2 Client tools and device control** | D1, D2, D3, D5 (window), D6, D9, D10, D11 (ConfigMgr part), D12, D14, R4 | L | The daily-driver items; mostly CIM and fully agentless |
| **M3 Security keys and status** | S1–S5, H1/H2 quick views | M | High audit value, small surface; sets the **Secret** pattern reused later |
| **M4 Remote GUI tools** | R1, R2, R3, D4, D8 (remote Software Center) | L | Largest visible gap versus the MVP; reuses the WPF host |
| **M5 Content, apps, users, collections** | C1, C2, C4, U1, U3, D13 | M | Admin workflow breadth across other nodes |
| **M6 Intune / Entra / Autopilot** | I1–I5, D11 cloud part | L | Needs Graph helper and a test tenant; modern-management need |
| **M7 Dashboards** | H1–H7, C3 | L | Built on M2–M6 data helpers |
| **M8 Hard environments** | E1 (audit forwarding), E2 (CMG via Run Scripts), E3 (untrusted domains), D15 | M | Needed in larger or segmented orgs; no role layer, so rights come from ConfigMgr/AD |
| **M9 Kiosk manager** | K1–K3 | M | Niche, lab-heavy |
| **M10 Automation + API** | A1, A2 | L | Best once the action set is stable |
| **M11 Insights and patching** | X1, X2 (winget-based) | L | Largest legal risk is installer licensing; optional |
| **Out of scope** | Management server, agent, role enforcement, commercial support, hosted edition, privileged-access add-on (needs server/agent), I6, A3 | | See §5–§6 |

Suggested first slice for review: **M1 + M2 + M3**.

## 9. Testing strategy

**CI (`windows-latest`, Pester + PSScriptAnalyzer) can cover:**
- Manifest ↔ function mapping, schema, XML generation/escaping per node (M1).
- All validators, including new placeholders and negative cases (injection strings).
- Business logic behind mocks: result shaping, redaction of secrets, audit entries, confirmation policy, throttling, workflow evaluation, winget manifest parsing.
- Graph and AdminSvc clients against a local stub HTTP server (request shape, paging, errors).
- WPF windows can be constructed headlessly for load/binding smoke tests; layout is checked manually.
- Add a CI rule: no function that writes a `Secret`-class value to the log (static test over audit/log calls).

**Lab only:** real CIM calls against clients, SMS Provider/AdminSvc, console menu rendering and placeholders per console version, AD/LAPS/BitLocker key retrieval, DP redistribution, UWF/Assigned Access, Graph with a real tenant and Autopilot, WoL, CMG scenarios, untrusted-domain matrix. Plan: a small lab checklist per milestone in `docs/LAB-TESTS.md`, and feature status in README switches from "planned" to "lab-verified" only after it is ticked.

## 10. Security and licensing notes

- Secrets (S2, S3, U2): confirmation, reason capture, audit, UI-only display, clipboard auto-clear, never in logs/command lines. We do not add our own permission layer; anyone who can run the tool with their own rights can read what those rights allow, and the docs state that.
- Remote execution primitives (`Win32_Process.Create`, Run Scripts, WinRM): commands are built only from fixed templates plus validated parameters; scripts for D15 are stored, hashed, and logged by hash.
- Graph: delegated, interactive auth, per-feature scopes, no stored refresh tokens beyond MSAL's cache.
- Bulk actions: count-based confirmation, throttle, dry-run for destructive ones.
- Licensing: MIT for our code; do not copy vendor text/icons/binaries. Depending on Microsoft modules (`Microsoft.Graph.Authentication`, RSAT, ConfigMgr module) is fine as separate installs. Do not bundle vendor installers or third-party catalogues without licence review. Remote Help and Autopilot use Microsoft licences the customer already holds. Product names of the commercial tool are used only for comparison in this plan.
- "Not affiliated" statement stays in README.

## Sources

Capability list from the supplied feature overview PDF, cross-checked against public pages: the vendor's Right Click Tools page and documentation menu (<https://www.recastsoftware.com/right-click-tools/>, <https://docs.recastsoftware.com/help/right-click-tools>, remote file explorer page). The documentation indicates remote tools work best with the vendor agent and does not publish protocol/port detail, so mechanisms above are our own design based on Microsoft documentation (ConfigMgr client SDK/SMS Provider reference, AdminService, Microsoft Graph, Windows LAPS, UWF/Assigned Access WMI providers). Items marked "verify" in this plan, especially Graph endpoints and client class details, should be confirmed against current Microsoft docs and a lab before implementation.
