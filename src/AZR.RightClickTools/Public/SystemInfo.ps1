# System information (roadmap D5, R4, S5): one data function per section, a window that shows them, and the
# per-row actions (services, processes, profiles, software). All remote access is CIM/WMI, agentless.

function Get-AZRSystemInfoSection {
    <# Names of the sections Get-AZRSystemInfo can return. #>
    'Software', 'Services', 'Processes', 'Updates', 'Profiles', 'Sessions', 'LocalAdmins', 'Batteries', 'Disks', 'Network'
}

function Get-AZRSystemInfo {
    <#
    .SYNOPSIS
        Returns one section of system information for a computer as plain objects.
    .PARAMETER Section
        Software, Services, Processes, Updates, Profiles, Sessions, LocalAdmins, Batteries, Disks or Network.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateSet('Software', 'Services', 'Processes', 'Updates', 'Profiles', 'Sessions', 'LocalAdmins', 'Batteries', 'Disks', 'Network')][string]$Section,
        [pscredential]$Credential
    )
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($s)
            switch ($Section) {
                'Software' {
                    foreach ($root in 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
                        foreach ($k in Get-AZRRegSubKey -Session $s -SubKey $root) {
                            $path = "$root\$k"
                            $name = Get-AZRRegString -Session $s -SubKey $path -ValueName 'DisplayName'
                            if (-not $name) { continue }
                            $isMsi = $k -match '^\{[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}$'
                            [pscustomobject]@{
                                ComputerName = $ComputerName
                                Name         = $name
                                Version      = Get-AZRRegString -Session $s -SubKey $path -ValueName 'DisplayVersion'
                                Publisher    = Get-AZRRegString -Session $s -SubKey $path -ValueName 'Publisher'
                                ProductCode  = if ($isMsi) { $k } else { $null }
                                Architecture = if ($root -match 'WOW6432Node') { 'x86' } else { 'native' }
                            }
                        }
                    }
                }
                'Services' {
                    Get-AZRCim -Session $s -ClassName Win32_Service | Sort-Object Name | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; Name = $_.Name; DisplayName = $_.DisplayName; State = $_.State; StartMode = $_.StartMode; Account = $_.StartName }
                    }
                }
                'Processes' {
                    Get-AZRCim -Session $s -ClassName Win32_Process | Sort-Object Name | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; ProcessId = $_.ProcessId; Name = $_.Name; WorkingSetMB = [math]::Round($_.WorkingSetSize / 1MB, 1); CommandLine = $_.CommandLine }
                    }
                }
                'Updates' {
                    Get-AZRCim -Session $s -ClassName Win32_QuickFixEngineering | Sort-Object InstalledOn -Descending | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; HotFixID = $_.HotFixID; Description = $_.Description; InstalledOn = $_.InstalledOn; InstalledBy = $_.InstalledBy }
                    }
                }
                'Profiles' {
                    Get-AZRCim -Session $s -ClassName Win32_UserProfile | Where-Object { -not $_.Special } | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; Path = $_.LocalPath; Sid = $_.SID; Loaded = $_.Loaded; LastUseTime = $_.LastUseTime }
                    }
                }
                'Sessions' {
                    Get-AZRCim -Session $s -ClassName Win32_LogonSession -Filter 'LogonType = 2 OR LogonType = 10 OR LogonType = 11' | ForEach-Object {
                        $who = Get-AZRCimAssociated -Session $s -InputObject $_ -Association Win32_LoggedOnUser | Select-Object -First 1
                        [pscustomobject]@{
                            ComputerName = $ComputerName
                            User         = if ($who) { '{0}\{1}' -f $who.Domain, $who.Name } else { '' }
                            LogonType    = switch ([int]$_.LogonType) { 2 { 'Console' } 10 { 'Remote desktop' } 11 { 'Cached' } default { [string]$_.LogonType } }
                            Started      = $_.StartTime
                        }
                    }
                }
                'LocalAdmins' {
                    # Well-known SID so this works on every OS language.
                    $grp = Get-AZRCim -Session $s -ClassName Win32_Group -Filter "SID = 'S-1-5-32-544'" | Select-Object -First 1
                    if ($grp) {
                        Get-AZRCimAssociated -Session $s -InputObject $grp -Association Win32_GroupUser | ForEach-Object {
                            [pscustomobject]@{ ComputerName = $ComputerName; Member = '{0}\{1}' -f $_.Domain, $_.Name; Sid = $_.SID; Type = ($_.CimClass.CimClassName -replace '^Win32_', '') }
                        }
                    }
                }
                'Batteries' {
                    Get-AZRCim -Session $s -ClassName Win32_Battery | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; Name = $_.Name; ChargePercent = $_.EstimatedChargeRemaining; Status = $_.BatteryStatus; DesignVoltage = $_.DesignVoltage }
                    }
                }
                'Disks' {
                    Get-AZRCim -Session $s -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; Drive = $_.DeviceID; Label = $_.VolumeName; FileSystem = $_.FileSystem; SizeGB = [math]::Round($_.Size / 1GB, 1); FreeGB = [math]::Round($_.FreeSpace / 1GB, 1) }
                    }
                }
                'Network' {
                    Get-AZRCim -Session $s -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; Adapter = $_.Description; IPAddress = ($_.IPAddress -join ', '); Gateway = ($_.DefaultIPGateway -join ', '); Dns = ($_.DNSServerSearchOrder -join ', '); Mac = $_.MACAddress; Dhcp = $_.DHCPEnabled }
                    }
                }
            }
        }
    }
}

function Get-AZRLocalAdministrator {
    <# Members of the local Administrators group (S5). One row per member; failures are returned as a row with Success = $false. #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName, [pscredential]$Credential)
    process {
        foreach ($c in $ComputerName) {
            try { Get-AZRSystemInfo -ComputerName $c -Section LocalAdmins -Credential $Credential }
            catch { [pscustomobject]@{ ComputerName = $c; Member = $null; Sid = $null; Type = $null; Success = $false; Message = $_.Exception.Message } }
        }
    }
}

function Set-AZRServiceState {
    <# Starts or stops a service via Win32_Service. #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Start', 'Stop')][string]$State,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $Name = Assert-AZRServiceName -Name $Name
    $row = [ordered]@{ ComputerName = $ComputerName; Action = "$State service $Name"; Success = $false; Message = '' }
    if ($PSCmdlet.ShouldProcess("$ComputerName\$Name", "$State service")) {
        try {
            Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                param($s)
                $svc = Get-AZRCim -Session $s -ClassName Win32_Service -Filter "Name = '$Name'" | Select-Object -First 1
                if (-not $svc) { throw "Service '$Name' not found." }
                $r = Invoke-AZRCimOnInstance -Session $s -InputObject $svc -MethodName "${State}Service"
                if ($r.ReturnValue -ne 0) { throw "${State}Service returned $($r.ReturnValue)" }
            }
            $row.Success = $true; $row.Message = 'Done'
            Write-AZRLog -Message "$State service $Name on $ComputerName"
        }
        catch { $row.Message = $_.Exception.Message }
    }
    [pscustomobject]$row
}

function Stop-AZRRemoteProcess {
    <# Ends a process by ID (Win32_Process.Terminate). #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$ProcessId,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $row = [ordered]@{ ComputerName = $ComputerName; Action = "End process $ProcessId"; Success = $false; Message = '' }
    if ($PSCmdlet.ShouldProcess("$ComputerName process $ProcessId", 'Terminate')) {
        try {
            Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                param($s)
                $p = Get-AZRCim -Session $s -ClassName Win32_Process -Filter "ProcessId = $ProcessId" | Select-Object -First 1
                if (-not $p) { throw "Process $ProcessId not found." }
                $r = Invoke-AZRCimOnInstance -Session $s -InputObject $p -MethodName Terminate
                if ($r.ReturnValue -ne 0) { throw "Terminate returned $($r.ReturnValue)" }
            }
            $row.Success = $true; $row.Message = 'Ended'
            Write-AZRLog -Message "Ended process $ProcessId on $ComputerName"
        }
        catch { $row.Message = $_.Exception.Message }
    }
    [pscustomobject]$row
}

function Remove-AZRUserProfile {
    <# Deletes a user profile that is not loaded (Win32_UserProfile.Delete). Destructive: the user's local data is lost. #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidatePattern('^S-1-[0-9\-]{5,80}$')][string]$Sid,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $row = [ordered]@{ ComputerName = $ComputerName; Action = "Delete profile $Sid"; Success = $false; Message = '' }
    if ($PSCmdlet.ShouldProcess("$ComputerName profile $Sid", 'Delete')) {
        try {
            Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                param($s)
                $p = Get-AZRCim -Session $s -ClassName Win32_UserProfile -Filter "SID = '$Sid'" | Select-Object -First 1
                if (-not $p) { throw "Profile $Sid not found." }
                if ($p.Loaded) { throw 'The profile is loaded (user signed in); sign the user out first.' }
                if ($p.Special) { throw 'Refusing to delete a system profile.' }
                $null = Invoke-AZRCimOnInstance -Session $s -InputObject $p -MethodName Delete
            }
            $row.Success = $true; $row.Message = 'Deleted'
            Write-AZRLog -Message "Deleted profile $Sid on $ComputerName"
        }
        catch { $row.Message = $_.Exception.Message }
    }
    [pscustomobject]$row
}

function Uninstall-AZRSoftware {
    <# Silently uninstalls an MSI product by product code (msiexec /x). Non-MSI software is not supported. #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$ProductCode,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $ProductCode = Assert-AZRProductCode -ProductCode $ProductCode
    if ($PSCmdlet.ShouldProcess("$ComputerName $ProductCode", 'msiexec /x')) {
        Invoke-AZRRemoteTemplate -ComputerName $ComputerName -Template MsiUninstall -Parameter @{ ProductCode = $ProductCode } -Credential $Credential -Label "Uninstall $ProductCode"
    }
}

function Show-AZRSystemInfo {
    <#
    .SYNOPSIS
        Opens the system information window: one tab per section, loaded when you click the tab, with row actions
        (start/stop service, end process, delete profile, uninstall MSI software).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $tabs = foreach ($sec in Get-AZRSystemInfoSection) {
        @{ Name = $sec; Loader = [scriptblock]::Create("Get-AZRSystemInfo -ComputerName '$ComputerName' -Section $sec") }
    }
    $actions = @(
        @{ Tab = 'Services'; Name = 'Start service'; NeedsSelection = $true; Risk = 'Change'; Script = [scriptblock]::Create("param(`$r) Set-AZRServiceState -ComputerName '$ComputerName' -Name `$r.Name -State Start -Confirm:`$false | Out-Null") }
        @{ Tab = 'Services'; Name = 'Stop service'; NeedsSelection = $true; Risk = 'Change'; Script = [scriptblock]::Create("param(`$r) Set-AZRServiceState -ComputerName '$ComputerName' -Name `$r.Name -State Stop -Confirm:`$false | Out-Null") }
        @{ Tab = 'Processes'; Name = 'End process'; NeedsSelection = $true; Risk = 'Destructive'; Script = [scriptblock]::Create("param(`$r) Stop-AZRRemoteProcess -ComputerName '$ComputerName' -ProcessId `$r.ProcessId -Confirm:`$false | Out-Null") }
        @{ Tab = 'Profiles'; Name = 'Delete profile'; NeedsSelection = $true; Risk = 'Destructive'; Script = [scriptblock]::Create("param(`$r) Remove-AZRUserProfile -ComputerName '$ComputerName' -Sid `$r.Sid -Confirm:`$false | Out-Null") }
        @{ Tab = 'Software'; Name = 'Uninstall (MSI)'; NeedsSelection = $true; Risk = 'Destructive'; Script = [scriptblock]::Create("param(`$r) Uninstall-AZRSoftware -ComputerName '$ComputerName' -ProductCode `$r.ProductCode -Confirm:`$false | Out-Null") }
    )
    Show-AZRWindow -Title "System information: $ComputerName" -Tab $tabs -Action $actions -Target @($ComputerName)
}
