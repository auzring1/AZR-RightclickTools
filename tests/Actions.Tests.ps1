BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    Import-Module (Join-Path $script:Root 'src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
    $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $script:Root 'src\Actions.psd1')
    $script:AllActions = $script:Manifest.Groups.Actions
}

Describe 'Module' {
    It 'exports every function declared in the manifest' {
        $declared = (Import-PowerShellDataFile (Join-Path $script:Root 'src\AZR.RightClickTools\AZR.RightClickTools.psd1')).FunctionsToExport
        $exported = (Get-Command -Module AZR.RightClickTools).Name
        $declared | ForEach-Object { $exported | Should -Contain $_ }
    }
}

Describe 'Client action list' {
    It 'has unique names and well-formed schedule IDs' {
        $list = Get-AZRClientActionList
        ($list.Name | Select-Object -Unique).Count | Should -Be $list.Count
        $list.ScheduleId | ForEach-Object { $_ | Should -Match '^\{[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}\}$' }
    }
}

Describe 'Action manifest' {
    It 'only references actions the dispatcher knows' {
        $known = (Get-AZRClientActionList).Name + 'Ping', 'DeviceInfo', 'Services', 'RestartCcmExec', 'EventLog', 'BrowseC', 'ClientLogs', 'Rdp', 'RdpAdmin', 'RemoteShell', 'ComputerManagement'
        foreach ($a in $script:AllActions) { $known | Should -Contain $a.Id }
    }
    It 'has unique action IDs' {
        ($script:AllActions.Id | Select-Object -Unique).Count | Should -Be $script:AllActions.Count
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

    It 'writes well-formed XML for both nodes' {
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
    }
}
