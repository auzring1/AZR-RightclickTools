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
    $CollectionId.ToUpper()
}

function Assert-AZRSiteCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$SiteCode)
    if ($SiteCode -notmatch '^[A-Za-z0-9]{3}$') { throw "Invalid site code: '$SiteCode'" }
    $SiteCode.ToUpper()
}

function Assert-AZRPackageId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$PackageId)
    if ($PackageId -notmatch '^[A-Za-z0-9]{3}[0-9A-Fa-f]{5}$') { throw "Invalid package ID: '$PackageId'" }
    $PackageId.ToUpper()
}

function Assert-AZRMacAddress {
    <#
    .SYNOPSIS
        Accepts AA:BB:CC:DD:EE:FF, AA-BB-..., or AABBCCDDEEFF and returns 12 upper-case hex digits.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$MacAddress)
    if ($MacAddress -notmatch '^([0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}$' -and $MacAddress -notmatch '^[0-9A-Fa-f]{12}$') {
        throw "Invalid MAC address: '$MacAddress'"
    }
    ($MacAddress -replace '[:\-]', '').ToUpper()
}

function Assert-AZRServiceName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9_\-\$\.]{1,256}$') { throw "Invalid service name: '$Name'" }
    $Name
}

function Assert-AZRProductCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ProductCode)
    if ($ProductCode -notmatch '^\{[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}$') { throw "Invalid MSI product code: '$ProductCode'" }
    $ProductCode.ToUpper()
}

function Assert-AZRCredentialName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9_\-]{1,64}$') { throw "Invalid credential name: '$Name' (letters, digits, '_' and '-' only)" }
    $Name
}

function Assert-AZRMessageText {
    <#
    .SYNOPSIS
        Allow-list for free text that ends up inside a fixed command template (msg.exe, shutdown /c).
        Letters, digits, spaces and basic punctuation only, so no quoting, expansion or pipe syntax is possible.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [int]$MaxLength = 250)
    $t = $Text.Trim()
    if ($t.Length -lt 1 -or $t.Length -gt $MaxLength) { throw "Message must be 1 to $MaxLength characters." }
    if ($t -notmatch "^[\p{L}\p{N} \.,:;!\?\(\)\-_'/]+$") {
        throw 'Message may only contain letters, digits, spaces and . , : ; ! ? ( ) - _ '' /'
    }
    $t
}

function Assert-AZRReason {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Reason)
    $r = $Reason.Trim()
    if ($r.Length -lt 3 -or $r.Length -gt 200 -or $r -match '[\x00-\x1F]') { throw 'A reason of 3 to 200 characters (no control characters) is required.' }
    $r
}

function Assert-AZRWqlValue {
    <#
    .SYNOPSIS
        Validates a value that will be embedded in single quotes in a WQL filter. Quotes and wildcards are not allowed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9 _\-\.@\\:]{1,128}$') { throw "Unsafe value for a WQL filter: '$Value'" }
    $Value
}
