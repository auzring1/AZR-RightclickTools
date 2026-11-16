function Get-AZRCollectionMember {
    <#
    .SYNOPSIS
        Lists the member devices of a collection using the SMS Provider (CIM) or, when the UseAdminService
        setting is on, the Administration Service. Falls back to the SMS Provider if the AdminService call fails.
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
    if ((Get-AZRSettings).UseAdminService) {
        try {
            return Invoke-AZRAdminService -Server $SiteServer -Path 'wmi/SMS_FullCollectionMembership' -Query @{ '$filter' = "CollectionID eq '$CollectionId'" } |
                ForEach-Object { [pscustomobject]@{ ResourceID = $_.ResourceID; Name = $_.Name; Client = $_.IsClient } }
        }
        catch { Write-AZRLog -Level Warn -Message "AdminService member query failed, using SMS Provider: $($_.Exception.Message)" }
    }
    Invoke-AZRWithCimSession -ComputerName $SiteServer -ScriptBlock {
        param($s)
        Get-AZRCim -Session $s -Namespace "root\sms\site_$SiteCode" -ClassName SMS_FullCollectionMembership -Filter "CollectionID = '$CollectionId'" |
            Select-Object ResourceID, Name, @{n = 'Client'; e = { $_.IsClient } }
    }
}
