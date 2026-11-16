# Collection membership and bulk tools (roadmap D9, D14).

function Invoke-AZRBulk {
    <#
    .SYNOPSIS
        Runs one AZR function against many computers with throttled concurrency and returns flat result rows.
    .DESCRIPTION
        -Function must be an exported AZR function (name pattern Verb-AZRNoun) that takes -ComputerName. Its output rows are
        returned as-is; a computer whose call threw gets one row with Success = $false and the error text.
    .EXAMPLE
        Invoke-AZRBulk -ComputerName PC01, PC02 -Function Invoke-AZRClientAction -Parameter @{ Action = 'HardwareInventory' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ComputerName,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]+-AZR[A-Za-z]+$')][string]$Function,
        [hashtable]$Parameter = @{},
        [int]$ThrottleLimit = 0
    )
    foreach ($n in $ComputerName) { $null = Assert-AZRComputerName -ComputerName $n }
    if (-not (Get-Command -Name $Function -Module AZR.RightClickTools -ErrorAction SilentlyContinue)) { throw "Unknown AZR function '$Function'." }
    $runs = Invoke-AZRParallel -Target $ComputerName -ThrottleLimit $ThrottleLimit -ProgressActivity "AZR: $Function" -ArgumentList @($Function, $Parameter) -ScriptBlock {
        param($Target, $Fn, $Params)
        & $Fn -ComputerName $Target @Params
    }
    foreach ($r in $runs) {
        if ($r.Success) { $r.Output }
        else { [pscustomobject]@{ ComputerName = $r.Target; Success = $false; Message = $r.Error } }
    }
}

function Get-AZRDeviceCollection {
    <# Lists the collections a device is a member of (device name -> ResourceID -> SMS_FullCollectionMembership -> SMS_Collection). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$ComputerName
    )
    $null = Assert-AZRComputerName -ComputerName $SiteServer
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $SiteCode = Assert-AZRSiteCode -SiteCode $SiteCode
    Invoke-AZRWithCimSession -ComputerName $SiteServer -ScriptBlock {
        param($s)
        $ns = "root\sms\site_$SiteCode"
        $dev = Get-AZRCimQuery -Session $s -Namespace $ns -Query (New-AZRWql -Class SMS_R_System -Property Name, ResourceID -Equals @{ Name = $ComputerName }) | Select-Object -First 1
        if (-not $dev) { throw "Device '$ComputerName' not found in site $SiteCode." }
        $rid = [int64]$dev.ResourceID
        $q = "SELECT CollectionID, Name, CollectionType, MemberCount FROM SMS_Collection WHERE CollectionID IN (SELECT CollectionID FROM SMS_FullCollectionMembership WHERE ResourceID = $rid)"
        Get-AZRCimQuery -Session $s -Namespace $ns -Query $q | Sort-Object Name | ForEach-Object {
            [pscustomobject]@{ ComputerName = $ComputerName; CollectionID = $_.CollectionID; Name = $_.Name; MemberCount = $_.MemberCount }
        }
    }
}

function Add-AZRDeviceToCollection {
    <#
    .SYNOPSIS
        Adds a device to a device collection with a direct membership rule (SMS_CollectionRuleDirect).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string[]]$ComputerName
    )
    Set-AZRCollectionRule -Mode Add -SiteServer $SiteServer -SiteCode $SiteCode -CollectionId $CollectionId -ComputerName $ComputerName -WhatIf:$WhatIfPreference
}

function Remove-AZRDeviceFromCollection {
    <# Removes the direct membership rule for a device. Query-based rules are not touched. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string[]]$ComputerName
    )
    Set-AZRCollectionRule -Mode Remove -SiteServer $SiteServer -SiteCode $SiteCode -CollectionId $CollectionId -ComputerName $ComputerName -WhatIf:$WhatIfPreference
}

function Set-AZRCollectionRule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('Add', 'Remove')][string]$Mode,
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$CollectionId,
        [Parameter(Mandatory)][string[]]$ComputerName
    )
    $null = Assert-AZRComputerName -ComputerName $SiteServer
    $SiteCode = Assert-AZRSiteCode -SiteCode $SiteCode
    $CollectionId = Assert-AZRCollectionId -CollectionId $CollectionId
    foreach ($n in $ComputerName) { $null = Assert-AZRComputerName -ComputerName $n }
    Invoke-AZRWithCimSession -ComputerName $SiteServer -ScriptBlock {
        param($s)
        $ns = "root\sms\site_$SiteCode"
        $coll = Get-AZRCim -Session $s -Namespace $ns -ClassName SMS_Collection -Filter "CollectionID = '$CollectionId'" | Select-Object -First 1
        if (-not $coll) { throw "Collection $CollectionId not found." }
        if ($coll.CollectionType -ne 2) { throw "Collection $CollectionId is not a device collection." }
        foreach ($n in $ComputerName) {
            $row = [ordered]@{ ComputerName = $n; CollectionID = $CollectionId; Action = "$Mode direct rule"; Success = $false; Message = '' }
            try {
                $dev = Get-AZRCimQuery -Session $s -Namespace $ns -Query (New-AZRWql -Class SMS_R_System -Property Name, ResourceID -Equals @{ Name = $n }) | Select-Object -First 1
                if (-not $dev) { throw "Device '$n' not found in site $SiteCode." }
                if ($PSCmdlet.ShouldProcess("$n -> $CollectionId", "$Mode direct membership rule")) {
                    $args2 = @{ ResourceClassName = 'SMS_R_System'; ResourceID = [uint32]$dev.ResourceID; RuleName = $n }
                    if ($Mode -eq 'Add') {
                        $rule = New-AZRCollectionRuleObject -Session $s -Namespace $ns -Property $args2
                        $null = Invoke-AZRCimOnInstance -Session $s -InputObject $coll -MethodName AddMembershipRule -Arguments @{ collectionRule = $rule }
                    }
                    else {
                        $rule = New-AZRCollectionRuleObject -Session $s -Namespace $ns -Property $args2
                        $null = Invoke-AZRCimOnInstance -Session $s -InputObject $coll -MethodName DeleteMembershipRule -Arguments @{ collectionRule = $rule }
                    }
                    $row.Success = $true; $row.Message = 'Done (membership updates after the next collection evaluation)'
                    Write-AZRLog -Message "$Mode direct rule: $n in $CollectionId"
                }
            }
            catch { $row.Message = $_.Exception.Message }
            [pscustomobject]$row
        }
    }
}

function New-AZRCollectionRuleObject {
    <# Creates a client-side SMS_CollectionRuleDirect object for AddMembershipRule/DeleteMembershipRule. #>
    [CmdletBinding()]
    param($Session, [string]$Namespace, [hashtable]$Property)
    New-CimInstance -ClientOnly -Namespace $Namespace -ClassName SMS_CollectionRuleDirect -Property $Property
}

function Get-AZRCollectionSummary {
    <#
    .SYNOPSIS
        Collection health summary: name, member count, how many are clients, active, and when membership last changed.
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
        $ns = "root\sms\site_$SiteCode"
        $coll = Get-AZRCim -Session $s -Namespace $ns -ClassName SMS_Collection -Filter "CollectionID = '$CollectionId'" | Select-Object -First 1
        if (-not $coll) { throw "Collection $CollectionId not found." }
        $members = @(Get-AZRCim -Session $s -Namespace $ns -ClassName SMS_FullCollectionMembership -Filter "CollectionID = '$CollectionId'")
        $clients = @($members | Where-Object { $_.IsClient })
        $active = @($members | Where-Object { $_.IsActive })
        [pscustomobject]@{
            CollectionID      = $CollectionId
            Name              = $coll.Name
            Members           = $members.Count
            WithClient        = $clients.Count
            WithoutClient     = $members.Count - $clients.Count
            ActiveClients     = $active.Count
            InactiveClients   = $clients.Count - $active.Count
            LimitingCollection = $coll.LimitToCollectionID
            LastMemberChange  = $coll.LastMemberChangeTime
        }
    }
}
