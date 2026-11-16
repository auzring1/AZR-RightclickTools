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
