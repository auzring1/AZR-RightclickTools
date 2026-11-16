BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
}
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
    $env:AZR_LOG_DIR = Join-Path $TestDrive 'logs'
    $env:AZR_SETTINGS_USER = Join-Path $TestDrive 'user.json'
    $env:AZR_SETTINGS_MACHINE = Join-Path $TestDrive 'machine.json'
    function global:Connect-MgGraph {}
    function global:Invoke-MgGraphRequest {}
    function global:Get-MgContext {}
}
AfterAll {
    foreach ($v in 'AZR_LOG_DIR', 'AZR_SETTINGS_USER', 'AZR_SETTINGS_MACHINE') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
    foreach ($f in 'Connect-MgGraph', 'Invoke-MgGraphRequest', 'Get-MgContext') { Remove-Item "function:global:$f" -ErrorAction SilentlyContinue }
}

Describe 'BitLocker detail (S1)' {
    InModuleScope AZR.RightClickTools {
        It 'maps method, protector and status codes' {
            ConvertTo-AZRBitLockerMethod -Value 7 | Should -Be 'XTS-AES 256'
            ConvertTo-AZRBitLockerMethod -Value 0 | Should -Be 'None'
            ConvertTo-AZRBitLockerProtectorType -Value 3 | Should -Be 'Recovery password'
            ConvertTo-AZRBitLockerProtectorType -Value 4 | Should -Be 'TPM + PIN'
            ConvertTo-AZRBitLockerStatus -Value 1 | Should -Be 'On'
        }
    }
    It 'reads volumes and protector types but never asks for a recovery password' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRWithCimSession { & $ScriptBlock ([pscustomobject]@{}) }
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ DriveLetter = 'C:' } }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRCimOnInstance {
            switch ($MethodName) {
                'GetEncryptionMethod' { [pscustomobject]@{ EncryptionMethod = 7 } }
                'GetConversionStatus' { [pscustomobject]@{ ConversionStatus = 1; EncryptionPercentage = 100 } }
                'GetProtectionStatus' { [pscustomobject]@{ ProtectionStatus = 1 } }
                'GetKeyProtectors' { [pscustomobject]@{ VolumeKeyProtectorID = @('{A}', '{B}') } }
                'GetKeyProtectorType' { [pscustomobject]@{ KeyProtectorType = $(if ($Arguments.VolumeKeyProtectorID -eq '{A}') { 1 } else { 3 }) } }
                default { throw "unexpected method $MethodName" }
            }
        }
        $r = Get-AZRBitLockerDetail -ComputerName PC01
        $r.Volume | Should -Be 'C:'
        $r.Protection | Should -Be 'On'
        $r.Method | Should -Be 'XTS-AES 256'
        $r.Protectors | Should -Be 'TPM, Recovery password'
        $r.HasRecoveryProtector | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-AZRCimOnInstance -Times 0 -ParameterFilter { $MethodName -like '*NumericalPassword*' }
    }
}

Describe 'BitLocker recovery keys (S2)' {
    BeforeAll {
        $script:secretText = '123456-234567-345678-456789-567890-678901-789012-890123'
        Mock -ModuleName AZR.RightClickTools Write-AZRLog { $script:logged += $Message } 
        Mock -ModuleName AZR.RightClickTools Write-AZRAudit { $script:audited += ("$Action|$Risk|$Outcome|$Reason|" + ($Detail | ConvertTo-Json -Depth 5 -Compress)) }
    }
    BeforeEach { $script:logged = ''; $script:audited = '' }

    It 'reads keys from Active Directory as SecureStrings' {
        Mock -ModuleName AZR.RightClickTools Test-AZRAdAvailable { $true }
        Mock -ModuleName AZR.RightClickTools Get-AZRAdComputer { [pscustomobject]@{ DistinguishedName = 'CN=PC01,OU=Laptops,DC=corp,DC=example' } }
        Mock -ModuleName AZR.RightClickTools Get-AZRAdRecoveryObject {
            $o = [pscustomobject]@{ Name = '2026-01-01{guid}'; whenCreated = [datetime]'2026-01-01' }
            $o | Add-Member -NotePropertyName 'msFVE-RecoveryPassword' -NotePropertyValue $script:secretText
            $o | Add-Member -NotePropertyName 'msFVE-RecoveryGuid' -NotePropertyValue ([guid]'11111111-2222-3333-4444-555555555555').ToByteArray()
            $o
        }
        $k = @(Get-AZRBitLockerRecoveryKey -ComputerName PC01 -Source AD)
        $k.Count | Should -Be 1
        $k[0].Source | Should -Be 'Active Directory'
        $k[0].KeyId | Should -Be '11111111-2222-3333-4444-555555555555'
        $k[0].RecoveryPassword | Should -BeOfType [securestring]
        Should -Invoke -ModuleName AZR.RightClickTools Get-AZRAdRecoveryObject -ParameterFilter { $IncludePassword }
        ($k | Out-String) | Should -Not -Match '123456-234567'
        ($k | ConvertTo-Json -Depth 3 -WarningAction SilentlyContinue) | Should -Not -Match '123456-234567'
    }
    It 'reads keys from Entra ID through Graph with validated ids' {
        Mock -ModuleName AZR.RightClickTools Test-AZRAdAvailable { $false }
        Mock -ModuleName AZR.RightClickTools Connect-AZRGraph { }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRGraph {
            if ($Uri -like '/v1.0/devices*') { @{ id = 'o1'; deviceId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } }
            elseif ($Uri -like '*recoveryKeys`?*') { @{ id = '99999999-8888-7777-6666-555555555555'; volumeType = 'operatingSystemVolume'; createdDateTime = '2026-02-02T10:00:00Z' }; @{ id = 'not-a-guid; DROP' } }
            elseif ($Uri -like '*recoveryKeys/99999999*') { @{ key = $script:secretText } }
        }
        $k = @(Get-AZRBitLockerRecoveryKey -ComputerName PC01.corp.example -Source Graph)
        $k.Count | Should -Be 1
        $k[0].Source | Should -Be 'Entra ID'
        $k[0].Volume | Should -Be 'operatingSystemVolume'
        $k[0].RecoveryPassword | Should -BeOfType [securestring]
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-AZRGraph -ParameterFilter { $Uri -like "*displayName eq 'PC01'*" }
    }
    It 'explains what is missing when no source works' {
        Mock -ModuleName AZR.RightClickTools Test-AZRAdAvailable { $false }
        { Get-AZRBitLockerRecoveryKey -ComputerName PC01 -Source AD } | Should -Throw '*RSAT*'
    }
    It 'rejects an unsafe computer name' {
        { Get-AZRBitLockerRecoveryKey -ComputerName "PC01' -or 1" } | Should -Throw '*Invalid computer name*'
    }
    It 'shows keys only in the secret window and keeps them out of the log and audit' {
        Mock -ModuleName AZR.RightClickTools Get-AZRBitLockerRecoveryKey {
            [pscustomobject]@{ ComputerName = 'PC01'; Source = 'Active Directory'; KeyId = 'k1'; Volume = $null; Created = [datetime]'2026-01-01'; RecoveryPassword = (ConvertTo-SecureString $script:secretText -AsPlainText -Force) }
        }
        $script:shown = $null
        Mock -ModuleName AZR.RightClickTools Show-AZRSecretWindow { $script:shown = $Item }
        Show-AZRBitLockerRecoveryKey -ComputerName PC01 -Reason 'INC9 user forgot PIN'
        $script:shown.Count | Should -Be 1
        $script:shown[0].Value | Should -BeOfType [securestring]
        $script:logged | Should -Not -Match '123456-234567'
        $script:audited | Should -Not -Match '123456-234567'
        $script:audited | Should -Match 'INC9 user forgot PIN'
        $script:audited | Should -Match '\|Secret\|'
        $script:audited | Should -Match 'keyCount'
    }
}

Describe 'LAPS (S3)' {
    BeforeAll {
        $script:pw = 'Xy9!secretLapsPassword'
        Mock -ModuleName AZR.RightClickTools Write-AZRLog { $script:logged += $Message }
        Mock -ModuleName AZR.RightClickTools Write-AZRAudit { $script:audited += ("$Action|$Risk|$Outcome|$Reason|" + ($Detail | ConvertTo-Json -Depth 5 -Compress)) }
    }
    BeforeEach { $script:logged = ''; $script:audited = '' }

    It 'reports Windows LAPS status without any password' {
        Mock -ModuleName AZR.RightClickTools Test-AZRWindowsLapsAvailable { $true }
        Mock -ModuleName AZR.RightClickTools Get-AZRWindowsLapsRecord { [pscustomobject]@{ Account = 'Administrator'; PasswordUpdateTime = (Get-Date).AddDays(-3); ExpirationTimestamp = (Get-Date).AddDays(-1); Password = (ConvertTo-SecureString $script:pw -AsPlainText -Force) } }
        $s = Get-AZRLapsStatus -ComputerName PC01
        $s.Flavor | Should -Be 'Windows LAPS'
        $s.Account | Should -Be 'Administrator'
        $s.Expired | Should -BeTrue
        ($s | Out-String) | Should -Not -Match 'secretLaps'
        $s.PSObject.Properties.Name | Should -Not -Contain 'Password'
    }
    It 'falls back to legacy LAPS expiry attribute (password attribute is not requested)' {
        Mock -ModuleName AZR.RightClickTools Test-AZRWindowsLapsAvailable { $false }
        Mock -ModuleName AZR.RightClickTools Test-AZRAdAvailable { $true }
        Mock -ModuleName AZR.RightClickTools Get-AZRAdComputer { $c = [pscustomobject]@{}; $c | Add-Member -NotePropertyName 'ms-Mcs-AdmPwdExpirationTime' -NotePropertyValue ((Get-Date).AddDays(10).ToFileTime()); $c }
        $s = Get-AZRLapsStatus -ComputerName PC01
        $s.Flavor | Should -Be 'Legacy LAPS'
        $s.Expired | Should -BeFalse
        Should -Invoke -ModuleName AZR.RightClickTools Get-AZRAdComputer -ParameterFilter { $Property -notcontains 'ms-Mcs-AdmPwd' }
    }
    It 'returns the Windows LAPS password as a SecureString' {
        Mock -ModuleName AZR.RightClickTools Test-AZRWindowsLapsAvailable { $true }
        Mock -ModuleName AZR.RightClickTools Get-AZRWindowsLapsRecord { [pscustomobject]@{ Account = 'Administrator'; PasswordUpdateTime = Get-Date; ExpirationTimestamp = (Get-Date).AddDays(30); DecryptionStatus = 'Success'; Password = (ConvertTo-SecureString $script:pw -AsPlainText -Force) } }
        $r = @(Get-AZRLapsPassword -ComputerName PC01)
        $r[0].Source | Should -Be 'Windows LAPS (AD)'
        $r[0].Password | Should -BeOfType [securestring]
    }
    It 'reports a decryption failure instead of showing nothing' {
        Mock -ModuleName AZR.RightClickTools Test-AZRWindowsLapsAvailable { $true }
        Mock -ModuleName AZR.RightClickTools Test-AZRAdAvailable { $false }
        Mock -ModuleName AZR.RightClickTools Get-AZRWindowsLapsRecord { [pscustomobject]@{ Account = 'Administrator'; DecryptionStatus = 'Unauthorized'; Password = (New-Object securestring) } }
        { Get-AZRLapsPassword -ComputerName PC01 } | Should -Throw '*decryption*'
    }
    It 'decodes Entra LAPS credentials into SecureStrings' {
        Mock -ModuleName AZR.RightClickTools Test-AZRWindowsLapsAvailable { $false }
        Mock -ModuleName AZR.RightClickTools Test-AZRAdAvailable { $false }
        Mock -ModuleName AZR.RightClickTools Connect-AZRGraph { }
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:pw))
        Mock -ModuleName AZR.RightClickTools Invoke-AZRGraph {
            if ($Uri -like '/v1.0/devices*') { @{ deviceId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } }
            else { @{ credentials = @(@{ accountName = 'localadmin'; passwordBase64 = $b64; backupDateTime = '2026-03-01T00:00:00Z' }) } }
        }
        $r = @(Get-AZRLapsPassword -ComputerName PC01 -Source Graph)
        $r[0].Source | Should -Be 'Entra ID LAPS'
        $r[0].Account | Should -Be 'localadmin'
        [System.Net.NetworkCredential]::new('', $r[0].Password).Password | Should -Be $script:pw
    }
    It 'keeps the password out of log and audit when shown' {
        Mock -ModuleName AZR.RightClickTools Get-AZRLapsPassword { [pscustomobject]@{ ComputerName = 'PC01'; Source = 'Windows LAPS (AD)'; Account = 'Administrator'; Updated = $null; Expires = (Get-Date).AddDays(5); Password = (ConvertTo-SecureString $script:pw -AsPlainText -Force) } }
        Mock -ModuleName AZR.RightClickTools Show-AZRSecretWindow { }
        Show-AZRLapsPassword -ComputerName PC01 -Reason 'INC77 local login needed'
        $script:logged | Should -Not -Match 'secretLaps'
        $script:audited | Should -Not -Match 'secretLaps'
        $script:audited | Should -Match 'INC77'
    }
    It 'rotates by setting expiry through the Windows LAPS cmdlet' {
        Mock -ModuleName AZR.RightClickTools Get-AZRLapsStatus { [pscustomobject]@{ Flavor = 'Windows LAPS'; Message = '' } }
        Mock -ModuleName AZR.RightClickTools Set-AZRWindowsLapsExpiration { }
        (Set-AZRLapsExpiration -ComputerName PC01 -Confirm:$false).Success | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Set-AZRWindowsLapsExpiration -Times 1
        Mock -ModuleName AZR.RightClickTools Get-AZRLapsStatus { [pscustomobject]@{ Flavor = 'None'; Message = 'nothing' } }
        (Set-AZRLapsExpiration -ComputerName PC01 -Confirm:$false).Success | Should -BeFalse
    }
}

Describe 'Remote Windows Security (S4)' {
    BeforeAll {
        Mock -ModuleName AZR.RightClickTools Write-AZRLog {}
        Mock -ModuleName AZR.RightClickTools Invoke-AZRWithCimSession { & $ScriptBlock ([pscustomobject]@{}) }
    }
    It 'maps firewall and Device Guard codes' {
        InModuleScope AZR.RightClickTools {
            ConvertTo-AZRFirewallAction -Value 4 | Should -Be 'Block'
            ConvertTo-AZRFirewallEnabled -Value 1 | Should -Be 'True'
            ConvertTo-AZRDeviceGuardService -Value 2 | Should -BeLike 'Memory integrity*'
        }
    }
    It 'summarises Defender state' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim {
            [pscustomobject]@{ AMServiceEnabled = $true; AntivirusEnabled = $true; RealTimeProtectionEnabled = $false; BehaviorMonitorEnabled = $true; NISEnabled = $true; IsTamperProtected = $true; AMProductVersion = '4.18'; AntivirusSignatureVersion = '1.2.3'; AntivirusSignatureLastUpdated = (Get-Date); QuickScanAge = 1; FullScanAge = 9 }
        }
        $d = Get-AZRWindowsSecurity -ComputerName PC01 -Section Defender
        $d.RealTimeProtection | Should -BeFalse
        $d.TamperProtected | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Get-AZRCim -ParameterFilter { $Namespace -eq 'root\Microsoft\Windows\Defender' -and $ClassName -eq 'MSFT_MpComputerStatus' }
    }
    It 'lists Defender exclusions per type' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ ExclusionPath = @('C:\Tools'); ExclusionExtension = @('.vhdx'); ExclusionProcess = $null; ExclusionIpAddress = $null } }
        $e = @(Get-AZRWindowsSecurity -ComputerName PC01 -Section Exclusions)
        $e.Count | Should -Be 2
        ($e | Where-Object Type -eq 'Path').Value | Should -Be 'C:\Tools'
    }
    It 'shows firewall profiles and caps rules' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim {
            if ($ClassName -eq 'MSFT_NetFirewallProfile') { [pscustomobject]@{ Name = 'Domain'; Enabled = 1; DefaultInboundAction = 4; DefaultOutboundAction = 2 } }
            else { 1..50 | ForEach-Object { [pscustomobject]@{ DisplayName = "Rule$_"; Enabled = 1; Direction = 1; Action = 2; DisplayGroup = 'G' } } }
        }
        $p = Get-AZRWindowsSecurity -ComputerName PC01 -Section Firewall
        $p.DefaultInbound | Should -Be 'Block'
        @(Get-AZRWindowsSecurity -ComputerName PC01 -Section FirewallRules -MaxRules 10).Count | Should -Be 10
    }
    It 'reads Secure Boot and firmware type from the registry without WinRM' {
        Mock -ModuleName AZR.RightClickTools Get-AZRRegDword { if ($ValueName -eq 'UEFISecureBootEnabled') { 1 } else { 2 } }
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ IsEnabled_InitialValue = $true; SpecVersion = '2.0' } }
        $b = Get-AZRWindowsSecurity -ComputerName PC01 -Section Boot
        $b.Firmware | Should -Be 'UEFI'
        $b.SecureBoot | Should -Be 'On'
        $b.TpmPresent | Should -BeTrue
    }
    It 'describes Device Guard / VBS' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ VirtualizationBasedSecurityStatus = 2; SecurityServicesConfigured = @(1, 2); SecurityServicesRunning = @(2) } }
        $g = Get-AZRWindowsSecurity -ComputerName PC01 -Section DeviceGuard
        $g.VirtualizationBasedSecurity | Should -Be 'Running'
        $g.ServicesRunning | Should -BeLike 'Memory integrity*'
    }
}

Describe 'Compliance quick views (H1, H2)' {
    It 'classifies BitLocker compliance' {
        Get-AZRBitLockerComplianceStatus -Reachable $false -OsProtected $false -HasRecoveryProtector $false -AdKeyCount $null | Should -Be 'Unreachable'
        Get-AZRBitLockerComplianceStatus -Reachable $true -OsProtected $false -HasRecoveryProtector $false -AdKeyCount 0 | Should -Be 'Not protected'
        Get-AZRBitLockerComplianceStatus -Reachable $true -OsProtected $true -HasRecoveryProtector $false -AdKeyCount 1 | Should -Be 'No recovery protector'
        Get-AZRBitLockerComplianceStatus -Reachable $true -OsProtected $true -HasRecoveryProtector $true -AdKeyCount 0 | Should -Be 'Encrypted, key not in AD'
        Get-AZRBitLockerComplianceStatus -Reachable $true -OsProtected $true -HasRecoveryProtector $true -AdKeyCount $null | Should -Be 'Compliant'
        Get-AZRBitLockerComplianceStatus -Reachable $true -OsProtected $true -HasRecoveryProtector $true -AdKeyCount 2 | Should -Be 'Compliant'
    }
    It 'combines live state with AD key presence and never reads key values' {
        Mock -ModuleName AZR.RightClickTools Get-AZRBitLockerDetail { [pscustomobject]@{ Volume = 'C:'; Protection = 'On'; HasRecoveryProtector = $true; Protectors = 'TPM, Recovery password' } }
        Mock -ModuleName AZR.RightClickTools Test-AZRAdAvailable { $true }
        Mock -ModuleName AZR.RightClickTools Get-AZRAdComputer { [pscustomobject]@{ DistinguishedName = 'CN=PC01,DC=x' } }
        Mock -ModuleName AZR.RightClickTools Get-AZRAdRecoveryObject { }
        $r = Get-AZRBitLockerCompliance -ComputerName PC01
        $r.Status | Should -Be 'Encrypted, key not in AD'
        Should -Invoke -ModuleName AZR.RightClickTools Get-AZRAdRecoveryObject -ParameterFilter { -not $IncludePassword }
    }
    It 'reports an unreachable device' {
        Mock -ModuleName AZR.RightClickTools Get-AZRBitLockerDetail { throw 'RPC unavailable' }
        (Get-AZRBitLockerCompliance -ComputerName PC01).Status | Should -Be 'Unreachable'
    }
}
