BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    Import-Module (Join-Path $script:Root 'src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
    $env:AZR_LOG_DIR = Join-Path $TestDrive 'logs'
    $env:AZR_SETTINGS_USER = Join-Path $TestDrive 'user.json'
    $env:AZR_SETTINGS_MACHINE = Join-Path $TestDrive 'machine.json'
    $env:AZR_CREDENTIAL_DIR = Join-Path $TestDrive 'creds'
}
AfterAll { foreach ($v in 'AZR_LOG_DIR', 'AZR_SETTINGS_USER', 'AZR_SETTINGS_MACHINE', 'AZR_CREDENTIAL_DIR') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue } }

Describe 'Settings' {
    BeforeEach { Remove-Item $env:AZR_SETTINGS_USER, $env:AZR_SETTINGS_MACHINE -ErrorAction SilentlyContinue }
    It 'returns safe defaults without any file' {
        $s = Get-AZRSettings
        $s.MaxParallel | Should -Be 10
        $s.RequireReasonForSecrets | Should -BeTrue
        $s.AuditToFile | Should -BeTrue
        $s.UseAdminService | Should -BeFalse
    }
    It 'lets the user file override defaults' {
        '{ "MaxParallel": 4, "ExportDirectory": "C:\\Exports" }' | Set-Content $env:AZR_SETTINGS_USER
        $s = Get-AZRSettings
        $s.MaxParallel | Should -Be 4
        $s.ExportDirectory | Should -Be 'C:\Exports'
    }
    It 'lets the machine policy file override the user file' {
        '{ "MaxParallel": 4, "RequireReasonForSecrets": false }' | Set-Content $env:AZR_SETTINGS_USER
        '{ "RequireReasonForSecrets": true }' | Set-Content $env:AZR_SETTINGS_MACHINE
        $s = Get-AZRSettings
        $s.RequireReasonForSecrets | Should -BeTrue
        $s.MaxParallel | Should -Be 4
    }
    It 'ignores invalid values and unknown keys but reports them' {
        '{ "MaxParallel": 9999, "Nonsense": 1, "UseWpfResults": "yes", "AuditPath": "x" }' | Set-Content $env:AZR_SETTINGS_USER
        $r = Get-AZRSettings -Detailed
        $r.Settings.MaxParallel | Should -Be 10
        $r.Settings.UseWpfResults | Should -BeTrue
        $r.Settings.AuditPath | Should -Be 'x'
        $r.Errors.Count | Should -Be 3
    }
    It 'survives a corrupt file' {
        'not json' | Set-Content $env:AZR_SETTINGS_USER
        (Get-AZRSettings).MaxParallel | Should -Be 10
    }
}

Describe 'Stored credentials' {
    It 'round-trips a credential and never stores the password as text' {
        $cred = [pscredential]::new('CORP\svc', (ConvertTo-SecureString 'Sup3rS3cret!' -AsPlainText -Force))
        Save-AZRCredential -Name 'Corp' -Credential $cred
        $file = Join-Path $env:AZR_CREDENTIAL_DIR 'Corp.cred.xml'
        Test-Path $file | Should -BeTrue
        if ($env:OS -eq 'Windows_NT') { (Get-Content $file -Raw) | Should -Not -Match 'Sup3rS3cret' }
        $back = Get-AZRStoredCredential -Name 'Corp'
        $back.UserName | Should -Be 'CORP\svc'
        Remove-AZRStoredCredential -Name 'Corp' -Confirm:$false
        Get-AZRStoredCredential -Name 'Corp' | Should -BeNullOrEmpty
    }
    It 'rejects path-like names' {
        { Get-AZRStoredCredential -Name '..\evil' } | Should -Throw '*Invalid credential name*'
        { Save-AZRCredential -Name 'a/b' -Credential ([pscredential]::new('u', (ConvertTo-SecureString 'x' -AsPlainText -Force))) } | Should -Throw
    }
    It 'uses the DefaultCredentialName setting for CIM sessions' {
        $cred = [pscredential]::new('CORP\svc', (ConvertTo-SecureString 'x' -AsPlainText -Force))
        Save-AZRCredential -Name 'Dflt' -Credential $cred
        '{ "DefaultCredentialName": "Dflt" }' | Set-Content $env:AZR_SETTINGS_USER
        InModuleScope AZR.RightClickTools { (Get-AZRDefaultCredential).UserName | Should -Be 'CORP\svc' }
        Remove-Item $env:AZR_SETTINGS_USER
    }
}

Describe 'Audit log' {
    BeforeEach { Get-ChildItem $env:AZR_LOG_DIR -Filter 'audit-*' -ErrorAction SilentlyContinue | Remove-Item }
    It 'writes one JSON object per line with who, what, target, outcome and risk' {
        Write-AZRAudit -Action 'Restart' -Target 'PC01', 'PC02' -Risk Destructive -Outcome Success -Reason 'INC1234'
        $file = Get-ChildItem $env:AZR_LOG_DIR -Filter 'audit-*.jsonl' | Select-Object -First 1
        $e = (Get-Content $file.FullName | Select-Object -Last 1) | ConvertFrom-Json
        $e.action | Should -Be 'Restart'
        $e.risk | Should -Be 'Destructive'
        $e.outcome | Should -Be 'Success'
        $e.targetCount | Should -Be 2
        $e.reason | Should -Be 'INC1234'
        $e.user | Should -Not -BeNullOrEmpty
        { [datetime]$e.time } | Should -Not -Throw
    }
    It 'redacts secret-looking detail fields and SecureStrings' {
        $ss = ConvertTo-SecureString 'AAAA-BBBB' -AsPlainText -Force
        Write-AZRAudit -Action 'Test' -Detail @{ RecoveryPassword = '111111-222222'; Nested = @{ Token = 'abc' }; KeyCount = 2; Other = $ss }
        $raw = (Get-ChildItem $env:AZR_LOG_DIR -Filter 'audit-*.jsonl' | Select-Object -First 1 | Get-Content -Raw)
        $raw | Should -Not -Match '111111-222222'
        $raw | Should -Not -Match 'abc'
        $raw | Should -Not -Match 'AAAA-BBBB'
        $raw | Should -Match '\[redacted\]'
        $raw | Should -Match '"KeyCount":2'
    }
    It 'can write to a configured path' {
        $p = Join-Path $TestDrive 'custom\audit.jsonl'
        ('{ "AuditPath": "' + ($p -replace '\\', '\\') + '" }') | Set-Content $env:AZR_SETTINGS_USER
        Write-AZRAudit -Action 'X'
        Test-Path $p | Should -BeTrue
        Remove-Item $env:AZR_SETTINGS_USER
    }
}

Describe 'Secret handling rules (static)' {
    It 'never passes secret-looking variables to Write-AZRLog or Write-AZRAudit' {
        $bad = New-Object System.Collections.Generic.List[string]
        foreach ($f in Get-ChildItem (Join-Path $script:Root 'src') -Recurse -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'Write-AZRLog', 'Write-AZRAudit' }, $true)
            foreach ($c in $calls) {
                $vars = $c.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
                foreach ($v in $vars) {
                    if ($v.VariablePath.UserPath -match '(?i)password|passwd|secret|recoverykey|^pw$|plain|^key$|token') { $bad.Add("$($f.Name):$($v.Extent.StartLineNumber) uses `$$($v.VariablePath.UserPath)") }
                }
            }
        }
        $bad | Should -BeNullOrEmpty
    }
    It 'detects a violation (rule self-check)' {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput('Write-AZRLog -Message "k $RecoveryPassword"', [ref]$null, [ref]$null)
        $c = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        @($c[0].FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -match '(?i)password' }, $true)).Count | Should -Be 1
    }
}

Describe 'Parallel runner' {
    It 'runs serially when throttled to 1 and returns one result per target' {
        InModuleScope AZR.RightClickTools {
            $r = @(Invoke-AZRParallel -Target 'a', 'b', 'c' -ThrottleLimit 1 -ScriptBlock { param($t) "hello $t" })
            $r.Count | Should -Be 3
            $r.Success | Should -Not -Contain $false
            ($r | Where-Object Target -eq 'b').Output | Should -Be 'hello b'
        }
    }
    It 'captures failures per target instead of stopping' {
        InModuleScope AZR.RightClickTools {
            $r = @(Invoke-AZRParallel -Target 'ok', 'bad' -ThrottleLimit 1 -ScriptBlock { param($t) if ($t -eq 'bad') { throw 'boom' } 'fine' })
            ($r | Where-Object Target -eq 'bad').Success | Should -BeFalse
            ($r | Where-Object Target -eq 'bad').Error | Should -Be 'boom'
            ($r | Where-Object Target -eq 'ok').Success | Should -BeTrue
        }
    }
    It 'runs in parallel with the module loaded in every runspace' {
        InModuleScope AZR.RightClickTools {
            $r = @(Invoke-AZRParallel -Target (1..6) -ThrottleLimit 3 -ArgumentList @('x') -ScriptBlock { param($t, $suffix) "$t$suffix"; (Get-AZRClientActionList).Count })
            $r.Count | Should -Be 6
            $r.Success | Should -Not -Contain $false
            ($r | Where-Object Target -eq '3').Output[0] | Should -Be '3x'
            ($r | Where-Object Target -eq '3').Output[1] | Should -BeGreaterThan 5
        }
    }
    It 'reports a terminating error in a parallel runspace as a failed target' {
        InModuleScope AZR.RightClickTools {
            $r = @(Invoke-AZRParallel -Target 'a', 'b' -ThrottleLimit 2 -ScriptBlock { param($t) if ($t -eq 'b') { throw 'bad target' } 'ok' })
            ($r | Where-Object Target -eq 'b').Success | Should -BeFalse
            ($r | Where-Object Target -eq 'b').Error | Should -Match 'bad target'
            ($r | Where-Object Target -eq 'a').Success | Should -BeTrue
        }
    }
    It 'returns nothing for no targets' {
        InModuleScope AZR.RightClickTools { @(Invoke-AZRParallel -Target @() -ScriptBlock { 1 }).Count | Should -Be 0 }
    }
}

Describe 'Invoke-AZRBulk' {
    It 'rejects bad names and unknown functions' {
        { Invoke-AZRBulk -ComputerName 'PC01;calc' -Function Get-AZRService } | Should -Throw '*Invalid computer name*'
        { Invoke-AZRBulk -ComputerName 'PC01' -Function 'Get-Process' } | Should -Throw
        { Invoke-AZRBulk -ComputerName 'PC01' -Function 'Get-AZRNotThere' } | Should -Throw '*Unknown AZR function*'
    }
    It 'flattens output and turns exceptions into failed rows' {
        Mock -ModuleName AZR.RightClickTools Invoke-AZRParallel {
            [pscustomobject]@{ Target = 'pc1'; Success = $true; Output = @([pscustomobject]@{ ComputerName = 'pc1'; Success = $true; Message = 'ok' }); Error = ''; DurationMs = 1 }
            [pscustomobject]@{ Target = 'pc2'; Success = $false; Output = @(); Error = 'WinRM cannot connect'; DurationMs = 1 }
        }
        $rows = @(Invoke-AZRBulk -ComputerName 'pc1', 'pc2' -Function Test-AZRConnection)
        $rows.Count | Should -Be 2
        ($rows | Where-Object ComputerName -eq 'pc2').Success | Should -BeFalse
        ($rows | Where-Object ComputerName -eq 'pc2').Message | Should -Be 'WinRM cannot connect'
        ($rows | Where-Object ComputerName -eq 'pc1').Message | Should -Be 'ok'
    }
}

Describe 'Result export' {
    It 'writes CSV and protects against formula injection' {
        $p = Join-Path $TestDrive 'out.csv'
        @([pscustomobject]@{ Name = '=cmd|calc'; Note = 'plain'; Plus = '+1+1'; At = '@SUM(1)'; Minus = '-2' }) | Export-AZRResult -Format Csv -Path $p | Should -Be $p
        $csv = Get-Content $p -Raw
        $csv | Should -Match "'=cmd\|calc"
        $csv | Should -Match "'\+1\+1"
        $csv | Should -Match "'@SUM"
        $csv | Should -Match "'-2"
        $csv | Should -Match 'plain'
    }
    It 'never exports SecureString values' {
        $ss = ConvertTo-SecureString 'TOP-SECRET-KEY' -AsPlainText -Force
        $p = Join-Path $TestDrive 'secret.json'
        @([pscustomobject]@{ Id = 1; Key = $ss }) | Export-AZRResult -Format Json -Path $p | Out-Null
        $json = Get-Content $p -Raw
        $json | Should -Not -Match 'TOP-SECRET-KEY'
        $json | Should -Match '\[hidden\]'
    }
    It 'joins arrays and picks a timestamped file name in the export directory' {
        ('{ "ExportDirectory": "' + (($TestDrive -replace '\\', '\\')) + '" }') | Set-Content $env:AZR_SETTINGS_USER
        $path = @([pscustomobject]@{ A = @(1, 2, 3) }) | Export-AZRResult -Format Csv -Name 'my report!'
        $path | Should -Match 'my_report_-\d{8}-\d{6}\.csv$'
        (Get-Content $path -Raw) | Should -Match '1; 2; 3'
        Remove-Item $env:AZR_SETTINGS_USER
    }
}

Describe 'AdminService client' {
    BeforeAll { Mock -ModuleName AZR.RightClickTools Write-AZRLog {} }
    It 'builds a validated, encoded request using the current identity' {
        Mock -ModuleName AZR.RightClickTools Invoke-RestMethod { [pscustomobject]@{ value = @([pscustomobject]@{ Name = 'PC01' }) } }
        $r = Invoke-AZRAdminService -Server 'cm01.corp.example' -Path 'wmi/SMS_R_System' -Query @{ '$filter' = "Name eq 'PC01'"; '$select' = 'Name' }
        $r[0].Name | Should -Be 'PC01'
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq "https://cm01.corp.example/AdminService/wmi/SMS_R_System?`$filter=Name%20eq%20%27PC01%27&`$select=Name" -and $UseDefaultCredentials -and $Method -eq 'Get'
        }
    }
    It 'follows paging links on the same host and aggregates values' {
        $script:calls = 0
        Mock -ModuleName AZR.RightClickTools Invoke-RestMethod {
            $script:calls++
            if ($script:calls -eq 1) { [pscustomobject]@{ value = @(1, 2); '@odata.nextLink' = 'https://cm01/AdminService/wmi/X?$skip=2' } }
            else { [pscustomobject]@{ value = @(3) } }
        }
        $r = Invoke-AZRAdminService -Server cm01 -Path 'wmi/X'
        $r | Should -Be @(1, 2, 3)
    }
    It 'refuses a paging link to another host' {
        Mock -ModuleName AZR.RightClickTools Invoke-RestMethod { [pscustomobject]@{ value = @(1); '@odata.nextLink' = 'https://evil.example/steal' } }
        { Invoke-AZRAdminService -Server cm01 -Path 'wmi/X' } | Should -Throw '*different host*'
    }
    It 'validates server and path' {
        { Invoke-AZRAdminService -Server 'cm01;x' -Path 'wmi/X' } | Should -Throw '*Invalid computer name*'
        { Invoke-AZRAdminService -Server cm01 -Path '../secret' } | Should -Throw '*Invalid AdminService path*'
        { Invoke-AZRAdminService -Server cm01 -Path 'wmi/X?y=1' } | Should -Throw '*Invalid AdminService path*'
    }
    It 'turns HTTP failures into a helpful error' {
        Mock -ModuleName AZR.RightClickTools Invoke-RestMethod { throw 'The remote server returned an error: (404) Not Found.' }
        { Invoke-AZRAdminService -Server cm01 -Path 'wmi/X' } | Should -Throw '*AdminService call failed*'
    }
    It 'sends a JSON body for POST and supports a base URI override' {
        Mock -ModuleName AZR.RightClickTools Invoke-RestMethod { [pscustomobject]@{ ok = $true } }
        $null = Invoke-AZRAdminService -BaseUri 'http://localhost:9/AdminService' -Path 'v1.0/Device(1)/X' -Method Post -Body @{ a = 1 }
        Should -Invoke -ModuleName AZR.RightClickTools Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq 'http://localhost:9/AdminService/v1.0/Device(1)/X' -and $Body -eq '{"a":1}' }
    }
}

Describe 'Graph helper' {
    BeforeAll {
        function global:Invoke-MgGraphRequest { param($Method, $Uri, $Body) }
        Mock -ModuleName AZR.RightClickTools Write-AZRLog {}
    }
    AfterAll { Remove-Item function:global:Invoke-MgGraphRequest -ErrorAction SilentlyContinue }
    It 'maps features to least-privilege scopes' {
        Get-AZRGraphScope -Feature BitLockerKeys | Should -Contain 'BitLockerKey.Read.All'
        Get-AZRGraphScope -Feature Laps | Should -Contain 'DeviceLocalCredential.Read.All'
        Get-AZRGraphScope -Feature BitLockerKeys, Laps | Should -Not -Contain 'Directory.ReadWrite.All'
    }
    It 'follows paging and validates the URI' {
        $script:n = 0
        Mock -ModuleName AZR.RightClickTools Invoke-MgGraphRequest {
            $script:n++
            if ($script:n -eq 1) { @{ value = @(@{ id = 1 }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/devices?$skiptoken=x' } } else { @{ value = @(@{ id = 2 }) } }
        }
        $r = Invoke-AZRGraph -Uri "/v1.0/devices?`$select=id"
        $r.Count | Should -Be 2
        { Invoke-AZRGraph -Uri 'https://evil.example/x' } | Should -Throw '*Invalid Graph URI*'
        { Invoke-AZRGraph -Uri '/v1.0/../x' } | Should -Not -Throw -Because 'dots are legal in path segments; only absolute URLs are refused'
    }
    It 'refuses paging links to other hosts' {
        Mock -ModuleName AZR.RightClickTools Invoke-MgGraphRequest { @{ value = @(1); '@odata.nextLink' = 'https://evil.example/next' } }
        { Invoke-AZRGraph -Uri '/v1.0/devices' } | Should -Throw '*different host*'
    }
}

Describe 'Window host' {
    It 'ships well-formed XAML with the named controls the code looks up' {
        InModuleScope AZR.RightClickTools {
            $x = [xml](Get-AZRWindowXaml)
            $names = $x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml') }
            foreach ($n in 'BtnRefresh', 'BtnCsv', 'BtnJson', 'BtnCopy', 'FilterBox', 'ActionBar', 'StatusText', 'Tabs') { $names | Should -Contain $n }
            $y = [xml](Get-AZRSecretWindowXaml)
            $names2 = $y.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml') }
            foreach ($n in 'Notice', 'Items', 'StatusText', 'BtnClose') { $names2 | Should -Contain $n }
        }
    }
    It 'filters rows on any property, ignoring case' {
        InModuleScope AZR.RightClickTools {
            $row = [pscustomobject]@{ Name = 'CcmExec'; State = 'Running'; Empty = $null }
            Test-AZRRowMatch -Row $row -Text 'ccm' | Should -BeTrue
            Test-AZRRowMatch -Row $row -Text 'RUN' | Should -BeTrue
            Test-AZRRowMatch -Row $row -Text 'zzz' | Should -BeFalse
            Test-AZRRowMatch -Row $row -Text '' | Should -BeTrue
        }
    }
    It 'builds the WPF host headlessly (Windows only)' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope AZR.RightClickTools {
            $r = Invoke-AZRSta -ScriptBlock {
                & (Get-Module AZR.RightClickTools) {
                    $w = New-AZRWindowObject -Title 'Smoke' -Tab @(@{ Name = 'One'; Data = @([pscustomobject]@{ A = 1; K = (ConvertTo-SecureString 'x' -AsPlainText -Force) }) }, @{ Name = 'Two'; Loader = { 1..3 | ForEach-Object { [pscustomobject]@{ N = $_ } } } }) `
                        -Action @(@{ Name = 'Do'; Script = { param($r) }; Tab = 'One' })
                    [pscustomobject]@{ Tabs = $w.State.Tabs.Count; Rows = $w.State.Tabs[0].Grid.Items.Count; Title = $w.Window.Title; Secret = $w.State.Tabs[0].Grid.Items[0].K }
                }
            }
            $r.Tabs | Should -Be 2
            $r.Rows | Should -Be 1
            $r.Title | Should -Be 'Smoke'
            $r.Secret | Should -Be '[hidden]'
        }
    }
}
