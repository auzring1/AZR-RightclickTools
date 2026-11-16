BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    $script:Installer = Join-Path $script:Root 'installer\Install-AZRRightClickTools.ps1'
}

Describe 'Installer' {
    It 'fails with a clear message when pasted instead of run as a file' {
        # A script block built from text has an empty $PSScriptRoot, like pasting into a console.
        $sb = [scriptblock]::Create((Get-Content -LiteralPath $script:Installer -Raw))
        { & $sb -WhatIf } | Should -Throw '*must be run as a file*'
    }
    It 'does not fail the guard when run as a file' {
        $err = $null
        try { & $script:Installer -ConsoleDir $TestDrive -WhatIf } catch { $err = $_.Exception.Message }
        $err | Should -Not -Match 'must be run as a file'
    }
}
