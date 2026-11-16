# Feature status

Legend: ✅ implemented (logic unit-tested, **not yet lab-verified**), 🧪 lab-verified, ⬜ planned. Nothing is marked 🧪 until it is ticked in [LAB-TESTS.md](LAB-TESTS.md). Full plan: [ROADMAP-FULL.md](ROADMAP-FULL.md).

## M1 Foundations
- ✅ Manifest v2 (risk, confirm, requires, ui), node table, validating multi-node generator
- ✅ `tools/Get-AZRConsoleNodes.ps1` GUID/placeholder discovery
- ✅ Settings (user + machine policy), alternate credentials (DPAPI), structured audit log, parallel runner, CSV/JSON/clipboard export, WPF host, AdminService client, Graph helper

## M2 Client tools and device control
- ✅ D1 more client actions (file collection, metering, installer source, state messages, baselines, update compliance refresh)
- ✅ D2 client cache view/clear/resize, repair, uninstall, health check, stop/restart CcmExec
- ✅ D3 execution-history reset (function only; needs a package ID, no menu item yet)
- ✅ D5/R4 system information window with service/process/profile/MSI actions
- ✅ D6 Wake-on-LAN, restart/shutdown/cancel, gpupdate; D12 send message
- ✅ D9 add/remove/show collections; D10 status messages + validated quick query; D11 delete from ConfigMgr; D14 bulk runner, collection summary, member export

## M3 Security
- ✅ S1 BitLocker details and TPM
- ✅ S2 BitLocker recovery keys from AD and Entra ID (⬜ ConfigMgr/MBAM sources)
- ✅ S3 LAPS status/password (Windows LAPS, legacy, Entra) and forced rotation
- ✅ S4 Remote Windows Security window
- ✅ S5 local administrators report; H1/H2 quick views (live BitLocker compliance, LAPS status per collection)

## Not in scope
No agent, no management server, no role enforcement, no commercial support. Patch catalogue (Winget) is a later milestone.

## Later milestones
M4 remote GUI tools, M5 content/apps/users, M6 Intune/Entra/Autopilot, M7 dashboards, and so on, as in the roadmap.
