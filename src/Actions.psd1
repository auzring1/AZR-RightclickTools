# Action manifest (schema v2): drives generation of the ConfigMgr console extension XML and the confirmation / audit policy.
#   Id          unique, must have a handler in the module (Private\ActionRegistry.ps1)
#   Targets     nodes from Nodes.psd1: Device, Collection (others once their GUIDs are discovered)
#   Risk        Read (default) | Change | Destructive | Secret   - drives confirmation and audit (see docs\ARCHITECTURE.md)
#   Confirm     Auto (default) | None  - None skips the single-device Yes/No prompt for harmless Change actions
#   Requires    optional: AD, Graph, AdminSvc, ConfigMgrModule, SmsProvider (prerequisites shown in the docs and errors)
#   Ui          optional: None | Grid | Window:<name>
@{
    SchemaVersion = 2
    Menu = 'AZR Tools'
    Groups = @(
        @{
            Name = 'Client Actions'
            Actions = @(
                @{ Id = 'MachinePolicyRetrieval';    Name = 'Machine Policy Retrieval && Evaluation'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers machine policy retrieval and evaluation.' }
                @{ Id = 'UserPolicyRetrieval';       Name = 'User Policy Retrieval';       Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers user policy retrieval.' }
                @{ Id = 'HardwareInventory';         Name = 'Hardware Inventory';          Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers a hardware inventory cycle.' }
                @{ Id = 'SoftwareInventory';         Name = 'Software Inventory';          Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers a software inventory cycle.' }
                @{ Id = 'DiscoveryDataCollection';   Name = 'Discovery Data Collection';   Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers a heartbeat discovery.' }
                @{ Id = 'SoftwareUpdatesScan';       Name = 'Software Updates Scan';       Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers a software updates scan.' }
                @{ Id = 'SoftwareUpdatesEvaluation'; Name = 'Software Updates Evaluation'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers software update deployment evaluation.' }
                @{ Id = 'ApplicationEvaluation';     Name = 'Application Deployment Evaluation'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers application deployment evaluation.' }
                @{ Id = 'FileCollection';            Name = 'File Collection';             Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers the file collection cycle.' }
                @{ Id = 'SoftwareMeteringUsage';     Name = 'Software Metering Usage Report'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers the software metering usage report cycle.' }
                @{ Id = 'WindowsInstallerSource';    Name = 'Windows Installer Source List Update'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers the Windows Installer source list update cycle.' }
                @{ Id = 'SendUnsentStateMessages';   Name = 'Send Unsent State Messages';  Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Sends state messages the client has not yet delivered.' }
                @{ Id = 'ComplianceEvaluation';      Name = 'Compliance (Baseline) Evaluation'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Triggers configuration baseline evaluation.' }
                @{ Id = 'RefreshUpdateCompliance';   Name = 'Refresh Update Compliance State'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Software updates scan, deployment evaluation and state message send, in order.' }
            )
        }
        @{
            Name = 'Client Tools'
            Actions = @(
                @{ Id = 'ClientHealthCheck';  Name = 'Run Client Health Check';   Targets = 'Device', 'Collection'; Risk = 'Change'; Description = 'Starts the Configuration Manager Health Evaluation task on the client.' }
                @{ Id = 'ClientCache';        Name = 'View Client Cache';         Targets = 'Device'; Risk = 'Read'; Ui = 'Grid'; Description = 'Shows cache size, location and cached content.' }
                @{ Id = 'ClearClientCache';   Name = 'Clear Client Cache';        Targets = 'Device', 'Collection'; Risk = 'Change'; Description = 'Deletes cached content on the client (it is downloaded again when needed).' }
                @{ Id = 'SetClientCacheSize'; Name = 'Set Client Cache Size...';  Targets = 'Device', 'Collection'; Risk = 'Change'; Description = 'Changes the client cache size in MB.' }
                @{ Id = 'RestartCcmExec';     Name = 'Restart ConfigMgr Client Service'; Targets = 'Device'; Risk = 'Change'; Description = 'Restarts the CcmExec service.' }
                @{ Id = 'StopCcmExec';        Name = 'Stop ConfigMgr Client Service'; Targets = 'Device'; Risk = 'Change'; Description = 'Stops the CcmExec service (stops all client activity until it is started again).' }
                @{ Id = 'RepairClient';       Name = 'Repair ConfigMgr Client';   Targets = 'Device', 'Collection'; Risk = 'Destructive'; Description = 'Starts a client repair.' }
                @{ Id = 'UninstallClient';    Name = 'Uninstall ConfigMgr Client'; Targets = 'Device', 'Collection'; Risk = 'Destructive'; Description = 'Uninstalls the client; the device stops being managed until it is reinstalled.' }
            )
        }
        @{
            Name = 'Power and Messages'
            Actions = @(
                @{ Id = 'WakeOnLan';       Name = 'Wake-on-LAN';              Targets = 'Device', 'Collection'; Risk = 'Change'; Requires = 'SmsProvider'; Description = 'Sends a magic packet using the MAC address stored in ConfigMgr.' }
                @{ Id = 'Restart';         Name = 'Restart (60 s warning)';   Targets = 'Device', 'Collection'; Risk = 'Destructive'; Description = 'Restarts the computer after a 60 second warning.' }
                @{ Id = 'Shutdown';        Name = 'Shut Down (60 s warning)'; Targets = 'Device', 'Collection'; Risk = 'Destructive'; Description = 'Shuts the computer down after a 60 second warning.' }
                @{ Id = 'AbortShutdown';   Name = 'Cancel Pending Restart/Shutdown'; Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Cancels a delayed restart or shutdown.' }
                @{ Id = 'GpUpdate';        Name = 'Group Policy Update';      Targets = 'Device', 'Collection'; Risk = 'Change'; Confirm = 'None'; Description = 'Runs gpupdate /force.' }
                @{ Id = 'SendNotification'; Name = 'Send Message to User...'; Targets = 'Device', 'Collection'; Risk = 'Change'; Description = 'Shows a message to the logged-on users.' }
            )
        }
        @{
            Name = 'Collections and Status'
            Actions = @(
                @{ Id = 'ShowCollections';       Name = 'Show Collections of Device'; Targets = 'Device'; Risk = 'Read'; Requires = 'SmsProvider'; Ui = 'Grid'; Description = 'Lists the collections the device is a member of.' }
                @{ Id = 'AddToCollection';       Name = 'Add to Collection...';       Targets = 'Device'; Risk = 'Change'; Requires = 'SmsProvider'; Description = 'Adds the device to a device collection with a direct rule.' }
                @{ Id = 'RemoveFromCollection';  Name = 'Remove from Collection...';  Targets = 'Device'; Risk = 'Change'; Requires = 'SmsProvider'; Description = 'Removes the device direct membership rule from a collection.' }
                @{ Id = 'StatusMessages';        Name = 'Status Messages (last 24 h)'; Targets = 'Device'; Risk = 'Read'; Requires = 'SmsProvider'; Ui = 'Grid'; Description = 'Shows recent status messages for the device.' }
                @{ Id = 'CollectionSummary';     Name = 'Collection Health Summary';  Targets = 'Collection'; Risk = 'Read'; Requires = 'SmsProvider'; Ui = 'Grid'; Description = 'Members, clients, active clients and last membership change.' }
                @{ Id = 'ExportMembers';         Name = 'Export Members to CSV';      Targets = 'Collection'; Risk = 'Read'; Requires = 'SmsProvider'; Description = 'Writes the member list to a CSV file.' }
                @{ Id = 'DeleteFromConfigMgr';   Name = 'Delete Device from ConfigMgr'; Targets = 'Device'; Risk = 'Destructive'; Requires = 'SmsProvider'; Description = 'Deletes the device record from ConfigMgr.' }
            )
        }
        @{
            Name = 'Remote Tools'
            Actions = @(
                @{ Id = 'Ping';               Name = 'Ping / WinRM Test';       Targets = 'Device', 'Collection'; Risk = 'Read'; Ui = 'Grid'; Description = 'Checks ping and WinRM reachability.' }
                @{ Id = 'Rdp';                Name = 'Remote Desktop (RDP)';    Targets = 'Device'; Risk = 'Read'; Description = 'Opens an RDP session.' }
                @{ Id = 'RdpAdmin';           Name = 'Remote Desktop (Admin Console)'; Targets = 'Device'; Risk = 'Read'; Description = 'Opens an RDP admin session.' }
                @{ Id = 'RemoteShell';        Name = 'Remote PowerShell';       Targets = 'Device'; Risk = 'Read'; Description = 'Opens an interactive PowerShell remoting session.' }
                @{ Id = 'BrowseC';            Name = 'Browse C$';               Targets = 'Device'; Risk = 'Read'; Description = 'Opens the administrative C$ share.' }
                @{ Id = 'ClientLogs';         Name = 'Open ConfigMgr Client Logs'; Targets = 'Device'; Risk = 'Read'; Description = 'Opens C:\Windows\CCM\Logs.' }
                @{ Id = 'Services';           Name = 'View Services';           Targets = 'Device'; Risk = 'Read'; Ui = 'Grid'; Description = 'Lists services in a grid.' }
                @{ Id = 'EventLog';           Name = 'View Recent System Errors'; Targets = 'Device'; Risk = 'Read'; Ui = 'Grid'; Description = 'Shows recent critical/error/warning System events.' }
                @{ Id = 'ComputerManagement'; Name = 'Computer Management';     Targets = 'Device'; Risk = 'Read'; Description = 'Opens Computer Management for the device.' }
                @{ Id = 'SystemInfo';         Name = 'System Information (window)'; Targets = 'Device'; Risk = 'Read'; Ui = 'Window:SystemInfo'; Description = 'Software, services, processes, updates, profiles, sessions, local admins, disks and network, with service/process/profile/software actions.' }
            )
        }
        @{
            Name = 'Security'
            Actions = @(
                @{ Id = 'BitLockerDetail';      Name = 'BitLocker Details';              Targets = 'Device'; Risk = 'Read'; Ui = 'Grid'; Description = 'Volumes, protection state, encryption method and protector types.' }
                @{ Id = 'BitLockerRecoveryKey'; Name = 'BitLocker Recovery Key...';      Targets = 'Device'; Risk = 'Secret'; Requires = 'AD', 'Graph'; Ui = 'Window:Secret'; Description = 'Looks up recovery keys in Active Directory and Entra ID. Asks for a reason and is audited.' }
                @{ Id = 'LapsStatus';           Name = 'LAPS Status';                    Targets = 'Device', 'Collection'; Risk = 'Read'; Requires = 'AD'; Ui = 'Grid'; Description = 'LAPS flavor, account, last change and expiry. No passwords.' }
                @{ Id = 'LapsPassword';         Name = 'LAPS Password...';               Targets = 'Device'; Risk = 'Secret'; Requires = 'AD', 'Graph'; Ui = 'Window:Secret'; Description = 'Shows the local administrator password. Asks for a reason and is audited.' }
                @{ Id = 'LapsRotate';           Name = 'Force LAPS Password Rotation';   Targets = 'Device'; Risk = 'Change'; Requires = 'AD'; Description = 'Sets the LAPS expiry to now so the client rotates the password.' }
                @{ Id = 'WindowsSecurity';      Name = 'Windows Security (window)';      Targets = 'Device'; Risk = 'Read'; Ui = 'Window:WindowsSecurity'; Description = 'Defender, firewall, Device Guard, Secure Boot, TPM and BitLocker state.' }
                @{ Id = 'LocalAdmins';          Name = 'Local Administrators';           Targets = 'Device', 'Collection'; Risk = 'Read'; Ui = 'Grid'; Description = 'Members of the local Administrators group.' }
                @{ Id = 'BitLockerCompliance';  Name = 'BitLocker Compliance (live)';    Targets = 'Collection'; Risk = 'Read'; Requires = 'AD'; Ui = 'Grid'; Description = 'OS volume protection, recovery protector and AD key escrow per member.' }
            )
        }
        @{
            Name = 'Device Info'
            Actions = @(
                @{ Id = 'DeviceInfo'; Name = 'Live Device Info'; Targets = 'Device'; Risk = 'Read'; Ui = 'Grid'; Description = 'Logged-on user, last boot, IP, disk, client version, pending reboot, BitLocker.' }
            )
        }
    )
}
