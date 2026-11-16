# Action manifest: drives generation of the ConfigMgr console extension XML.
# Targets: Device = Devices node, Collection = Device Collections node.
@{
    Menu = 'AZR Tools'
    Groups = @(
        @{
            Name = 'Client Actions'
            Actions = @(
                @{ Id = 'MachinePolicyRetrieval';    Name = 'Machine Policy Retrieval && Evaluation'; Targets = 'Device', 'Collection'; Description = 'Triggers machine policy retrieval and evaluation.' }
                @{ Id = 'UserPolicyRetrieval';       Name = 'User Policy Retrieval';       Targets = 'Device', 'Collection'; Description = 'Triggers user policy retrieval.' }
                @{ Id = 'HardwareInventory';         Name = 'Hardware Inventory';          Targets = 'Device', 'Collection'; Description = 'Triggers a hardware inventory cycle.' }
                @{ Id = 'SoftwareInventory';         Name = 'Software Inventory';          Targets = 'Device', 'Collection'; Description = 'Triggers a software inventory cycle.' }
                @{ Id = 'DiscoveryDataCollection';   Name = 'Discovery Data Collection';   Targets = 'Device', 'Collection'; Description = 'Triggers a heartbeat discovery.' }
                @{ Id = 'SoftwareUpdatesScan';       Name = 'Software Updates Scan';       Targets = 'Device', 'Collection'; Description = 'Triggers a software updates scan.' }
                @{ Id = 'SoftwareUpdatesEvaluation'; Name = 'Software Updates Evaluation'; Targets = 'Device', 'Collection'; Description = 'Triggers software update deployment evaluation.' }
                @{ Id = 'ApplicationEvaluation';     Name = 'Application Deployment Evaluation'; Targets = 'Device', 'Collection'; Description = 'Triggers application deployment evaluation.' }
                @{ Id = 'RestartCcmExec';            Name = 'Restart ConfigMgr Client Service'; Targets = 'Device'; Description = 'Restarts the CcmExec service.' }
            )
        }
        @{
            Name = 'Remote Tools'
            Actions = @(
                @{ Id = 'Ping';               Name = 'Ping / WinRM Test';       Targets = 'Device', 'Collection'; Description = 'Checks ping and WinRM reachability.' }
                @{ Id = 'Rdp';                Name = 'Remote Desktop (RDP)';    Targets = 'Device'; Description = 'Opens an RDP session.' }
                @{ Id = 'RdpAdmin';           Name = 'Remote Desktop (Admin Console)'; Targets = 'Device'; Description = 'Opens an RDP admin session.' }
                @{ Id = 'RemoteShell';        Name = 'Remote PowerShell';       Targets = 'Device'; Description = 'Opens an interactive PowerShell remoting session.' }
                @{ Id = 'BrowseC';            Name = 'Browse C$';               Targets = 'Device'; Description = 'Opens the administrative C$ share.' }
                @{ Id = 'ClientLogs';         Name = 'Open ConfigMgr Client Logs'; Targets = 'Device'; Description = 'Opens C:\Windows\CCM\Logs.' }
                @{ Id = 'Services';           Name = 'View Services';           Targets = 'Device'; Description = 'Lists services in a grid.' }
                @{ Id = 'EventLog';           Name = 'View Recent System Errors'; Targets = 'Device'; Description = 'Shows recent critical/error/warning System events.' }
                @{ Id = 'ComputerManagement'; Name = 'Computer Management';     Targets = 'Device'; Description = 'Opens Computer Management for the device.' }
            )
        }
        @{
            Name = 'Device Info'
            Actions = @(
                @{ Id = 'DeviceInfo'; Name = 'Live Device Info'; Targets = 'Device'; Description = 'Logged-on user, last boot, IP, disk, client version, pending reboot, BitLocker.' }
            )
        }
    )
}
