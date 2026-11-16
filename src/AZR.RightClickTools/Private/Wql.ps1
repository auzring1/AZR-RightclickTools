function ConvertTo-AZRDmtfDateTime {
    <# Formats a date as a WMI/DMTF string in UTC (yyyyMMddHHmmss.ffffff+000) for use in WQL filters. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetime]$Date)
    $Date.ToUniversalTime().ToString('yyyyMMddHHmmss.ffffff', [System.Globalization.CultureInfo]::InvariantCulture) + '+000'
}

function New-AZRWql {
    <#
    .SYNOPSIS
        Builds a WQL query from validated pieces only. Class and property names are allow-listed patterns,
        values go through Assert-AZRWqlValue and are always quoted. Raw user text is never concatenated.
    .EXAMPLE
        New-AZRWql -Class SMS_R_System -Property Name,ResourceID -Equals @{ Name = 'PC01' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,63}$')][string]$Class,
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,63}$')][string[]]$Property = @('*'),
        [System.Collections.IDictionary]$Equals = @{},
        [hashtable]$GreaterOrEqual = @{}
    )
    $props = if ($Property -contains '*') { '*' } else { $Property -join ', ' }
    $where = New-Object System.Collections.Generic.List[string]
    foreach ($k in ($Equals.Keys | Sort-Object)) {
        if ($k -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$') { throw "Invalid property name in filter: '$k'" }
        $v = $Equals[$k]
        if ($v -is [int] -or $v -is [long]) { $where.Add("$k = $v") }
        else { $where.Add("$k = '" + (Assert-AZRWqlValue -Value ([string]$v)) + "'") }
    }
    foreach ($k in ($GreaterOrEqual.Keys | Sort-Object)) {
        if ($k -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$') { throw "Invalid property name in filter: '$k'" }
        $v = $GreaterOrEqual[$k]
        if ($v -is [datetime]) { $where.Add("$k >= '" + (ConvertTo-AZRDmtfDateTime -Date $v) + "'") }
        elseif ($v -is [int] -or $v -is [long]) { $where.Add("$k >= $v") }
        else { throw "Unsupported value type for '$k'" }
    }
    $q = "SELECT $props FROM $Class"
    if ($where.Count) { $q += ' WHERE ' + ($where -join ' AND ') }
    $q
}
