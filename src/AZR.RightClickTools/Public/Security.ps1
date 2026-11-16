# Security tools (roadmap S1 to S5 and the H1/H2 quick views).
# SECRET RULES: recovery keys and passwords are returned only as SecureString, are shown only by Show-AZRSecretWindow,
# and are never passed to Write-AZRLog / Write-AZRAudit, exported, or put on a command line.

#region S1 BitLocker detail and TPM
function ConvertTo-AZRBitLockerMethod {
    param($Value)
    switch ([int]$Value) { 0 { 'None' } 1 { 'AES 128 with diffuser' } 2 { 'AES 256 with diffuser' } 3 { 'AES 128' } 4 { 'AES 256' } 5 { 'Hardware encryption' } 6 { 'XTS-AES 128' } 7 { 'XTS-AES 256' } default { "Unknown ($Value)" } }
}

function ConvertTo-AZRBitLockerProtectorType {
    param($Value)
    switch ([int]$Value) { 1 { 'TPM' } 2 { 'External key' } 3 { 'Recovery password' } 4 { 'TPM + PIN' } 5 { 'TPM + startup key' } 6 { 'TPM + PIN + startup key' } 7 { 'Public key' } 8 { 'Passphrase' } 9 { 'TPM certificate' } 10 { 'CNG' } default { 'Unknown' } }
}

function ConvertTo-AZRBitLockerStatus {
    param($Value)
    switch ([int]$Value) { 0 { 'Off' } 1 { 'On' } 2 { 'Unknown' } default { "Unknown ($Value)" } }
}

function Get-AZRBitLockerDetail {
    <#
    .SYNOPSIS
        Per-volume BitLocker detail: protection state, conversion state and percent, encryption method and the
        protector types. Recovery passwords are NOT read here.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName, [pscredential]$Credential)
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($s)
            $ns = 'root\cimv2\Security\MicrosoftVolumeEncryption'
            foreach ($v in Get-AZRCim -Session $s -Namespace $ns -ClassName Win32_EncryptableVolume) {
                $method = (Invoke-AZRCimOnInstance -Session $s -InputObject $v -MethodName GetEncryptionMethod).EncryptionMethod
                $conv = Invoke-AZRCimOnInstance -Session $s -InputObject $v -MethodName GetConversionStatus
                $prot = Invoke-AZRCimOnInstance -Session $s -InputObject $v -MethodName GetProtectionStatus
                $ids = @((Invoke-AZRCimOnInstance -Session $s -InputObject $v -MethodName GetKeyProtectors -Arguments @{ KeyProtectorType = [uint32]0 }).VolumeKeyProtectorID)
                $types = foreach ($id in $ids) {
                    ConvertTo-AZRBitLockerProtectorType -Value (Invoke-AZRCimOnInstance -Session $s -InputObject $v -MethodName GetKeyProtectorType -Arguments @{ VolumeKeyProtectorID = $id }).KeyProtectorType
                }
                [pscustomobject]@{
                    ComputerName      = $ComputerName
                    Volume            = $v.DriveLetter
                    Protection        = ConvertTo-AZRBitLockerStatus -Value $prot.ProtectionStatus
                    ConversionStatus  = switch ([int]$conv.ConversionStatus) { 0 { 'Fully decrypted' } 1 { 'Fully encrypted' } 2 { 'Encryption in progress' } 3 { 'Decryption in progress' } 4 { 'Encryption paused' } 5 { 'Decryption paused' } default { [string]$conv.ConversionStatus } }
                    PercentEncrypted  = $conv.EncryptionPercentage
                    Method            = ConvertTo-AZRBitLockerMethod -Value $method
                    Protectors        = (@($types) -join ', ')
                    HasRecoveryProtector = (@($types) -contains 'Recovery password')
                }
            }
        }
    }
}

function Get-AZRTpmInfo {
    <# TPM presence and state from Win32_Tpm (initial values as reported by the provider). #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName, [pscredential]$Credential)
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($s)
            $t = Get-AZRCim -Session $s -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm | Select-Object -First 1
            if (-not $t) { return [pscustomobject]@{ ComputerName = $ComputerName; Present = $false; Enabled = $null; Activated = $null; Owned = $null; SpecVersion = $null; ManufacturerVersion = $null } }
            [pscustomobject]@{ ComputerName = $ComputerName; Present = $true; Enabled = $t.IsEnabled_InitialValue; Activated = $t.IsActivated_InitialValue; Owned = $t.IsOwned_InitialValue; SpecVersion = $t.SpecVersion; ManufacturerVersion = $t.ManufacturerVersion }
        }
    }
}
#endregion

#region S2 BitLocker recovery keys
function Get-AZRBitLockerRecoveryKey {
    <#
    .SYNOPSIS
        Looks up BitLocker recovery passwords for a computer in Active Directory and/or Entra ID (Microsoft Graph).
    .DESCRIPTION
        SECRET. Returns objects whose RecoveryPassword is a SecureString. Callers must show it only with
        Show-AZRSecretWindow and must not log or export it. The dispatcher asks for a reason and writes an audit entry
        (who, which device, when, why, how many keys) without the key.
        Sources: AD (msFVE-RecoveryInformation child objects, needs the RSAT ActiveDirectory module and read rights on
        the recovery information) and Graph (needs BitLockerKey.Read.All). ConfigMgr/MBAM key sources are not implemented yet.
    .PARAMETER Source
        Auto tries every source that is available; AD or Graph restrict it to one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [ValidateSet('Auto', 'AD', 'Graph')][string]$Source = 'Auto',
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $found = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]

    if ($Source -in 'Auto', 'AD') {
        if (Test-AZRAdAvailable) {
            try {
                $comp = Get-AZRAdComputer -ComputerName $ComputerName -Credential $Credential
                foreach ($o in Get-AZRAdRecoveryObject -ComputerDn $comp.DistinguishedName -IncludePassword -Credential $Credential) {
                    $pw = $o.'msFVE-RecoveryPassword'
                    if (-not $pw) { $problems.Add("AD: no read access to the password of $($o.Name)"); continue }
                    $guid = try { ([guid][byte[]]$o.'msFVE-RecoveryGuid').ToString() } catch { $null }
                    $found.Add([pscustomobject]@{
                            ComputerName     = $ComputerName
                            Source           = 'Active Directory'
                            KeyId            = $guid
                            Volume           = $null
                            Created          = $o.whenCreated
                            RecoveryPassword = (ConvertTo-AZRSecureString -Text ([string]$pw))
                        })
                }
            }
            catch { $problems.Add("AD: $($_.Exception.Message)") }
        }
        elseif ($Source -eq 'AD') { $problems.Add('AD: the ActiveDirectory PowerShell module (RSAT) is not installed.') }
    }

    if ($Source -in 'Auto', 'Graph') {
        if (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue) {
            try {
                $null = Connect-AZRGraph -Feature BitLockerKeys
                $devs = @(Invoke-AZRGraph -Uri ("/v1.0/devices?`$filter=displayName eq '{0}'&`$select=id,deviceId,displayName" -f $ComputerName.Split('.')[0]))
                foreach ($d in $devs) {
                    $did = [string]$d['deviceId']
                    if ($did -notmatch '^[0-9a-fA-F\-]{36}$') { continue }
                    foreach ($k in @(Invoke-AZRGraph -Uri "/v1.0/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$did'")) {
                        $kid = [string]$k['id']
                        if ($kid -notmatch '^[0-9a-fA-F\-]{36}$') { continue }
                        $full = Invoke-AZRGraph -Uri "/v1.0/informationProtection/bitlocker/recoveryKeys/${kid}?`$select=key" | Select-Object -First 1
                        if (-not $full -or -not $full['key']) { continue }
                        $found.Add([pscustomobject]@{
                                ComputerName     = $ComputerName
                                Source           = 'Entra ID'
                                KeyId            = $kid
                                Volume           = [string]$k['volumeType']
                                Created          = $k['createdDateTime']
                                RecoveryPassword = (ConvertTo-AZRSecureString -Text ([string]$full['key']))
                            })
                    }
                }
            }
            catch { $problems.Add("Graph: $($_.Exception.Message)") }
        }
        elseif ($Source -eq 'Graph') { $problems.Add('Graph: Microsoft.Graph.Authentication is not installed (Install-Module Microsoft.Graph.Authentication).') }
    }

    foreach ($p in $problems) { Write-AZRLog -Level Warn -Message "BitLocker key lookup for ${ComputerName}: $p" }
    if (-not $found.Count -and $problems.Count) { throw ('No key found. ' + ($problems -join ' ')) }
    $found.ToArray()
}

function ConvertTo-AZRSecureString {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Value arrives as text from AD/Graph and is held as SecureString from here on.')]
    param([Parameter(Mandatory)][string]$Text)
    ConvertTo-SecureString -String $Text -AsPlainText -Force
}

function Show-AZRBitLockerRecoveryKey {
    <#
    .SYNOPSIS
        Fetches recovery keys for a device and shows them in the secret window. Writes an audit entry (never the key).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [string]$Reason, [ValidateSet('Auto', 'AD', 'Graph')][string]$Source = 'Auto')
    $keys = @(Get-AZRBitLockerRecoveryKey -ComputerName $ComputerName -Source $Source)
    Write-AZRAudit -Action 'BitLockerRecoveryKey' -Target $ComputerName -Risk Secret -Outcome Success -Reason $Reason -Detail @{ keyCount = $keys.Count; sources = (@($keys.Source | Select-Object -Unique) -join ',') }
    if (-not $keys.Count) { Show-AZRMessage -Message "No BitLocker recovery key found for $ComputerName." -Icon Warning; return }
    $items = foreach ($k in $keys) {
        $label = '{0}  |  key ID {1}  |  {2}' -f $k.Source, $k.KeyId, $(if ($k.Created) { ([datetime]$k.Created).ToString('yyyy-MM-dd HH:mm') } else { 'date unknown' })
        if ($k.Volume) { $label += "  |  $($k.Volume)" }
        @{ Label = $label; Value = $k.RecoveryPassword }
    }
    Show-AZRSecretWindow -Title "BitLocker recovery keys: $ComputerName" -Item @($items)
}
#endregion

#region S3 LAPS
function Get-AZRLapsStatus {
    <#
    .SYNOPSIS
        LAPS state without revealing passwords: Windows LAPS or legacy LAPS, managed account, last change and expiry.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName, [pscredential]$Credential)
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        $row = [ordered]@{ ComputerName = $ComputerName; Flavor = 'None'; Account = $null; PasswordUpdated = $null; Expires = $null; Expired = $null; Success = $true; Message = '' }
        try {
            $rec = $null
            if (Test-AZRWindowsLapsAvailable) {
                try { $rec = Get-AZRWindowsLapsRecord -ComputerName $ComputerName -Credential $Credential } catch { $rec = $null }
            }
            if ($rec -and $rec.PasswordUpdateTime -and $rec.PasswordUpdateTime -gt [datetime]'1700-01-01') {
                $row.Flavor = 'Windows LAPS'; $row.Account = $rec.Account; $row.PasswordUpdated = $rec.PasswordUpdateTime; $row.Expires = $rec.ExpirationTimestamp
            }
            elseif (Test-AZRAdAvailable) {
                $c = Get-AZRAdComputer -ComputerName $ComputerName -Property 'ms-Mcs-AdmPwdExpirationTime' -Credential $Credential
                $ft = $c.'ms-Mcs-AdmPwdExpirationTime'
                if ($ft) { $row.Flavor = 'Legacy LAPS'; $row.Expires = [datetime]::FromFileTime([int64]$ft) }
            }
            else { $row.Message = 'No directory module available (install RSAT ActiveDirectory or the Windows LAPS module).' }
            if ($row.Expires) { $row.Expired = ([datetime]$row.Expires) -lt (Get-Date) }
        }
        catch { $row.Success = $false; $row.Message = $_.Exception.Message }
        [pscustomobject]$row
    }
}

function Get-AZRLapsPassword {
    <#
    .SYNOPSIS
        SECRET. Reads the local administrator password from Windows LAPS (AD), legacy LAPS (AD) or Entra ID (Graph).
        Passwords are returned as SecureString; show them only with Show-AZRSecretWindow.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [ValidateSet('Auto', 'WindowsLaps', 'LegacyLaps', 'Graph')][string]$Source = 'Auto',
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $found = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]

    if (($Source -in 'Auto', 'WindowsLaps') -and (Test-AZRWindowsLapsAvailable)) {
        try {
            $r = Get-AZRWindowsLapsRecord -ComputerName $ComputerName -Credential $Credential
            if ($r -and $r.Password -is [securestring]) {
                if ($r.DecryptionStatus -and [string]$r.DecryptionStatus -ne 'Success' -and [string]$r.DecryptionStatus -ne 'NotApplicable') { $problems.Add("Windows LAPS decryption: $($r.DecryptionStatus)") }
                else { $found.Add([pscustomobject]@{ ComputerName = $ComputerName; Source = 'Windows LAPS (AD)'; Account = $r.Account; Updated = $r.PasswordUpdateTime; Expires = $r.ExpirationTimestamp; Password = $r.Password }) }
            }
        }
        catch { $problems.Add("Windows LAPS: $($_.Exception.Message)") }
    }
    if (($Source -in 'Auto', 'LegacyLaps') -and -not $found.Count -and (Test-AZRAdAvailable)) {
        try {
            $c = Get-AZRAdComputer -ComputerName $ComputerName -Property 'ms-Mcs-AdmPwd', 'ms-Mcs-AdmPwdExpirationTime' -Credential $Credential
            $pw = $c.'ms-Mcs-AdmPwd'
            if ($pw) {
                $exp = if ($c.'ms-Mcs-AdmPwdExpirationTime') { [datetime]::FromFileTime([int64]$c.'ms-Mcs-AdmPwdExpirationTime') } else { $null }
                $found.Add([pscustomobject]@{ ComputerName = $ComputerName; Source = 'Legacy LAPS (AD)'; Account = 'Built-in administrator'; Updated = $null; Expires = $exp; Password = (ConvertTo-AZRSecureString -Text ([string]$pw)) })
            }
        }
        catch { $problems.Add("Legacy LAPS: $($_.Exception.Message)") }
    }
    if (($Source -in 'Auto', 'Graph') -and -not $found.Count -and (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
        try {
            $null = Connect-AZRGraph -Feature Laps
            foreach ($d in @(Invoke-AZRGraph -Uri ("/v1.0/devices?`$filter=displayName eq '{0}'&`$select=id,deviceId" -f $ComputerName.Split('.')[0]))) {
                $did = [string]$d['deviceId']
                if ($did -notmatch '^[0-9a-fA-F\-]{36}$') { continue }
                $cred = Invoke-AZRGraph -Uri "/v1.0/directory/deviceLocalCredentials/${did}?`$select=credentials" | Select-Object -First 1
                foreach ($c in @($cred['credentials'])) {
                    if (-not $c['passwordBase64']) { continue }
                    $plain = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$c['passwordBase64']))
                    $found.Add([pscustomobject]@{ ComputerName = $ComputerName; Source = 'Entra ID LAPS'; Account = $c['accountName']; Updated = $c['backupDateTime']; Expires = $null; Password = (ConvertTo-AZRSecureString -Text $plain) })
                }
            }
        }
        catch { $problems.Add("Graph LAPS: $($_.Exception.Message)") }
    }
    foreach ($p in $problems) { Write-AZRLog -Level Warn -Message "LAPS lookup for ${ComputerName}: $p" }
    if (-not $found.Count -and $problems.Count) { throw ('No LAPS password retrieved. ' + ($problems -join ' ')) }
    $found.ToArray()
}

function Show-AZRLapsPassword {
    <# Fetches the LAPS password(s) and shows them in the secret window. Writes an audit entry (never the password). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [string]$Reason, [ValidateSet('Auto', 'WindowsLaps', 'LegacyLaps', 'Graph')][string]$Source = 'Auto')
    $records = @(Get-AZRLapsPassword -ComputerName $ComputerName -Source $Source)
    Write-AZRAudit -Action 'LapsPassword' -Target $ComputerName -Risk Secret -Outcome Success -Reason $Reason -Detail @{ passwordCount = $records.Count; sources = (@($records.Source | Select-Object -Unique) -join ',') }
    if (-not $records.Count) { Show-AZRMessage -Message "No LAPS password found for $ComputerName." -Icon Warning; return }
    $items = foreach ($p in $records) {
        $label = '{0}  |  account {1}' -f $p.Source, $p.Account
        if ($p.Expires) { $label += '  |  expires ' + ([datetime]$p.Expires).ToString('yyyy-MM-dd HH:mm') }
        @{ Label = $label; Value = $p.Password }
    }
    Show-AZRSecretWindow -Title "LAPS password: $ComputerName" -Item @($items)
}

function Set-AZRLapsExpiration {
    <#
    .SYNOPSIS
        Sets the LAPS password expiry (default: now) so the next policy run rotates the password.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [datetime]$When = (Get-Date),
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $row = [ordered]@{ ComputerName = $ComputerName; Action = 'Set LAPS expiration'; Success = $false; Message = '' }
    if ($PSCmdlet.ShouldProcess($ComputerName, "Set LAPS password expiration to $When")) {
        try {
            $status = Get-AZRLapsStatus -ComputerName $ComputerName -Credential $Credential
            switch ($status.Flavor) {
                'Windows LAPS' { Set-AZRWindowsLapsExpiration -ComputerName $ComputerName -When $When -Credential $Credential -Confirm:$false }
                'Legacy LAPS' {
                    $p = Get-AZRAdParameter -Credential $Credential
                    $c = Get-AZRAdComputer -ComputerName $ComputerName -Credential $Credential
                    Set-ADComputer @p -Identity $c.DistinguishedName -Replace @{ 'ms-Mcs-AdmPwdExpirationTime' = $When.ToFileTime() }
                }
                default { throw "No LAPS configuration found for $ComputerName. $($status.Message)" }
            }
            $row.Success = $true; $row.Message = "Expiration set ($($status.Flavor)); the client rotates the password at its next policy processing."
        }
        catch { $row.Message = $_.Exception.Message }
    }
    [pscustomobject]$row
}
#endregion

#region S4 Remote Windows Security
function Get-AZRWindowsSecuritySection { 'Summary', 'Defender', 'Exclusions', 'Firewall', 'FirewallRules', 'DeviceGuard', 'Boot', 'BitLocker' }

function ConvertTo-AZRFirewallAction { param($Value) switch ([int]$Value) { 0 { 'Not configured' } 2 { 'Allow' } 4 { 'Block' } default { [string]$Value } } }
function ConvertTo-AZRFirewallEnabled { param($Value) switch ([int]$Value) { 0 { 'False' } 1 { 'True' } 2 { 'Not configured' } default { [string]$Value } } }
function ConvertTo-AZRDeviceGuardService {
    param($Value)
    switch ([int]$Value) { 1 { 'Credential Guard' } 2 { 'Memory integrity (HVCI)' } 3 { 'System Guard Secure Launch' } 4 { 'SMM firmware measurement' } 5 { 'Kernel-mode hardware stack protection' } default { "Service $Value" } }
}

function Get-AZRWindowsSecurity {
    <#
    .SYNOPSIS
        Read-only security state of a remote computer (Defender, firewall, VBS/Device Guard, Secure Boot, TPM, BitLocker).
    .PARAMETER Section
        Summary, Defender, Exclusions, Firewall, FirewallRules, DeviceGuard, Boot or BitLocker.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName,
        [ValidateSet('Summary', 'Defender', 'Exclusions', 'Firewall', 'FirewallRules', 'DeviceGuard', 'Boot', 'BitLocker')][string]$Section = 'Summary',
        [ValidateRange(1, 5000)][int]$MaxRules = 1000,
        [pscredential]$Credential
    )
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        switch ($Section) {
            'BitLocker' { Get-AZRBitLockerDetail -ComputerName $ComputerName -Credential $Credential; return }
            'Summary' {
                $row = [ordered]@{ ComputerName = $ComputerName }
                foreach ($sec in 'Defender', 'Boot', 'DeviceGuard') {
                    try {
                        $d = @(Get-AZRWindowsSecurity -ComputerName $ComputerName -Section $sec -Credential $Credential) | Select-Object -First 1
                        foreach ($p in $d.PSObject.Properties) { if ($p.Name -ne 'ComputerName') { $row["$sec.$($p.Name)"] = $p.Value } }
                    }
                    catch { $row["$sec"] = "unavailable: $($_.Exception.Message)" }
                }
                try { $row['Firewall'] = (@(Get-AZRWindowsSecurity -ComputerName $ComputerName -Section Firewall -Credential $Credential) | ForEach-Object { '{0}={1}' -f $_.Profile, $_.Enabled }) -join '; ' } catch { $row['Firewall'] = 'unavailable' }
                try { $row['BitLocker'] = (@(Get-AZRBitLockerDetail -ComputerName $ComputerName -Credential $Credential) | ForEach-Object { '{0} {1}' -f $_.Volume, $_.Protection }) -join '; ' } catch { $row['BitLocker'] = 'unavailable' }
                [pscustomobject]$row
                return
            }
        }
        Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($s)
            switch ($Section) {
                'Defender' {
                    $d = Get-AZRCim -Session $s -Namespace 'root\Microsoft\Windows\Defender' -ClassName MSFT_MpComputerStatus | Select-Object -First 1
                    if ($d) {
                        [pscustomobject]@{
                            ComputerName = $ComputerName; ServiceEnabled = $d.AMServiceEnabled; AntivirusEnabled = $d.AntivirusEnabled; RealTimeProtection = $d.RealTimeProtectionEnabled
                            BehaviorMonitor = $d.BehaviorMonitorEnabled; NetworkInspection = $d.NISEnabled; TamperProtected = $d.IsTamperProtected
                            ProductVersion = $d.AMProductVersion; SignatureVersion = $d.AntivirusSignatureVersion; SignatureUpdated = $d.AntivirusSignatureLastUpdated
                            QuickScanAgeDays = $d.QuickScanAge; FullScanAgeDays = $d.FullScanAge
                        }
                    }
                }
                'Exclusions' {
                    $p = Get-AZRCim -Session $s -Namespace 'root\Microsoft\Windows\Defender' -ClassName MSFT_MpPreference | Select-Object -First 1
                    if ($p) {
                        foreach ($pair in @(@('Path', $p.ExclusionPath), @('Extension', $p.ExclusionExtension), @('Process', $p.ExclusionProcess), @('IP address', $p.ExclusionIpAddress))) {
                            foreach ($v in @($pair[1] | Where-Object { $_ })) { [pscustomobject]@{ ComputerName = $ComputerName; Type = $pair[0]; Value = $v } }
                        }
                    }
                }
                'Firewall' {
                    Get-AZRCim -Session $s -Namespace 'root\StandardCimv2' -ClassName MSFT_NetFirewallProfile | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; Profile = $_.Name; Enabled = ConvertTo-AZRFirewallEnabled -Value $_.Enabled; DefaultInbound = ConvertTo-AZRFirewallAction -Value $_.DefaultInboundAction; DefaultOutbound = ConvertTo-AZRFirewallAction -Value $_.DefaultOutboundAction }
                    }
                }
                'FirewallRules' {
                    Get-AZRCim -Session $s -Namespace 'root\StandardCimv2' -ClassName MSFT_NetFirewallRule | Select-Object -First $MaxRules | ForEach-Object {
                        [pscustomobject]@{ ComputerName = $ComputerName; Name = $_.DisplayName; Enabled = ConvertTo-AZRFirewallEnabled -Value $_.Enabled; Direction = $(if ([int]$_.Direction -eq 1) { 'Inbound' } else { 'Outbound' }); Action = ConvertTo-AZRFirewallAction -Value $_.Action; Group = $_.DisplayGroup }
                    }
                }
                'DeviceGuard' {
                    $g = Get-AZRCim -Session $s -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard | Select-Object -First 1
                    if ($g) {
                        [pscustomobject]@{
                            ComputerName = $ComputerName
                            VirtualizationBasedSecurity = switch ([int]$g.VirtualizationBasedSecurityStatus) { 0 { 'Off' } 1 { 'Enabled, not running' } 2 { 'Running' } default { [string]$g.VirtualizationBasedSecurityStatus } }
                            ServicesConfigured = (@($g.SecurityServicesConfigured) | ForEach-Object { ConvertTo-AZRDeviceGuardService -Value $_ }) -join ', '
                            ServicesRunning    = (@($g.SecurityServicesRunning) | ForEach-Object { ConvertTo-AZRDeviceGuardService -Value $_ }) -join ', '
                        }
                    }
                }
                'Boot' {
                    $sb = Get-AZRRegDword -Session $s -SubKey 'SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ValueName 'UEFISecureBootEnabled'
                    $fw = Get-AZRRegDword -Session $s -SubKey 'SYSTEM\CurrentControlSet\Control' -ValueName 'PEFirmwareType'
                    $tpm = try { Get-AZRCim -Session $s -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm | Select-Object -First 1 } catch { $null }
                    [pscustomobject]@{
                        ComputerName = $ComputerName
                        Firmware     = switch ($fw) { 1 { 'BIOS (legacy)' } 2 { 'UEFI' } default { 'Unknown' } }
                        SecureBoot   = switch ($sb) { 1 { 'On' } 0 { 'Off' } default { 'Unknown / not supported' } }
                        TpmPresent   = [bool]$tpm
                        TpmEnabled   = $tpm.IsEnabled_InitialValue
                        TpmSpec      = $tpm.SpecVersion
                    }
                }
            }
        }
    }
}

function Show-AZRWindowsSecurity {
    <# Read-only security window with one tab per section; tabs load when first opened. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $tabs = foreach ($sec in Get-AZRWindowsSecuritySection) {
        @{ Name = $sec; Loader = [scriptblock]::Create("Get-AZRWindowsSecurity -ComputerName '$ComputerName' -Section $sec") }
    }
    Show-AZRWindow -Title "Windows Security: $ComputerName" -Tab $tabs -Target @($ComputerName)
}
#endregion

#region H1 / H2 and compliance helpers
function Get-AZRBitLockerComplianceStatus {
    <#
    .SYNOPSIS
        Pure rule: classify one device from facts. Used by Get-AZRBitLockerCompliance and unit-tested.
    #>
    [CmdletBinding()]
    param([bool]$Reachable, [bool]$OsProtected, [bool]$HasRecoveryProtector, $AdKeyCount)
    if (-not $Reachable) { return 'Unreachable' }
    if (-not $OsProtected) { return 'Not protected' }
    if (-not $HasRecoveryProtector) { return 'No recovery protector' }
    if ($null -ne $AdKeyCount -and [int]$AdKeyCount -eq 0) { return 'Encrypted, key not in AD' }
    'Compliant'
}

function Get-AZRBitLockerCompliance {
    <#
    .SYNOPSIS
        Live BitLocker compliance for one device: is the OS volume protected, does it have a recovery protector, and (when the
        AD module is present) is a key escrowed in AD. Key values are never read.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName, [pscredential]$Credential)
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        $vols = $null
        try { $vols = @(Get-AZRBitLockerDetail -ComputerName $ComputerName -Credential $Credential) } catch { $vols = $null }
        if ($null -eq $vols) {
            return [pscustomobject]@{ ComputerName = $ComputerName; Status = Get-AZRBitLockerComplianceStatus -Reachable $false -OsProtected $false -HasRecoveryProtector $false -AdKeyCount $null; OsVolume = $null; Protectors = $null; AdKeys = $null }
        }
        $os = $vols | Where-Object { $_.Volume -eq $env:SystemDrive -or $_.Volume -eq 'C:' } | Select-Object -First 1
        if (-not $os) { $os = $vols | Select-Object -First 1 }
        $adKeys = $null
        if (Test-AZRAdAvailable) {
            try { $c = Get-AZRAdComputer -ComputerName $ComputerName -Credential $Credential; $adKeys = @(Get-AZRAdRecoveryObject -ComputerDn $c.DistinguishedName -Credential $Credential).Count } catch { $adKeys = $null }
        }
        [pscustomobject]@{
            ComputerName = $ComputerName
            Status       = Get-AZRBitLockerComplianceStatus -Reachable $true -OsProtected ([bool]($os -and $os.Protection -eq 'On')) -HasRecoveryProtector ([bool]($os -and $os.HasRecoveryProtector)) -AdKeyCount $adKeys
            OsVolume     = $os.Volume
            Protectors   = $os.Protectors
            AdKeys       = $adKeys
        }
    }
}
#endregion
