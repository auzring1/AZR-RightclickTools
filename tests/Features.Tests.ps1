BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
}

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    Import-Module (Join-Path $script:Root 'src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
    $env:AZR_LOG_DIR = Join-Path $TestDrive 'logs'
    $env:AZR_SETTINGS_USER = Join-Path $TestDrive 'user.json'
    $env:AZR_SETTINGS_MACHINE = Join-Path $TestDrive 'machine.json'
}
AfterAll { foreach ($v in 'AZR_LOG_DIR', 'AZR_SETTINGS_USER', 'AZR_SETTINGS_MACHINE') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue } }

Describe 'WQL builder' {
    InModuleScope AZR.RightClickTools {
        It 'builds quoted equality filters in a stable order' {
            New-AZRWql -Class SMS_R_System -Property Name, ResourceID -Equals @{ Name = 'PC01'; Client = 1 } | Should -Be "SELECT Name, ResourceID FROM SMS_R_System WHERE Client = 1 AND Name = 'PC01'"
        }
        It 'formats dates as DMTF in UTC' {
            ConvertTo-AZRDmtfDateTime -Date ([datetime]::new(2026, 1, 2, 3, 4, 5, [System.DateTimeKind]::Utc)) | Should -Be '20260102030405.000000+000'
            New-AZRWql -Class SMS_StatusMessage -GreaterOrEqual @{ Time = [datetime]::new(2026, 1, 2, 3, 4, 5, [System.DateTimeKind]::Utc) } | Should -Match "Time >= '20260102030405.000000\+000'"
        }
        It 'refuses injection through class, property or value' {
            { New-AZRWql -Class 'SMS_R_System; DROP' } | Should -Throw
            { New-AZRWql -Class SMS_R_System -Property 'Name FROM X --' } | Should -Throw
            { New-AZRWql -Class SMS_R_System -Equals @{ Name = "x' OR '1'='1" } } | Should -Throw '*Unsafe value*'
            { New-AZRWql -Class SMS_R_System -Equals @{ "Name = 1 OR 1" = 'x' } } | Should -Throw '*Invalid property name*'
        }
    }
}

Describe 'Remote command templates' {
    InModuleScope AZR.RightClickTools {
        It 'builds fixed command lines' {
            New-AZRCommandLine -Template CcmUninstall -WindowsDirectory 'C:\Windows' | Should -Be '"C:\Windows\ccmsetup\ccmsetup.exe" /uninstall'
            New-AZRCommandLine -Template Restart -WindowsDirectory 'C:\Windows' -Parameter @{ DelaySeconds = 30; Text = 'Restart for updates' } | Should -Be '"C:\Windows\System32\shutdown.exe" /r /t 30 /c "Restart for updates" /d p:4:1'
            New-AZRCommandLine -Template MsiUninstall -WindowsDirectory 'C:\Windows' -Parameter @{ ProductCode = '{12345678-ABCD-ABCD-ABCD-1234567890AB}' } | Should -Be '"C:\Windows\System32\msiexec.exe" /x {12345678-ABCD-ABCD-ABCD-1234567890AB} /qn /norestart'
            New-AZRCommandLine -Template Notify -WindowsDirectory 'C:\Windows' -Parameter @{ Text = 'Hello there' } | Should -Be '"C:\Windows\System32\msg.exe" * /TIME:300 "Hello there"'
        }
        It 'rejects injection through text, product code, delay or directory' {
            { New-AZRCommandLine -Template Notify -WindowsDirectory 'C:\Windows' -Parameter @{ Text = 'x" & calc & "' } } | Should -Throw
            { New-AZRCommandLine -Template MsiUninstall -WindowsDirectory 'C:\Windows' -Parameter @{ ProductCode = '{x} & calc' } } | Should -Throw
            { New-AZRCommandLine -Template Restart -WindowsDirectory 'C:\Windows' -Parameter @{ DelaySeconds = -1; Text = 'x' } } | Should -Throw
            { New-AZRCommandLine -Template GpUpdate -WindowsDirectory 'C:\Windows" & calc & "' } | Should -Throw
        }
        It 'encodes the cache-clear script and contains no caller input' {
            $cmd = New-AZRCommandLine -Template ClearClientCache -WindowsDirectory 'C:\Windows'
            $cmd | Should -Match '-EncodedCommand [A-Za-z0-9+/=]+$'
            $b64 = ($cmd -split '-EncodedCommand ')[1]
            [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($b64)) | Should -Match 'UIResource.UIResourceMgr'
        }
        It 'starts a process through Win32_Process.Create and fails on a non-zero return' {
            Mock Invoke-AZRCim { [pscustomobject]@{ ReturnValue = 0; ProcessId = 4242 } }
            Mock Write-AZRLog {}
            Invoke-AZRRemoteProcess -Session ([pscustomobject]@{}) -CommandLine 'x.exe' -ComputerName PC01 | Should -Be 4242
            Should -Invoke Invoke-AZRCim -ParameterFilter { $ClassName -eq 'Win32_Process' -and $MethodName -eq 'Create' -and $Arguments.CommandLine -eq 'x.exe' }
            Mock Invoke-AZRCim { [pscustomobject]@{ ReturnValue = 5 } }
            { Invoke-AZRRemoteProcess -Session ([pscustomobject]@{}) -CommandLine 'x.exe' -ComputerName PC01 } | Should -Throw '*returned 5*'
        }
    }
}

Describe 'Confirmation policy' {
    InModuleScope AZR.RightClickTools {
        BeforeAll { $s = [pscustomobject]@{ BulkConfirmThreshold = 1; RequireReasonForSecrets = $true } }
        It 'asks nothing for single-device reads and harmless changes' {
            (Get-AZRConfirmationPlan -Risk Read -Scope Device -Count 1 -Settings $s).Kind | Should -Be 'None'
            (Get-AZRConfirmationPlan -Risk Change -Scope Device -Count 1 -Confirm None -Settings $s).Kind | Should -Be 'None'
        }
        It 'asks Yes/No for changes and for any bulk run' {
            (Get-AZRConfirmationPlan -Risk Change -Scope Device -Count 1 -Settings $s).Kind | Should -Be 'YesNo'
            (Get-AZRConfirmationPlan -Risk Change -Scope Collection -Count 40 -Confirm None -Settings $s).Kind | Should -Be 'YesNo'
            (Get-AZRConfirmationPlan -Risk Read -Scope Collection -Count 3 -Settings $s).Kind | Should -Be 'YesNo'
        }
        It 'requires the typed device name or count for destructive actions' {
            $p = Get-AZRConfirmationPlan -Risk Destructive -Scope Device -Count 1 -ComputerName PC01 -Settings $s
            $p.Kind | Should -Be 'Typed'; $p.Expected | Should -Be 'PC01'
            $p = Get-AZRConfirmationPlan -Risk Destructive -Scope Collection -Count 37 -ComputerName PC01 -Settings $s
            $p.Expected | Should -Be '37'
        }
        It 'requires a reason for secrets unless policy turns it off' {
            (Get-AZRConfirmationPlan -Risk Secret -Scope Device -Count 1 -Settings $s).NeedsReason | Should -BeTrue
            (Get-AZRConfirmationPlan -Risk Secret -Scope Device -Count 1 -Settings ([pscustomobject]@{ BulkConfirmThreshold = 1; RequireReasonForSecrets = $false })).NeedsReason | Should -BeFalse
        }
        It 'Confirm-AZRRisk accepts only the exact typed value' {
            Mock Read-AZRInput { 'pc01' }
            (Confirm-AZRRisk -Action 'Restart' -Risk Destructive -Target 'PC01').Approved | Should -BeTrue
            Mock Read-AZRInput { 'PC02' }
            (Confirm-AZRRisk -Action 'Restart' -Risk Destructive -Target 'PC01').Approved | Should -BeFalse
            Mock Read-AZRInput { $null }
            (Confirm-AZRRisk -Action 'Restart' -Risk Destructive -Target 'PC01').Approved | Should -BeFalse
        }
        It 'Confirm-AZRRisk collects a reason for secrets and declines when it is missing' {
            Mock Confirm-AZRAction { $true }
            Mock Read-AZRInput { 'INC4711 user locked out' }
            $r = Confirm-AZRRisk -Action 'LAPS' -Risk Secret -Target 'PC01'
            $r.Approved | Should -BeTrue; $r.Reason | Should -Be 'INC4711 user locked out'
            Mock Read-AZRInput { 'x' }
            (Confirm-AZRRisk -Action 'LAPS' -Risk Secret -Target 'PC01').Approved | Should -BeFalse
            Mock Confirm-AZRAction { $false }
            (Confirm-AZRRisk -Action 'LAPS' -Risk Secret -Target 'PC01').Approved | Should -BeFalse
        }
    }
}

Describe 'Action dispatcher' {
    BeforeAll {
        Mock -ModuleName AZR.RightClickTools Write-AZRLog {}
        Mock -ModuleName AZR.RightClickTools Show-AZRMessage {}
        Mock -ModuleName AZR.RightClickTools Write-AZRAudit {}
        Mock -ModuleName AZR.RightClickTools Get-AZRActionTable {
            $script:ran = $script:ran  # keep variable visible
            @{
                Ping                 = @{ Device = { param($c) $global:AZRTestCtx = $c }; Collection = { param($c) $global:AZRTestCtx = $c } }
                Restart              = @{ Device = { param($c) $global:AZRTestCtx = $c }; Collection = { param($c) $global:AZRTestCtx = $c } }
                BitLockerRecoveryKey = @{ Device = { param($c) $global:AZRTestCtx = $c } }
            }
        }
    }
    BeforeEach { $global:AZRTestCtx = $null }
    AfterAll { Remove-Variable AZRTestCtx -Scope Global -ErrorAction SilentlyContinue }

    It 'runs a read action on a device with no prompt and audits success' {
        Mock -ModuleName AZR.RightClickTools Confirm-AZRAction { throw 'should not prompt' }
        Mock -ModuleName AZR.RightClickTools Read-AZRInput { throw 'should not prompt' }
        Invoke-AZRAction -Action Ping -ComputerName 'PC01'
        $global:AZRTestCtx.ComputerName | Should -Be 'PC01'
        Should -Invoke -ModuleName AZR.RightClickTools Write-AZRAudit -ParameterFilter { $Action -eq 'Ping' -and $Outcome -eq 'Success' -and $Risk -eq 'Read' }
    }
    It 'validates the computer name before anything runs' {
        Invoke-AZRAction -Action Ping -ComputerName 'PC01; calc'
        $global:AZRTestCtx | Should -BeNullOrEmpty
        Should -Invoke -ModuleName AZR.RightClickTools Write-AZRAudit -ParameterFilter { $Outcome -eq 'Failure' }
        Should -Invoke -ModuleName AZR.RightClickTools Show-AZRMessage -ParameterFilter { $Icon -eq 'Error' }
    }
    It 'does not run the handler when a destructive confirmation is declined, and audits the cancellation' {
        Mock -ModuleName AZR.RightClickTools Confirm-AZRRisk { @{ Approved = $false; Reason = $null } }
        Invoke-AZRAction -Action Restart -ComputerName 'PC01'
        $global:AZRTestCtx | Should -BeNullOrEmpty
        Should -Invoke -ModuleName AZR.RightClickTools Write-AZRAudit -ParameterFilter { $Action -eq 'Restart' -and $Outcome -eq 'Cancelled' -and $Risk -eq 'Destructive' }
    }
    It 'passes the reason to secret handlers and leaves the success audit to the handler' {
        Mock -ModuleName AZR.RightClickTools Confirm-AZRRisk { @{ Approved = $true; Reason = 'INC1 forgot PIN' } }
        Invoke-AZRAction -Action BitLockerRecoveryKey -ComputerName 'PC01'
        $global:AZRTestCtx.Reason | Should -Be 'INC1 forgot PIN'
        Should -Invoke -ModuleName AZR.RightClickTools Write-AZRAudit -Times 0 -ParameterFilter { $Outcome -eq 'Success' }
    }
    It 'refuses a secret action against a collection' {
        Invoke-AZRAction -Action BitLockerRecoveryKey -CollectionId 'SMS00001' -SiteServer cm01 -SiteCode ABC
        $global:AZRTestCtx | Should -BeNullOrEmpty
        Should -Invoke -ModuleName AZR.RightClickTools Show-AZRMessage -ParameterFilter { $Message -like '*single device*' }
    }
    It 'resolves collection members, asks for a typed count and hands names to the handler' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCollectionMember { [pscustomobject]@{ ResourceID = 1; Name = 'PC01' }; [pscustomobject]@{ ResourceID = 2; Name = 'PC02' } }
        Mock -ModuleName AZR.RightClickTools Read-AZRInput { '2' }
        Invoke-AZRAction -Action Restart -CollectionId 'SMS00001' -SiteServer cm01 -SiteCode ABC
        $global:AZRTestCtx.Names | Should -Be @('PC01', 'PC02')
        $global:AZRTestCtx.Scope | Should -Be 'Collection'
        Should -Invoke -ModuleName AZR.RightClickTools Write-AZRAudit -ParameterFilter { $Action -eq 'Restart' -and $Outcome -eq 'Success' -and @($Target).Count -eq 2 }
    }
    It 'warns about an empty collection' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCollectionMember { @() }
        Invoke-AZRAction -Action Ping -CollectionId 'SMS00001' -SiteServer cm01 -SiteCode ABC
        Should -Invoke -ModuleName AZR.RightClickTools Show-AZRMessage -ParameterFilter { $Message -like '*no members*' }
    }
}

Describe 'Client actions and tools' {
    BeforeAll {
        Mock -ModuleName AZR.RightClickTools Write-AZRLog {}
        Mock -ModuleName AZR.RightClickTools Invoke-AZRWithCimSession { & $ScriptBlock ([pscustomobject]@{ Fake = $true }) }
    }
    It 'triggers the schedule ID for a new D1 action' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRCim { }
        $r = Invoke-AZRClientAction -ComputerName PC01 -Action SendUnsentStateMessages -Confirm:$false
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-AZRCim -ParameterFilter { $MethodName -eq 'TriggerSchedule' -and $Arguments.sScheduleID -eq '{00000000-0000-0000-0000-000000000111}' }
    }
    It 'reports failure per computer without throwing' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRCim { throw 'RPC unavailable' }
        $r = Invoke-AZRClientAction -ComputerName PC01 -Action HardwareInventory -Confirm:$false
        $r.Success | Should -BeFalse
        $r.Message | Should -Be 'RPC unavailable'
    }
    It 'sets the cache size on the CacheConfig instance' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ Size = 5120; Location = 'C:\Windows\ccmcache' } }
        Mock -ModuleName AZR.RightClickTools Set-AZRCimProperty { }
        $r = Set-AZRClientCacheSize -ComputerName PC01 -SizeMB 20480 -Confirm:$false
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Set-AZRCimProperty -ParameterFilter { $Property.Size -eq 20480 }
        { Set-AZRClientCacheSize -ComputerName PC01 -SizeMB 0 -Confirm:$false } | Should -Throw
    }
    It 'supports -WhatIf for destructive client tools' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRRemoteTemplate { throw 'must not run' }
        { Uninstall-AZRClient -ComputerName PC01 -WhatIf } | Should -Not -Throw
        { Clear-AZRClientCache -ComputerName PC01 -WhatIf } | Should -Not -Throw
    }
    It 'falls back to ccmrepair.exe when RepairClient is unavailable' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRCim { throw 'Not found' } -ParameterFilter { $MethodName -eq 'RepairClient' }
        Mock -ModuleName AZR.RightClickTools Get-AZRWindowsDirectory { 'C:\Windows' }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRRemoteProcess { 11 }
        (Repair-AZRClient -ComputerName PC01 -Confirm:$false).Success | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-AZRRemoteProcess -ParameterFilter { $CommandLine -eq '"C:\Windows\CCM\ccmrepair.exe"' }
    }
    It 'backs up and deletes execution history, then triggers machine policy' {
        $script:deleted = New-Object System.Collections.Generic.List[string]
        Mock -ModuleName AZR.RightClickTools Get-AZRRegSubKey { if ($SubKey -like '*\ABC00012') { @('PROG1') } elseif ($SubKey -like '*\System') { @('ABC00012') } else { @() } }
        Mock -ModuleName AZR.RightClickTools Get-AZRRegString { 'x' }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRReg { $script:deleted.Add($SubKey); [pscustomobject]@{ ReturnValue = 0 } }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRClientAction { [pscustomobject]@{ Success = $true } }
        $r = Reset-AZRExecutionHistory -ComputerName PC01 -PackageId abc00012 -Confirm:$false
        $r.Success | Should -BeTrue
        $script:deleted.Count | Should -Be 2
        $script:deleted[0] | Should -BeLike '*\ABC00012\PROG1'
        $script:deleted[1] | Should -BeLike '*\ABC00012'
        Get-ChildItem $env:AZR_LOG_DIR -Filter 'exechistory-*.json' | Should -Not -BeNullOrEmpty
        { Reset-AZRExecutionHistory -ComputerName PC01 -PackageId 'ABC' -Confirm:$false } | Should -Throw '*Invalid package ID*'
    }
}

Describe 'Power and messaging' {
    It 'builds a 102-byte magic packet' {
        $p = Get-AZRMagicPacket -MacAddress 'AA:BB:CC:DD:EE:FF'
        $p.Length | Should -Be 102
        ($p[0..5] | Select-Object -Unique) | Should -Be 255
        $p[6..11] | Should -Be @(0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF)
        $p[96..101] | Should -Be @(0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF)
        { Get-AZRMagicPacket -MacAddress 'nope' } | Should -Throw
    }
    It 'does not send anything with -WhatIf and validates the broadcast address' {
        (Send-AZRWakeOnLan -MacAddress 'AA:BB:CC:DD:EE:FF' -WhatIf) | Should -BeNullOrEmpty
        { Send-AZRWakeOnLan -MacAddress 'AA:BB:CC:DD:EE:FF' -BroadcastAddress 'not-an-ip' } | Should -Throw
    }
    It 'rejects unsafe notification text before touching the network' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRRemoteTemplate { throw 'must not run' }
        { Send-AZRNotification -ComputerName PC01 -Message 'x" & calc' -Confirm:$false } | Should -Throw '*Message may only contain*'
    }
    It 'runs restart through the template with the delay and message' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRRemoteTemplate { [pscustomobject]@{ Success = $true } }
        $null = Restart-AZRComputer -ComputerName PC01 -DelaySeconds 120 -Message 'Maintenance restart' -Confirm:$false
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-AZRRemoteTemplate -ParameterFilter { $Template -eq 'Restart' -and $Parameter.DelaySeconds -eq 120 -and $Parameter.Text -eq 'Maintenance restart' }
    }
}

Describe 'Collection tools' {
    BeforeAll {
        Mock -ModuleName AZR.RightClickTools Write-AZRLog {}
        Mock -ModuleName AZR.RightClickTools Invoke-AZRWithCimSession { & $ScriptBlock ([pscustomobject]@{ Fake = $true }) }
    }
    It 'lists the collections of a device through validated WQL' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCimQuery {
            if ($Query -like '*SMS_R_System*') { [pscustomobject]@{ Name = 'PC01'; ResourceID = 16777220 } }
            else { [pscustomobject]@{ CollectionID = 'SMS00001'; Name = 'All Systems'; MemberCount = 10 } }
        }
        $r = Get-AZRDeviceCollection -SiteServer cm01 -SiteCode abc -ComputerName PC01
        $r.CollectionID | Should -Be 'SMS00001'
        Should -Invoke -ModuleName AZR.RightClickTools Get-AZRCimQuery -ParameterFilter { $Namespace -eq 'root\sms\site_ABC' -and $Query -like '*ResourceID = 16777220*' }
    }
    It 'adds a direct rule for a device and refuses a user collection' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ CollectionID = 'ABC00012'; CollectionType = 2 } }
        Mock -ModuleName AZR.RightClickTools Get-AZRCimQuery { [pscustomobject]@{ Name = 'PC01'; ResourceID = 16777220 } }
        Mock -ModuleName AZR.RightClickTools New-AZRCollectionRuleObject { [pscustomobject]@{ Rule = $Property.ResourceID } }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRCimOnInstance { }
        $r = Add-AZRDeviceToCollection -SiteServer cm01 -SiteCode ABC -CollectionId ABC00012 -ComputerName PC01 -Confirm:$false
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-AZRCimOnInstance -ParameterFilter { $MethodName -eq 'AddMembershipRule' }
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ CollectionID = 'ABC00099'; CollectionType = 1 } }
        { Add-AZRDeviceToCollection -SiteServer cm01 -SiteCode ABC -CollectionId ABC00099 -ComputerName PC01 -Confirm:$false } | Should -Throw '*not a device collection*'
    }
    It 'summarises a collection' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim {
            if ($ClassName -eq 'SMS_Collection') { [pscustomobject]@{ Name = 'Laptops'; LimitToCollectionID = 'SMS00001'; LastMemberChangeTime = [datetime]'2026-01-01' } }
            else { [pscustomobject]@{ IsClient = $true; IsActive = $true }; [pscustomobject]@{ IsClient = $true; IsActive = $false }; [pscustomobject]@{ IsClient = $false; IsActive = $false } }
        }
        $s = Get-AZRCollectionSummary -SiteServer cm01 -SiteCode ABC -CollectionId ABC00012
        $s.Members | Should -Be 3; $s.WithClient | Should -Be 2; $s.WithoutClient | Should -Be 1; $s.ActiveClients | Should -Be 1; $s.InactiveClients | Should -Be 1
    }
    It 'refuses to delete when a name matches several records' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCimQuery { [pscustomobject]@{ Name = 'PC01' }; [pscustomobject]@{ Name = 'PC01' } }
        Mock -ModuleName AZR.RightClickTools Remove-AZRCimInstance { throw 'must not delete' }
        $r = Remove-AZRDeviceFromConfigMgr -SiteServer cm01 -SiteCode ABC -ComputerName PC01 -Confirm:$false
        $r.Success | Should -BeFalse
        $r.Message | Should -BeLike '*matches 2 records*'
    }
    It 'deletes exactly one matching device' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCimQuery { [pscustomobject]@{ Name = 'PC01' } }
        Mock -ModuleName AZR.RightClickTools Remove-AZRCimInstance { }
        (Remove-AZRDeviceFromConfigMgr -SiteServer cm01 -SiteCode ABC -ComputerName PC01 -Confirm:$false).Success | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Remove-AZRCimInstance -Times 1
    }
    It 'builds status message queries from validated parts and maps severity' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCimQuery {
            [pscustomobject]@{ Time = (Get-Date); Severity = [uint32]3221225472; Component = 'SMS_MP'; MessageID = 5436; ModuleName = 'SMS Server'; InsString1 = 'a'; InsString2 = $null; InsString3 = $null }
        }
        $r = @(Get-AZRStatusMessage -SiteServer cm01 -SiteCode ABC -ComputerName PC01 -Hours 2)
        $r[0].Severity | Should -Be 'Error'
        Should -Invoke -ModuleName AZR.RightClickTools Get-AZRCimQuery -ParameterFilter { $Query -like "SELECT * FROM SMS_StatMsgWithInsStrings WHERE MachineName = 'PC01' AND Time >= '*" -or $Query -like "*FROM SMS_StatMsgWithInsStrings WHERE MachineName = 'PC01' AND Time >= *" }
        { Get-AZRStatusMessage -SiteServer cm01 -SiteCode ABC -ComputerName "PC01' OR 1=1" } | Should -Throw
    }
    It 'only allows SMS_ classes in quick queries' {
        { Invoke-AZRSmsQuery -SiteServer cm01 -SiteCode ABC -Class 'Win32_Process' } | Should -Throw
    }
}

Describe 'System information' {
    BeforeAll {
        Mock -ModuleName AZR.RightClickTools Write-AZRLog {}
        Mock -ModuleName AZR.RightClickTools Invoke-AZRWithCimSession { & $ScriptBlock ([pscustomobject]@{ Fake = $true }) }
    }
    It 'reads software from both uninstall hives and flags MSI product codes' {
        Mock -ModuleName AZR.RightClickTools Get-AZRRegSubKey { if ($SubKey -notlike '*WOW6432Node*') { @('{12345678-ABCD-ABCD-ABCD-1234567890AB}', 'SomeExe') } else { @() } }
        Mock -ModuleName AZR.RightClickTools Get-AZRRegString { switch ($ValueName) { 'DisplayName' { "App $SubKey" } 'DisplayVersion' { '1.0' } default { 'Pub' } } }
        $r = @(Get-AZRSystemInfo -ComputerName PC01 -Section Software)
        $r.Count | Should -Be 2
        ($r | Where-Object ProductCode).ProductCode | Should -Be '{12345678-ABCD-ABCD-ABCD-1234567890AB}'
    }
    It 'reports local administrators using the well-known SID filter' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ Name = 'Administrators' } }
        Mock -ModuleName AZR.RightClickTools Get-AZRCimAssociated { [pscustomobject]@{ Domain = 'CORP'; Name = 'Domain Admins'; SID = 'S-1-5-21-1-2-3-512'; CimClass = [pscustomobject]@{ CimClassName = 'Win32_Group' } } }
        $r = @(Get-AZRLocalAdministrator -ComputerName PC01)
        $r[0].Member | Should -Be 'CORP\Domain Admins'
        $r[0].Type | Should -Be 'Group'
        Should -Invoke -ModuleName AZR.RightClickTools Get-AZRCim -ParameterFilter { $Filter -eq "SID = 'S-1-5-32-544'" }
    }
    It 'returns a failed row instead of throwing for an unreachable computer in the admin report' {
        Mock -ModuleName AZR.RightClickTools Get-AZRSystemInfo { throw 'RPC server unavailable' }
        $r = @(Get-AZRLocalAdministrator -ComputerName PC01)
        $r[0].Success | Should -BeFalse
        $r[0].Message | Should -BeLike '*RPC*'
    }
    It 'refuses to delete loaded or special profiles' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ Loaded = $true; Special = $false } }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRCimOnInstance { throw 'must not delete' }
        (Remove-AZRUserProfile -ComputerName PC01 -Sid 'S-1-5-21-1-2-3-1001' -Confirm:$false).Message | Should -BeLike '*loaded*'
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ Loaded = $false; Special = $true } }
        (Remove-AZRUserProfile -ComputerName PC01 -Sid 'S-1-5-21-1-2-3-1001' -Confirm:$false).Message | Should -BeLike '*system profile*'
        { Remove-AZRUserProfile -ComputerName PC01 -Sid 'bad' -Confirm:$false } | Should -Throw
    }
    It 'terminates a process by ID and starts/stops a service' {
        Mock -ModuleName AZR.RightClickTools Get-AZRCim { [pscustomobject]@{ Name = 'x' } }
        Mock -ModuleName AZR.RightClickTools Invoke-AZRCimOnInstance { [pscustomobject]@{ ReturnValue = 0 } }
        (Stop-AZRRemoteProcess -ComputerName PC01 -ProcessId 4321 -Confirm:$false).Success | Should -BeTrue
        (Set-AZRServiceState -ComputerName PC01 -Name Spooler -State Stop -Confirm:$false).Success | Should -BeTrue
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-AZRCimOnInstance -ParameterFilter { $MethodName -eq 'StopService' }
        { Set-AZRServiceState -ComputerName PC01 -Name 'a;b' -State Stop -Confirm:$false } | Should -Throw
    }
}
