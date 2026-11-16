# SMS Provider helpers: status messages and quick queries (roadmap D10), delete device (D11, ConfigMgr part).

function Invoke-AZRSmsQuery {
    <#
    .SYNOPSIS
        Quick query against the SMS Provider. The WQL is built from a class name, property names and equality /
        greater-or-equal filters that are all validated; raw WQL text is not accepted.
    .EXAMPLE
        Invoke-AZRSmsQuery -SiteServer cm01 -SiteCode ABC -Class SMS_R_System -Property Name,ResourceID -Equals @{ Name = 'PC01' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][ValidatePattern('^SMS_[A-Za-z0-9_]{1,60}$')][string]$Class,
        [string[]]$Property = @('*'),
        [System.Collections.IDictionary]$Equals = @{},
        [hashtable]$GreaterOrEqual = @{},
        [ValidateRange(1, 5000)][int]$MaxRows = 500
    )
    $null = Assert-AZRComputerName -ComputerName $SiteServer
    $SiteCode = Assert-AZRSiteCode -SiteCode $SiteCode
    $query = New-AZRWql -Class $Class -Property $Property -Equals $Equals -GreaterOrEqual $GreaterOrEqual
    Invoke-AZRWithCimSession -ComputerName $SiteServer -ScriptBlock {
        param($s)
        Get-AZRCimQuery -Session $s -Namespace "root\sms\site_$SiteCode" -Query $query | Select-Object -First $MaxRows
    }
}

function Get-AZRStatusMessage {
    <#
    .SYNOPSIS
        Recent status messages for a device (SMS_StatMsgWithInsStrings): time, severity, component, message ID and insert strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$ComputerName,
        [ValidateRange(1, 720)][int]$Hours = 24,
        [ValidateSet('All', 'Error', 'Warning', 'Informational')][string]$Severity = 'All',
        [ValidateRange(1, 5000)][int]$MaxRows = 500
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $filter = @{ MachineName = $ComputerName }
    $since = @{ Time = (Get-Date).AddHours(-$Hours) }
    $rows = Invoke-AZRSmsQuery -SiteServer $SiteServer -SiteCode $SiteCode -Class SMS_StatMsgWithInsStrings `
        -Property RecordID, Time, Severity, MessageID, ModuleName, Component, MachineName, InsString1, InsString2, InsString3 `
        -Equals $filter -GreaterOrEqual $since -MaxRows $MaxRows
    $sevName = { param($v) switch ([uint32]$v -shr 30) { 3 { 'Error' } 2 { 'Warning' } 1 { 'Informational' } default { 'Unknown' } } }
    $rows | ForEach-Object {
        [pscustomobject]@{
            Time      = $_.Time
            Severity  = & $sevName $_.Severity
            Component = $_.Component
            MessageID = $_.MessageID
            Module    = $_.ModuleName
            Details   = (@($_.InsString1, $_.InsString2, $_.InsString3) | Where-Object { $_ }) -join ' | '
        }
    } | Where-Object { $Severity -eq 'All' -or $_.Severity -eq $Severity } | Sort-Object Time -Descending
}

function Remove-AZRDeviceFromConfigMgr {
    <#
    .SYNOPSIS
        Deletes the device record(s) from ConfigMgr (SMS_R_System). The device object, its history and collection memberships
        go away; it reappears if discovery finds it again. Destructive.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName
    )
    begin {
        $null = Assert-AZRComputerName -ComputerName $SiteServer
        $SiteCode = Assert-AZRSiteCode -SiteCode $SiteCode
    }
    process {
        foreach ($n in $ComputerName) {
            $null = Assert-AZRComputerName -ComputerName $n
            $row = [ordered]@{ ComputerName = $n; Action = 'Delete from ConfigMgr'; Success = $false; Message = '' }
            try {
                Invoke-AZRWithCimSession -ComputerName $SiteServer -ScriptBlock {
                    param($s)
                    $q = New-AZRWql -Class SMS_R_System -Equals @{ Name = $n }
                    $devs = @(Get-AZRCimQuery -Session $s -Namespace "root\sms\site_$SiteCode" -Query $q)
                    if (-not $devs.Count) { throw "Device '$n' not found." }
                    if ($devs.Count -gt 1) { throw "Device name '$n' matches $($devs.Count) records; refusing to delete several at once." }
                    if ($PSCmdlet.ShouldProcess($n, 'Delete device record from ConfigMgr')) {
                        Remove-AZRCimInstance -Session $s -InputObject $devs[0]
                        $row.Success = $true; $row.Message = 'Deleted'
                        Write-AZRLog -Message "Deleted $n from ConfigMgr site $SiteCode"
                    }
                }
            }
            catch { $row.Message = $_.Exception.Message }
            [pscustomobject]$row
        }
    }
}
