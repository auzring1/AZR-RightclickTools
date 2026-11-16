function Assert-AZRComputerName {
    <#
    .SYNOPSIS
        Rejects anything that is not a plain hostname/FQDN/IPv4 so values from the console
        can never be interpreted as extra command-line arguments or shell syntax.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ComputerName)
    if ($ComputerName -notmatch '^[A-Za-z0-9]([A-Za-z0-9\-\.]{0,251}[A-Za-z0-9])?$') {
        throw "Invalid computer name: '$ComputerName'"
    }
    $ComputerName
}

function Assert-AZRCollectionId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$CollectionId)
    if ($CollectionId -notmatch '^[A-Za-z0-9]{3}[0-9A-Fa-f]{5}$') { throw "Invalid collection ID: '$CollectionId'" }
    $CollectionId
}

function Assert-AZRSiteCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$SiteCode)
    if ($SiteCode -notmatch '^[A-Za-z0-9]{3}$') { throw "Invalid site code: '$SiteCode'" }
    $SiteCode.ToUpper()
}
