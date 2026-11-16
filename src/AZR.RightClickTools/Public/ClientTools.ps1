# ConfigMgr client tools (roadmap D2): cache, repair, uninstall, health check, update compliance refresh.

function Get-AZRClientCache {
    <#
    .SYNOPSIS
        Shows the ConfigMgr client cache settings (size, location, in use) and the cached content items.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
        param($s)
        $cfg = Get-AZRCim -Session $s -Namespace 'root\ccm\SoftMgmtAgent' -ClassName CacheConfig | Select-Object -First 1
        if ($cfg) {
            [pscustomobject]@{ ComputerName = $ComputerName; Type = 'Cache'; Item = $cfg.Location; Detail = "Size $($cfg.Size) MB, in use $($cfg.InUse) KB"; ReferenceCount = $null; LastReferenced = $null }
        }
        Get-AZRCim -Session $s -Namespace 'root\ccm\SoftMgmtAgent' -ClassName CacheInfoEx | ForEach-Object {
            [pscustomobject]@{ ComputerName = $ComputerName; Type = 'Content'; Item = $_.Location; Detail = "$($_.ContentId) ($($_.ContentSize) KB)"; ReferenceCount = $_.ReferenceCount; LastReferenced = $_.LastReferenced }
        }
    }
}

function Set-AZRClientCacheSize {
    <#
    .SYNOPSIS
        Changes the ConfigMgr client cache size (MB) through the CacheConfig class.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateRange(1, 1048576)][int]$SizeMB,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $result = [ordered]@{ ComputerName = $ComputerName; Action = "Set cache size to $SizeMB MB"; Success = $false; Message = '' }
    if ($PSCmdlet.ShouldProcess($ComputerName, "Set client cache size to $SizeMB MB")) {
        try {
            Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                param($s)
                $cfg = Get-AZRCim -Session $s -Namespace 'root\ccm\SoftMgmtAgent' -ClassName CacheConfig | Select-Object -First 1
                if (-not $cfg) { throw 'CacheConfig not found; is the ConfigMgr client installed?' }
                $null = Set-AZRCimProperty -Session $s -InputObject $cfg -Property @{ Size = [uint32]$SizeMB }
            }
            $result.Success = $true; $result.Message = 'Changed'
            Write-AZRLog -Message "Cache size on $ComputerName set to $SizeMB MB"
        }
        catch { $result.Message = $_.Exception.Message }
    }
    [pscustomobject]$result
}

function Clear-AZRClientCache {
    <#
    .SYNOPSIS
        Deletes cached content on the client (it is re-downloaded when needed). Runs a fixed script on the target; the
        result is not reported back, so check CacheMgr.log or Get-AZRClientCache afterwards.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    if ($PSCmdlet.ShouldProcess($ComputerName, 'Clear ConfigMgr client cache')) {
        Invoke-AZRRemoteTemplate -ComputerName $ComputerName -Template ClearClientCache -Credential $Credential -Label 'Clear client cache'
    }
}

function Repair-AZRClient {
    <#
    .SYNOPSIS
        Starts a ConfigMgr client repair (SMS_Client.RepairClient, falling back to ccmrepair.exe on the target).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $result = [ordered]@{ ComputerName = $ComputerName; Action = 'Repair client'; Success = $false; Message = '' }
    if ($PSCmdlet.ShouldProcess($ComputerName, 'Repair ConfigMgr client')) {
        try {
            Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                param($s)
                try { $null = Invoke-AZRCim -Session $s -Namespace 'root\ccm' -ClassName SMS_Client -MethodName RepairClient }
                catch {
                    Write-AZRLog -Level Warn -Message "RepairClient method failed on ${ComputerName} ($($_.Exception.Message)); trying ccmrepair.exe"
                    $win = Get-AZRWindowsDirectory -Session $s
                    $null = Invoke-AZRRemoteProcess -Session $s -ComputerName $ComputerName -CommandLine (New-AZRCommandLine -Template CcmRepairExe -WindowsDirectory $win)
                }
            }
            $result.Success = $true; $result.Message = 'Repair started'
        }
        catch { $result.Message = $_.Exception.Message }
    }
    [pscustomobject]$result
}

function Uninstall-AZRClient {
    <#
    .SYNOPSIS
        Uninstalls the ConfigMgr client (ccmsetup.exe /uninstall). Destructive: the device stops being managed until reinstalled.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    if ($PSCmdlet.ShouldProcess($ComputerName, 'Uninstall ConfigMgr client')) {
        Invoke-AZRRemoteTemplate -ComputerName $ComputerName -Template CcmUninstall -Credential $Credential -Label 'Uninstall client'
    }
}

function Invoke-AZRClientHealthCheck {
    <#
    .SYNOPSIS
        Starts the built-in "Configuration Manager Health Evaluation" scheduled task on the client.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    if ($PSCmdlet.ShouldProcess($ComputerName, 'Run client health evaluation')) {
        Invoke-AZRRemoteTemplate -ComputerName $ComputerName -Template ClientHealthCheck -Credential $Credential -Label 'Client health check'
    }
}

function Update-AZRUpdateCompliance {
    <#
    .SYNOPSIS
        Refreshes software update compliance: software updates scan, then deployment evaluation, then state messages.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName, [pscredential]$Credential)
    process {
        foreach ($c in $ComputerName) {
            $steps = foreach ($a in 'SoftwareUpdatesScan', 'SoftwareUpdatesEvaluation', 'SendUnsentStateMessages') {
                Invoke-AZRClientAction -ComputerName $c -Action $a -Credential $Credential -WhatIf:$WhatIfPreference
            }
            $failed = @($steps | Where-Object { -not $_.Success })
            [pscustomobject]@{
                ComputerName = $c
                Action       = 'Refresh update compliance'
                Success      = ($steps -and -not $failed)
                Message      = if ($failed) { ($failed | ForEach-Object { "$($_.Action): $($_.Message)" }) -join '; ' } else { 'Scan, evaluation and state messages triggered' }
            }
        }
    }
}
