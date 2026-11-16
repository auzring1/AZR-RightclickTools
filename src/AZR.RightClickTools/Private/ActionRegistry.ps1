# Handlers for every menu action. Contract: a script block taking one context object:
#   Id, ComputerName (Device scope), Names + Members (Collection scope), CollectionId, SiteServer, SiteCode, Reason.
# Policy (confirmation, audit, validation) lives in Invoke-AZRAction; handlers only do the work and show results.

function ConvertTo-AZRPropertyRow {
    <# Turns one wide object into Property/Value rows for a readable grid. #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)]$InputObject)
    process { foreach ($p in $InputObject.PSObject.Properties) { [pscustomobject]@{ Property = $p.Name; Value = $(if ($p.Value -is [securestring]) { '[hidden]' } else { $p.Value }) } } }
}

function Get-AZRActionTable {
    $t = @{}

    # Client schedule actions (every entry of Get-AZRClientActionList is callable, even those not in the menu).
    $schedule = @{
        Device     = { param($c) Invoke-AZRClientAction -ComputerName $c.ComputerName -Action $c.Id | Show-AZRResult -Title "AZR: $($c.Id) on $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Invoke-AZRClientAction -Parameter @{ Action = $c.Id } | Show-AZRResult -Title "AZR: $($c.Id) ($($c.CollectionId))" }
    }
    foreach ($a in Get-AZRClientActionList) { $t[$a.Name] = $schedule }
    $t['RefreshUpdateCompliance'] = @{
        Device     = { param($c) Update-AZRUpdateCompliance -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Update compliance: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Update-AZRUpdateCompliance -Parameter @{ Confirm = $false } | Show-AZRResult -Title "Update compliance ($($c.CollectionId))" }
    }

    # Client tools
    $t['ClientHealthCheck'] = @{
        Device     = { param($c) Invoke-AZRClientHealthCheck -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Health check: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Invoke-AZRClientHealthCheck -Parameter @{ Confirm = $false } | Show-AZRResult -Title "Health check ($($c.CollectionId))" }
    }
    $t['ClientCache'] = @{ Device = { param($c) Get-AZRClientCache -ComputerName $c.ComputerName | Show-AZRResult -Title "Client cache: $($c.ComputerName)" } }
    $t['ClearClientCache'] = @{
        Device     = { param($c) Clear-AZRClientCache -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Clear cache: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Clear-AZRClientCache -Parameter @{ Confirm = $false } | Show-AZRResult -Title "Clear cache ($($c.CollectionId))" }
    }
    $t['SetClientCacheSize'] = @{
        Device     = { param($c) $mb = Read-AZRCacheSize; if ($mb) { Set-AZRClientCacheSize -ComputerName $c.ComputerName -SizeMB $mb -Confirm:$false | Show-AZRResult -Title "Cache size: $($c.ComputerName)" } }
        Collection = { param($c) $mb = Read-AZRCacheSize; if ($mb) { Invoke-AZRBulk -ComputerName $c.Names -Function Set-AZRClientCacheSize -Parameter @{ SizeMB = $mb; Confirm = $false } | Show-AZRResult -Title "Cache size ($($c.CollectionId))" } }
    }
    $t['RestartCcmExec'] = @{ Device = { param($c) Restart-AZRService -ComputerName $c.ComputerName -Name 'CcmExec' -Confirm:$false | Show-AZRResult -Title "CcmExec: $($c.ComputerName)" } }
    $t['StopCcmExec'] = @{ Device = { param($c) Set-AZRServiceState -ComputerName $c.ComputerName -Name 'CcmExec' -State Stop -Confirm:$false | Show-AZRResult -Title "CcmExec: $($c.ComputerName)" } }
    $t['RepairClient'] = @{
        Device     = { param($c) Repair-AZRClient -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Repair client: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Repair-AZRClient -Parameter @{ Confirm = $false } | Show-AZRResult -Title "Repair client ($($c.CollectionId))" }
    }
    $t['UninstallClient'] = @{
        Device     = { param($c) Uninstall-AZRClient -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Uninstall client: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Uninstall-AZRClient -Parameter @{ Confirm = $false } | Show-AZRResult -Title "Uninstall client ($($c.CollectionId))" }
    }

    # Power and messages
    $t['WakeOnLan'] = @{
        Device     = { param($c) Get-AZRDeviceMac -SiteServer $c.SiteServer -SiteCode $c.SiteCode -ComputerName $c.ComputerName | Send-AZRWolForDevice | Show-AZRResult -Title "Wake-on-LAN: $($c.ComputerName)" }
        Collection = { param($c) Get-AZRDeviceMac -SiteServer $c.SiteServer -SiteCode $c.SiteCode -CollectionId $c.CollectionId | Send-AZRWolForDevice | Show-AZRResult -Title "Wake-on-LAN ($($c.CollectionId))" }
    }
    $t['Restart'] = @{
        Device     = { param($c) Restart-AZRComputer -ComputerName $c.ComputerName -DelaySeconds 60 -Confirm:$false | Show-AZRResult -Title "Restart: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Restart-AZRComputer -Parameter @{ DelaySeconds = 60; Confirm = $false } | Show-AZRResult -Title "Restart ($($c.CollectionId))" }
    }
    $t['Shutdown'] = @{
        Device     = { param($c) Stop-AZRComputer -ComputerName $c.ComputerName -DelaySeconds 60 -Confirm:$false | Show-AZRResult -Title "Shutdown: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Stop-AZRComputer -Parameter @{ DelaySeconds = 60; Confirm = $false } | Show-AZRResult -Title "Shutdown ($($c.CollectionId))" }
    }
    $t['AbortShutdown'] = @{
        Device     = { param($c) Stop-AZRPendingShutdown -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Cancel shutdown: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Stop-AZRPendingShutdown -Parameter @{ Confirm = $false } | Show-AZRResult -Title "Cancel shutdown ($($c.CollectionId))" }
    }
    $t['GpUpdate'] = @{
        Device     = { param($c) Invoke-AZRGpUpdate -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "gpupdate: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Invoke-AZRGpUpdate -Parameter @{ Confirm = $false } | Show-AZRResult -Title "gpupdate ($($c.CollectionId))" }
    }
    $t['SendNotification'] = @{
        Device     = { param($c) $m = Read-AZRNotificationText; if ($m) { Send-AZRNotification -ComputerName $c.ComputerName -Message $m -Confirm:$false | Show-AZRResult -Title "Message: $($c.ComputerName)" } }
        Collection = { param($c) $m = Read-AZRNotificationText; if ($m) { Invoke-AZRBulk -ComputerName $c.Names -Function Send-AZRNotification -Parameter @{ Message = $m; Confirm = $false } | Show-AZRResult -Title "Message ($($c.CollectionId))" } }
    }

    # Collections and status
    $t['ShowCollections'] = @{ Device = { param($c) Get-AZRDeviceCollection -SiteServer $c.SiteServer -SiteCode $c.SiteCode -ComputerName $c.ComputerName | Show-AZRResult -Title "Collections of $($c.ComputerName)" } }
    $t['AddToCollection'] = @{ Device = { param($c) $id = Read-AZRCollectionId; if ($id) { Add-AZRDeviceToCollection -SiteServer $c.SiteServer -SiteCode $c.SiteCode -CollectionId $id -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Add to $id" } } }
    $t['RemoveFromCollection'] = @{ Device = { param($c) $id = Read-AZRCollectionId; if ($id) { Remove-AZRDeviceFromCollection -SiteServer $c.SiteServer -SiteCode $c.SiteCode -CollectionId $id -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Remove from $id" } } }
    $t['StatusMessages'] = @{ Device = { param($c) Get-AZRStatusMessage -SiteServer $c.SiteServer -SiteCode $c.SiteCode -ComputerName $c.ComputerName | Show-AZRResult -Title "Status messages: $($c.ComputerName)" } }
    $t['CollectionSummary'] = @{ Collection = { param($c) Get-AZRCollectionSummary -SiteServer $c.SiteServer -SiteCode $c.SiteCode -CollectionId $c.CollectionId | ConvertTo-AZRPropertyRow | Show-AZRResult -Title "Collection summary: $($c.CollectionId)" } }
    $t['ExportMembers'] = @{ Collection = { param($c) $p = $c.Members | Export-AZRResult -Format Csv -Name "members-$($c.CollectionId)"; Show-AZRMessage -Message "Exported $(@($c.Members).Count) member(s) to:`n$p" } }
    $t['DeleteFromConfigMgr'] = @{ Device = { param($c) Remove-AZRDeviceFromConfigMgr -SiteServer $c.SiteServer -SiteCode $c.SiteCode -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "Delete from ConfigMgr: $($c.ComputerName)" } }

    # Remote tools
    $t['Ping'] = @{
        Device     = { param($c) Test-AZRConnection -ComputerName $c.ComputerName | Show-AZRResult -Title "Ping: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Test-AZRConnection -Parameter @{ Count = 1 } | Show-AZRResult -Title "Ping ($($c.CollectionId))" }
    }
    $t['Rdp'] = @{ Device = { param($c) Start-AZRRdp -ComputerName $c.ComputerName } }
    $t['RdpAdmin'] = @{ Device = { param($c) Start-AZRRdp -ComputerName $c.ComputerName -Admin } }
    $t['RemoteShell'] = @{ Device = { param($c) Start-AZRRemoteShell -ComputerName $c.ComputerName } }
    $t['BrowseC'] = @{ Device = { param($c) Open-AZRCDrive -ComputerName $c.ComputerName } }
    $t['ClientLogs'] = @{ Device = { param($c) Open-AZRClientLogs -ComputerName $c.ComputerName } }
    $t['Services'] = @{ Device = { param($c) Get-AZRService -ComputerName $c.ComputerName | Show-AZRResult -Title "Services: $($c.ComputerName)" } }
    $t['EventLog'] = @{ Device = { param($c) Get-AZREventLog -ComputerName $c.ComputerName | Show-AZRResult -Title "Event log: $($c.ComputerName)" } }
    $t['ComputerManagement'] = @{ Device = { param($c) Start-AZRComputerManagement -ComputerName $c.ComputerName } }
    $t['SystemInfo'] = @{ Device = { param($c) Show-AZRSystemInfo -ComputerName $c.ComputerName } }
    $t['DeviceInfo'] = @{ Device = { param($c) Get-AZRDeviceInfo -ComputerName $c.ComputerName | ConvertTo-AZRPropertyRow | Show-AZRResult -Title "Device info: $($c.ComputerName)" } }

    # Security
    $t['BitLockerDetail'] = @{ Device = { param($c) Get-AZRBitLockerDetail -ComputerName $c.ComputerName | Show-AZRResult -Title "BitLocker: $($c.ComputerName)" } }
    $t['BitLockerRecoveryKey'] = @{ Device = { param($c) Show-AZRBitLockerRecoveryKey -ComputerName $c.ComputerName -Reason $c.Reason } }
    $t['LapsStatus'] = @{
        Device     = { param($c) Get-AZRLapsStatus -ComputerName $c.ComputerName | Show-AZRResult -Title "LAPS status: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Get-AZRLapsStatus | Show-AZRResult -Title "LAPS status ($($c.CollectionId))" }
    }
    $t['LapsPassword'] = @{ Device = { param($c) Show-AZRLapsPassword -ComputerName $c.ComputerName -Reason $c.Reason } }
    $t['LapsRotate'] = @{ Device = { param($c) Set-AZRLapsExpiration -ComputerName $c.ComputerName -Confirm:$false | Show-AZRResult -Title "LAPS rotation: $($c.ComputerName)" } }
    $t['WindowsSecurity'] = @{ Device = { param($c) Show-AZRWindowsSecurity -ComputerName $c.ComputerName } }
    $t['LocalAdmins'] = @{
        Device     = { param($c) Get-AZRLocalAdministrator -ComputerName $c.ComputerName | Show-AZRResult -Title "Local administrators: $($c.ComputerName)" }
        Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Get-AZRLocalAdministrator | Show-AZRResult -Title "Local administrators ($($c.CollectionId))" }
    }
    $t['BitLockerCompliance'] = @{ Collection = { param($c) Invoke-AZRBulk -ComputerName $c.Names -Function Get-AZRBitLockerCompliance | Show-AZRResult -Title "BitLocker compliance ($($c.CollectionId))" } }
    $t
}

function Send-AZRWolForDevice {
    <# Pipeline helper: takes Get-AZRDeviceMac rows and sends one magic packet per valid MAC. #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)]$InputObject)
    process {
        $macs = @($InputObject.MacAddress | Where-Object { $_ })
        $sent = 0
        foreach ($m in $macs) {
            try { $null = Assert-AZRMacAddress -MacAddress $m; $null = Send-AZRWakeOnLan -MacAddress $m -Confirm:$false; $sent++ } catch { Write-AZRLog -Level Warn -Message "Skipped MAC '$m' for $($InputObject.ComputerName): $($_.Exception.Message)" }
        }
        [pscustomobject]@{ ComputerName = $InputObject.ComputerName; Success = ($sent -gt 0); Message = if ($sent) { "Magic packet sent for $sent MAC address(es)" } else { 'No usable MAC address found in ConfigMgr' } }
    }
}

function Read-AZRCacheSize {
    $r = Read-AZRInput -Title 'Client cache size' -Prompt 'New client cache size in MB (1 to 1048576):' -Default '10240'
    if (-not $r) { return $null }
    $n = 0
    if (-not [int]::TryParse($r.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt 1048576) { throw "'$r' is not a valid cache size." }
    $n
}

function Read-AZRNotificationText {
    $r = Read-AZRInput -Title 'Message to user' -Prompt 'Message text (letters, digits and basic punctuation):'
    if (-not $r) { return $null }
    Assert-AZRMessageText -Text $r
}

function Read-AZRCollectionId {
    $r = Read-AZRInput -Title 'Collection' -Prompt 'Device collection ID (for example ABC00012):'
    if (-not $r) { return $null }
    Assert-AZRCollectionId -CollectionId $r.Trim()
}
