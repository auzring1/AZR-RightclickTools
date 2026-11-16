BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '..\src\AZR.RightClickTools\AZR.RightClickTools.psd1') -Force
}

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\src\AZR.RightClickTools\AZR.RightClickTools.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'Input validation' {
    InModuleScope AZR.RightClickTools {
        It 'accepts valid host names' -ForEach @('PC01', 'pc-01.corp.example.com', '10.0.0.5') {
            Assert-AZRComputerName -ComputerName $_ | Should -Be $_
        }
        It 'rejects injection attempts' -ForEach @(
            "PC01'; calc; '", 'PC01 -Foo', 'PC01&whoami', '', '-bad', 'a b', 'PC01"x') {
            { Assert-AZRComputerName -ComputerName $_ } | Should -Throw
        }
        It 'validates collection IDs' {
            Assert-AZRCollectionId -CollectionId 'SMS00001' | Should -Be 'SMS00001'
            { Assert-AZRCollectionId -CollectionId "SMS00001' OR 1=1" } | Should -Throw
        }
        It 'validates site codes' {
            Assert-AZRSiteCode -SiteCode 'abc' | Should -Be 'ABC'
            { Assert-AZRSiteCode -SiteCode 'ABCD' } | Should -Throw
        }
    }
}

Describe 'New validators' {
    InModuleScope AZR.RightClickTools {
        It 'normalises MAC addresses' {
            Assert-AZRMacAddress -MacAddress 'aa:bb:cc:dd:ee:ff' | Should -Be 'AABBCCDDEEFF'
            Assert-AZRMacAddress -MacAddress 'AA-BB-CC-DD-EE-FF' | Should -Be 'AABBCCDDEEFF'
            Assert-AZRMacAddress -MacAddress '001122334455' | Should -Be '001122334455'
            { Assert-AZRMacAddress -MacAddress 'AA:BB:CC:DD:EE' } | Should -Throw
            { Assert-AZRMacAddress -MacAddress 'GG:BB:CC:DD:EE:FF' } | Should -Throw
        }
        It 'validates package IDs and product codes' {
            Assert-AZRPackageId -PackageId 'abc00012' | Should -Be 'ABC00012'
            { Assert-AZRPackageId -PackageId "ABC0001'" } | Should -Throw
            Assert-AZRProductCode -ProductCode '{12345678-ABCD-ABCD-ABCD-1234567890AB}' | Should -Be '{12345678-ABCD-ABCD-ABCD-1234567890AB}'
            { Assert-AZRProductCode -ProductCode '{x}; calc' } | Should -Throw
        }
        It 'only allows safe message text' {
            Assert-AZRMessageText -Text 'Please save your work (restart in 5 minutes).' | Should -Not -BeNullOrEmpty
            foreach ($bad in 'hi" & calc', 'a|b', 'x > y', '%COMSPEC%', '`whoami`', '$(calc)', "line1`nline2", '', ('x' * 300)) {
                { Assert-AZRMessageText -Text $bad } | Should -Throw -Because $bad
            }
        }
        It 'requires a sensible reason' {
            Assert-AZRReason -Reason '  INC12345 lost laptop ' | Should -Be 'INC12345 lost laptop'
            { Assert-AZRReason -Reason 'x' } | Should -Throw
            { Assert-AZRReason -Reason "a`nb" } | Should -Throw
        }
        It 'rejects unsafe WQL values and service names' {
            { Assert-AZRWqlValue -Value "PC01' OR Name LIKE '%" } | Should -Throw
            Assert-AZRWqlValue -Value 'PC-01.corp' | Should -Be 'PC-01.corp'
            { Assert-AZRServiceName -Name 'x; calc' } | Should -Throw
        }
    }
}
