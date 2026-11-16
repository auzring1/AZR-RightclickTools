function Get-AZRDeviceInfo {
    <#
    .SYNOPSIS
        Collects a snapshot of live device information from the computer via CIM.
        Each section is best-effort; failures are reported in the Notes property.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName,
        [pscredential]$Credential
    )
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        $notes = New-Object System.Collections.Generic.List[string]
        $info = [ordered]@{
            ComputerName = $ComputerName; LoggedOnUser = $null; LastBoot = $null; Uptime = $null
            OperatingSystem = $null; OSBuild = $null; Manufacturer = $null; Model = $null
            SerialNumber = $null; IPAddress = $null; MacAddress = $null; SystemDriveFreeGB = $null
            ClientVersion = $null; PendingReboot = $null; BitLocker = $null; Notes = $null
        }
        $session = New-AZRCimSession -ComputerName $ComputerName -Credential $Credential
        try {
            $get = {
                param($Class, $Namespace = 'root\cimv2', $Filter)
                $p = @{ CimSession = $session; Namespace = $Namespace; ClassName = $Class; ErrorAction = 'Stop' }
                if ($Filter) { $p.Filter = $Filter }
                Get-CimInstance @p
            }
            try {
                $cs = & $get 'Win32_ComputerSystem'
                $info.LoggedOnUser = $cs.UserName; $info.Manufacturer = $cs.Manufacturer; $info.Model = $cs.Model
            } catch { $notes.Add("ComputerSystem: $($_.Exception.Message)") }
            try {
                $os = & $get 'Win32_OperatingSystem'
                $info.OperatingSystem = $os.Caption; $info.OSBuild = $os.BuildNumber
                $info.LastBoot = $os.LastBootUpTime
                $info.Uptime = '{0}d {1}h {2}m' -f ($os.LocalDateTime - $os.LastBootUpTime).Days, ($os.LocalDateTime - $os.LastBootUpTime).Hours, ($os.LocalDateTime - $os.LastBootUpTime).Minutes
                $sysDrive = $os.SystemDrive
            } catch { $notes.Add("OperatingSystem: $($_.Exception.Message)") }
            try { $info.SerialNumber = (& $get 'Win32_BIOS').SerialNumber } catch { $notes.Add("BIOS: $($_.Exception.Message)") }
            try {
                $nics = @(& $get 'Win32_NetworkAdapterConfiguration' 'root\cimv2' 'IPEnabled = TRUE')
                $info.IPAddress = ($nics.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) -join ', '
                $info.MacAddress = ($nics.MACAddress | Where-Object { $_ }) -join ', '
            } catch { $notes.Add("Network: $($_.Exception.Message)") }
            try {
                if (-not $sysDrive) { $sysDrive = 'C:' }
                $disk = & $get 'Win32_LogicalDisk' 'root\cimv2' "DeviceID = '$sysDrive'"
                $info.SystemDriveFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
            } catch { $notes.Add("Disk: $($_.Exception.Message)") }
            try { $info.ClientVersion = (& $get 'SMS_Client' 'root\ccm').ClientVersion } catch { $notes.Add('ConfigMgr client not reachable') }
            try {
                $r = Invoke-CimMethod -CimSession $session -Namespace 'root\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction Stop
                $info.PendingReboot = [bool]($r.RebootPending -or $r.IsHardRebootPending)
            } catch { $notes.Add('PendingReboot: unavailable') }
            try {
                $vols = @(& $get 'Win32_EncryptableVolume' 'root\cimv2\Security\MicrosoftVolumeEncryption')
                $info.BitLocker = ($vols | ForEach-Object {
                        '{0} {1}' -f $_.DriveLetter, $(switch ($_.ProtectionStatus) { 0 { 'Off' } 1 { 'On' } 2 { 'Unknown' } default { '?' } })
                    }) -join '; '
            } catch { $notes.Add('BitLocker: unavailable') }
        }
        finally { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
        $info.Notes = $notes -join ' | '
        [pscustomobject]$info
    }
}
