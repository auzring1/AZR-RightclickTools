function Invoke-AZRAction {
    <#
    .SYNOPSIS
        Single entry point used by the ConfigMgr console extension. Dispatches an action name
        to the right tool for a device (ComputerName) or a collection (CollectionId).
    .DESCRIPTION
        Action names are either a client action name (see Get-AZRClientActionList) or one of:
        Ping, DeviceInfo, Services, RestartCcmExec, EventLog, BrowseC, ClientLogs, Rdp, RdpAdmin,
        RemoteShell, ComputerManagement.
        Collection targets support client actions and Ping.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$ComputerName,
        [string]$CollectionId,
        [string]$SiteServer,
        [string]$SiteCode
    )
    $deviceOnly = @('DeviceInfo', 'Services', 'RestartCcmExec', 'EventLog', 'BrowseC', 'ClientLogs', 'Rdp', 'RdpAdmin', 'RemoteShell', 'ComputerManagement')
    $clientActions = (Get-AZRClientActionList).Name
    $known = $clientActions + $deviceOnly + 'Ping'
    if ($Action -notin $known) { throw "Unknown action '$Action'" }

    try {
        if ($CollectionId) {
            if ($Action -in $deviceOnly) { throw "Action '$Action' can only run against a single device." }
            $members = @(Get-AZRCollectionMember -SiteServer $SiteServer -SiteCode $SiteCode -CollectionId $CollectionId |
                    Where-Object { $_.Name })
            if (-not $members) { Show-AZRMessage -Message 'The collection has no members.' -Icon Warning; return }
            if (-not (Confirm-AZRAction -Message "Run '$Action' on $($members.Count) device(s) in collection ${CollectionId}?")) { return }
            Write-AZRLog -Message "Collection run: $Action on $($members.Count) devices in $CollectionId"
            $names = $members.Name
            $results = if ($Action -eq 'Ping') { $names | Test-AZRConnection -Count 1 }
                       else { Invoke-AZRClientAction -ComputerName $names -Action $Action }
            $results | Show-AZRResult -Title "AZR: $Action ($CollectionId)"
            return
        }

        if (-not $ComputerName) { throw 'A ComputerName or CollectionId is required.' }
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        Write-AZRLog -Message "Action $Action on $ComputerName"

        switch ($Action) {
            'Ping'              { Test-AZRConnection -ComputerName $ComputerName | Show-AZRResult -Title "Ping: $ComputerName" }
            'DeviceInfo'        { Get-AZRDeviceInfo -ComputerName $ComputerName | Format-List | Out-String | ForEach-Object { Show-AZRMessage -Title "Device info: $ComputerName" -Message $_ } }
            'Services'          { Get-AZRService -ComputerName $ComputerName | Show-AZRResult -Title "Services: $ComputerName" }
            'RestartCcmExec'    {
                if (Confirm-AZRAction -Message "Restart the ConfigMgr client service (CcmExec) on $ComputerName?") {
                    Restart-AZRService -ComputerName $ComputerName -Name 'CcmExec' -Confirm:$false | Show-AZRResult -Title "CcmExec: $ComputerName"
                }
            }
            'EventLog'          { Get-AZREventLog -ComputerName $ComputerName | Show-AZRResult -Title "Event log: $ComputerName" }
            'BrowseC'           { Open-AZRCDrive -ComputerName $ComputerName }
            'ClientLogs'        { Open-AZRClientLogs -ComputerName $ComputerName }
            'Rdp'               { Start-AZRRdp -ComputerName $ComputerName }
            'RdpAdmin'          { Start-AZRRdp -ComputerName $ComputerName -Admin }
            'RemoteShell'       { Start-AZRRemoteShell -ComputerName $ComputerName }
            'ComputerManagement'{ Start-AZRComputerManagement -ComputerName $ComputerName }
            default             { Invoke-AZRClientAction -ComputerName $ComputerName -Action $Action | Show-AZRResult -Title "AZR: $Action on $ComputerName" }
        }
    }
    catch {
        Write-AZRLog -Level Error -Message "Action $Action failed: $($_.Exception.Message)"
        Show-AZRMessage -Message $_.Exception.Message -Title 'AZR-RightClickTools error' -Icon Error
    }
}
