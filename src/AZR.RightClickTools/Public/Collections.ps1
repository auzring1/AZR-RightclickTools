function Get-AZRCollectionMember {
    <#
    .SYNOPSIS
        Lists the member devices of a collection using the SMS Provider (CIM), no ConfigMgr cmdlets needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$CollectionId
    )
    $null = Assert-AZRComputerName -ComputerName $SiteServer
    $SiteCode = Assert-AZRSiteCode -SiteCode $SiteCode
    $CollectionId = Assert-AZRCollectionId -CollectionId $CollectionId
    Invoke-AZRWithCimSession -ComputerName $SiteServer -ScriptBlock {
        param($s)
        Get-CimInstance -CimSession $s -Namespace "root\sms\site_$SiteCode" -ClassName SMS_FullCollectionMembership `
            -Filter "CollectionID = '$CollectionId'" -ErrorAction Stop |
            Select-Object ResourceID, Name, @{n = 'Client'; e = { $_.IsClient } }
    }
}
