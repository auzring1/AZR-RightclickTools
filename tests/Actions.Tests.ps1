BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    Import-Module (Join-Path $script:Root 'src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
    $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $script:Root 'src\Actions.psd1')
    $script:Nodes = Import-PowerShellDataFile -Path (Join-Path $script:Root 'src\Nodes.psd1')
    $script:AllActions = $script:Manifest.Groups.Actions
}

Describe 'Module' {
    It 'exports every function declared in the manifest' {
        $declared = (Import-PowerShellDataFile (Join-Path $script:Root 'src\AZR.RightClickTools\AZR.RightClickTools.psd1')).FunctionsToExport
        $exported = (Get-Command -Module AZR.RightClickTools).Name
        $declared | ForEach-Object { $exported | Should -Contain $_ }
    }
    It 'declares every public function in Public\*.ps1 unless it is a known internal helper' {
        $declared = (Import-PowerShellDataFile (Join-Path $script:Root 'src\AZR.RightClickTools\AZR.RightClickTools.psd1')).FunctionsToExport
        $internal = 'Get-AZRSystemInfoSection', 'Get-AZRWindowsSecuritySection', 'Set-AZRCollectionRule', 'New-AZRCollectionRuleObject',
        'ConvertTo-AZRBitLockerMethod', 'ConvertTo-AZRBitLockerProtectorType', 'ConvertTo-AZRBitLockerStatus', 'ConvertTo-AZRSecureString',
        'ConvertTo-AZRFirewallAction', 'ConvertTo-AZRFirewallEnabled', 'ConvertTo-AZRDeviceGuardService'
        $defined = foreach ($f in Get-ChildItem (Join-Path $script:Root 'src\AZR.RightClickTools\Public') -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false).Name
        }
        foreach ($d in $defined) { if ($d -notin $internal) { $declared | Should -Contain $d -Because "$d is public" } }
    }
    It 'parses every script without errors' {
        foreach ($f in Get-ChildItem (Join-Path $script:Root 'src'), (Join-Path $script:Root 'tools'), (Join-Path $script:Root 'installer') -Recurse -Filter *.ps1) {
            $errs = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
            $errs | Should -BeNullOrEmpty -Because $f.Name
        }
    }
}

Describe 'Client action list' {
    It 'has unique names and well-formed schedule IDs' {
        $list = Get-AZRClientActionList
        ($list.Name | Select-Object -Unique).Count | Should -Be $list.Count
        ($list.ScheduleId | Select-Object -Unique).Count | Should -Be $list.Count
        $list.ScheduleId | ForEach-Object { $_ | Should -Match '^\{[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}\}$' }
    }
}

Describe 'Action manifest (schema v2)' {
    It 'is schema version 2' { $script:Manifest.SchemaVersion | Should -Be 2 }
    It 'has a handler for every action id' {
        InModuleScope AZR.RightClickTools -Parameters @{ ids = $script:AllActions.Id } {
            $table = Get-AZRActionTable
            foreach ($id in $ids) { $table.ContainsKey($id) | Should -BeTrue -Because $id }
        }
    }
    It 'has a handler scope for every declared target' {
        InModuleScope AZR.RightClickTools -Parameters @{ actions = $script:AllActions } {
            $table = Get-AZRActionTable
            foreach ($a in $actions) {
                foreach ($t in $a.Targets) { $table[$a.Id].ContainsKey($t) | Should -BeTrue -Because "$($a.Id) declares target $t" }
            }
        }
    }
    It 'has unique action IDs' {
        ($script:AllActions.Id | Select-Object -Unique).Count | Should -Be $script:AllActions.Count
    }
    It 'only uses allowed Risk, Requires, Confirm and Ui values' {
        foreach ($a in $script:AllActions) {
            $risk = if ($a.Risk) { $a.Risk } else { 'Read' }
            $risk | Should -BeIn 'Read', 'Change', 'Destructive', 'Secret'
            foreach ($r in @($a.Requires)) { if ($r) { $r | Should -BeIn 'AD', 'Graph', 'AdminSvc', 'ConfigMgrModule', 'SmsProvider' } }
            if ($a.Confirm) { $a.Confirm | Should -BeIn 'Auto', 'None' }
            if ($a.Ui) { $a.Ui | Should -Match '^(None|Grid|Window:[A-Za-z]+)$' }
        }
    }
    It 'never skips confirmation for destructive or secret actions, and keeps secrets single-device' {
        foreach ($a in $script:AllActions) {
            if ($a.Risk -in 'Destructive', 'Secret') { $a.Confirm | Should -Not -Be 'None' -Because $a.Id }
            if ($a.Risk -eq 'Secret') { $a.Targets | Should -Not -Contain 'Collection' -Because $a.Id }
        }
    }
    It 'targets only nodes that exist and have a GUID' {
        foreach ($a in $script:AllActions) { foreach ($t in $a.Targets) { $script:Nodes[$t].Guid | Should -Not -BeNullOrEmpty -Because "$($a.Id) -> $t" } }
    }
    It 'uses only placeholders its node supports' {
        foreach ($n in $script:Nodes.Keys) {
            $node = $script:Nodes[$n]
            if (-not $node.TargetArgs) { continue }
            foreach ($m in [regex]::Matches($node.TargetArgs, '##SUB:([^#]+)##')) { $node.Placeholders | Should -Contain $m.Groups[1].Value }
        }
    }
    It 'resolves definitions from the manifest with defaults' {
        InModuleScope AZR.RightClickTools {
            $d = Get-AZRActionDefinition -Id 'BitLockerRecoveryKey'
            $d.Risk | Should -Be 'Secret'
            (Get-AZRActionDefinition -Id 'Ping').Risk | Should -Be 'Read'
            Get-AZRActionDefinition -Id 'NoSuchAction' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-AZRAction' {
    It 'rejects unknown actions' {
        { Invoke-AZRAction -Action 'Nope' -ComputerName 'PC01' } | Should -Throw '*Unknown action*'
    }
}

Describe 'Build-ConsoleExtension' {
    BeforeAll {
        $script:Out = Join-Path ([System.IO.Path]::GetTempPath()) ('azr-test-' + [guid]::NewGuid())
        & (Join-Path $script:Root 'tools\Build-ConsoleExtension.ps1') -LauncherPath 'C:\Program Files\AZR-RightClickTools\Launcher\Invoke-AZRLauncher.ps1' -OutputPath $script:Out
    }
    AfterAll { Remove-Item -LiteralPath $script:Out -Recurse -Force -ErrorAction SilentlyContinue }

    It 'writes well-formed XML for each node that has a GUID and actions' {
        $files = Get-ChildItem -Path $script:Out -Recurse -Filter '*.xml'
        $files.Count | Should -Be 2
        foreach ($f in $files) { { [xml](Get-Content -LiteralPath $f.FullName -Raw) } | Should -Not -Throw }
    }
    It 'uses the device substitution on the device node and collection ID on the collection node' {
        $dev = Get-Content -Raw (Join-Path $script:Out 'ed9dee86-eadd-4ac8-82a1-7234a4646e62\AZR-RightClickTools.xml')
        $col = Get-Content -Raw (Join-Path $script:Out '3fd01cd1-9e01-461e-92cd-94866b8d1f39\AZR-RightClickTools.xml')
        $dev | Should -Match '##SUB:Name##'
        $col | Should -Match '##SUB:CollectionID##'
        $col | Should -Not -Match 'Action RemoteShell'
        $col | Should -Not -Match 'Action BitLockerRecoveryKey'
        $dev | Should -Match 'Action BitLockerRecoveryKey'
    }
    It 'launches PowerShell in STA mode for the WPF windows' {
        (Get-Content -Raw (Join-Path $script:Out 'ed9dee86-eadd-4ac8-82a1-7234a4646e62\AZR-RightClickTools.xml')) | Should -Match '-STA'
    }
    It 'escapes XML special characters in menu names' {
        $dev = Get-Content -Raw (Join-Path $script:Out 'ed9dee86-eadd-4ac8-82a1-7234a4646e62\AZR-RightClickTools.xml')
        $dev | Should -Match 'Machine Policy Retrieval &amp;&amp; Evaluation'
        $dev | Should -Not -Match 'Retrieval && Evaluation'
    }
    It 'generates one menu entry per action per target' {
        $dev = [xml](Get-Content -Raw (Join-Path $script:Out 'ed9dee86-eadd-4ac8-82a1-7234a4646e62\AZR-RightClickTools.xml'))
        $count = @($dev.SelectNodes('//ActionDescription[@Class="Executable"]')).Count
        $count | Should -Be @($script:AllActions | Where-Object { $_.Targets -contains 'Device' }).Count
    }
    It 'refuses an invalid manifest and lists the problems' {
        $bad = Join-Path $TestDrive 'bad.psd1'
        Set-Content -LiteralPath $bad -Value "@{ SchemaVersion = 2; Menu = 'X'; Groups = @(@{ Name = 'G'; Actions = @(@{ Id = 'A'; Name = 'n'; Description = 'd'; Targets = 'Nowhere'; Risk = 'Explode' }, @{ Id = 'Danger'; Name = 'n'; Description = 'd'; Targets = 'Device'; Risk = 'Destructive'; Confirm = 'None' }) }) }"
        { & (Join-Path $script:Root 'tools\Build-ConsoleExtension.ps1') -LauncherPath 'C:\l.ps1' -OutputPath (Join-Path $TestDrive 'o') -ManifestPath $bad } |
            Should -Throw '*unknown target*'
    }
}

Describe 'Get-AZRConsoleNodes tool' {
    It 'reports placeholders and menu names per node GUID folder' {
        . (Join-Path $script:Root 'tools\Get-AZRConsoleNodes.ps1')
        $guid = '11111111-2222-3333-4444-555555555555'
        $dir = Join-Path $TestDrive "Actions\$guid"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Actions\not-a-guid') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'x.xml') -Value '<A DisplayName="Delete"><P>-n ##SUB:Name## ##SUB:ResourceID## ##SUB:Name##</P></A>'
        $r = @(Get-AZRConsoleNodeInfo -ActionsPath (Join-Path $TestDrive 'Actions'))
        $r.Count | Should -Be 1
        $r[0].Guid | Should -Be $guid
        $r[0].Placeholders | Should -Be @('Name', 'ResourceID')
        $r[0].MenuNames | Should -Contain 'Delete'
    }
}
