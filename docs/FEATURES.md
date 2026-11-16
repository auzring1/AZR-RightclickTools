# Feature roadmap

Legend: ✅ in MVP, ⬜ planned.

## P0 Client actions
- ✅ Machine/User policy retrieval, Hardware & Software inventory, Discovery, Updates scan/evaluation, App evaluation
- ✅ Restart CcmExec
- ⬜ Client repair / reinstall, clear client cache, reset policy, trigger specific update/deployment, run Task Sequence eval
- ⬜ Re-run failed deployment, reset WMI repository helper

## P1 Remote tools
- ✅ Ping/WinRM test, RDP, remote PowerShell, C$ browse, client logs folder, services, recent errors, Computer Management
- ⬜ Remote registry browser, processes viewer/kill, scheduled tasks, installed software list and uninstall, run script/command with output, remote file copy
- ⬜ Wake-on-LAN (via site WoL or magic packet), reboot / shutdown with message and delay, remote assistance/Remote Control launch

## P1 Device info
- ✅ Logged-on user, last boot/uptime, OS, model, serial, IP/MAC, disk free, client version, pending reboot, BitLocker status
- ⬜ BitLocker recovery key lookup (role-gated), LAPS password lookup (role-gated), local admins, last patch date, hardware/warranty

## P2 Collections & bulk
- ✅ Client actions and ping on every collection member
- ⬜ Parallel execution with throttling, CSV export, collection health summary, add/remove devices to collection

## P2 Other
- ⬜ Content: distribute/validate content on DPs, DP health
- ⬜ Admin Service backend, alternate credentials, per-action RBAC allow-list, audit log shipping
- ⬜ Intune counterpart (Graph) as a separate module
