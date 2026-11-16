function Invoke-AZRAction {
    <#
    .SYNOPSIS
        Single entry point used by the ConfigMgr console extension. Validates the target, applies the confirmation policy
        for the action's risk class, runs the handler and writes an audit entry.
    .DESCRIPTION
        Action ids come from the manifest (src\Actions.psd1) and the client action list. A device is passed as -ComputerName,
        a collection as -CollectionId (with -SiteServer/-SiteCode so members can be resolved).
        Confirmation by risk: Read none (bulk: count prompt), Change Yes/No, Destructive typed device name or count,
        Secret Yes/No plus reason. Bulk work runs through the throttled parallel runner (MaxParallel setting).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$ComputerName,
        [string]$CollectionId,
        [string]$SiteServer,
        [string]$SiteCode
    )
    $table = Get-AZRActionTable
    if (-not $table.ContainsKey($Action)) { throw "Unknown action '$Action'" }
    $def = Get-AZRActionDefinition -Id $Action
    if (-not $def) { $def = [pscustomobject]@{ Id = $Action; Name = $Action; Risk = 'Change'; Confirm = 'None' } }
    $scope = if ($CollectionId) { 'Collection' } else { 'Device' }
    $risk = $def.Risk
    $targets = @()

    try {
        if (-not $table[$Action].ContainsKey($scope)) { throw "Action '$Action' can only run against a single device." }
        $ctx = [ordered]@{ Id = $Action; ComputerName = $null; Names = @(); Members = @(); CollectionId = $null; SiteServer = $SiteServer; SiteCode = $SiteCode; Reason = $null; Scope = $scope }
        if ($scope -eq 'Collection') {
            $ctx.CollectionId = Assert-AZRCollectionId -CollectionId $CollectionId
            $ctx.Members = @(Get-AZRCollectionMember -SiteServer $SiteServer -SiteCode $SiteCode -CollectionId $ctx.CollectionId | Where-Object { $_.Name })
            if (-not $ctx.Members) { Show-AZRMessage -Message 'The collection has no members.' -Icon Warning; return }
            $ctx.Names = @($ctx.Members.Name)
            $targets = $ctx.Names
        }
        else {
            if (-not $ComputerName) { throw 'A ComputerName or CollectionId is required.' }
            $ctx.ComputerName = Assert-AZRComputerName -ComputerName $ComputerName
            $targets = @($ctx.ComputerName)
        }

        $label = if ($def.Name) { ($def.Name -replace '&&', '&') } else { $Action }
        $approval = Confirm-AZRRisk -Action $label -Risk $risk -Scope $scope -Target $targets -Confirm $def.Confirm
        if (-not $approval.Approved) {
            Write-AZRAudit -Action $Action -Target $targets -Risk $risk -Outcome Cancelled -Message "Scope $scope"
            Write-AZRLog -Message "Action $Action cancelled by user ($scope, $($targets.Count) target(s))"
            return
        }
        $ctx.Reason = $approval.Reason
        Write-AZRLog -Message "Action $Action ($risk) on $($targets.Count) target(s): $($targets[0])$(if ($targets.Count -gt 1) { ' ...' })"

        & $table[$Action][$scope] ([pscustomobject]$ctx)

        # Secret handlers write their own audit entry (key counts and reason, never the secret).
        if ($risk -ne 'Secret') { Write-AZRAudit -Action $Action -Target $targets -Risk $risk -Outcome Success -Message "Scope $scope" }
    }
    catch {
        Write-AZRLog -Level Error -Message "Action $Action failed: $($_.Exception.Message)"
        Write-AZRAudit -Action $Action -Target $targets -Risk $risk -Outcome Failure -Message $_.Exception.Message
        Show-AZRMessage -Message $_.Exception.Message -Title 'AZR-RightClickTools error' -Icon Error
    }
}
