# Re-run a deployment (roadmap D3): clear the client's execution history for a package/program so the
# advertisement runs again. Lab-only to verify; the old values are saved to the log folder first.

function Get-AZRExecutionHistory {
    <#
    .SYNOPSIS
        Lists the legacy package/program execution history recorded on the client (HKLM ...\Execution History\System).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $root = 'SOFTWARE\Microsoft\SMS\Mobile Client\Software Distribution\Execution History\System'
    Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
        param($s)
        foreach ($pkg in Get-AZRRegSubKey -Session $s -SubKey $root) {
            foreach ($prog in Get-AZRRegSubKey -Session $s -SubKey "$root\$pkg") {
                $k = "$root\$pkg\$prog"
                [pscustomobject]@{
                    ComputerName = $ComputerName
                    PackageId    = $pkg
                    Program      = Get-AZRRegString -Session $s -SubKey $k -ValueName '_ProgramID'
                    State        = Get-AZRRegString -Session $s -SubKey $k -ValueName '_State'
                    RunStart     = Get-AZRRegString -Session $s -SubKey $k -ValueName '_RunStartTime'
                    Key          = $k
                }
            }
        }
    }
}

function Reset-AZRExecutionHistory {
    <#
    .SYNOPSIS
        Deletes the execution history key for one package ID so a "run once" deployment can run again, then triggers
        machine policy retrieval. The deleted values are saved as JSON in the AZR log folder first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$PackageId,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $PackageId = Assert-AZRPackageId -PackageId $PackageId
    $result = [ordered]@{ ComputerName = $ComputerName; Action = "Reset execution history $PackageId"; Success = $false; Message = '' }
    if (-not $PSCmdlet.ShouldProcess("$ComputerName\$PackageId", 'Delete execution history')) { return [pscustomobject]$result }
    try {
        $root = 'SOFTWARE\Microsoft\SMS\Mobile Client\Software Distribution\Execution History\System'
        $removed = Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($s)
            $backup = @(foreach ($prog in Get-AZRRegSubKey -Session $s -SubKey "$root\$PackageId") {
                    $k = "$root\$PackageId\$prog"
                    [ordered]@{ Key = $k; ProgramID = (Get-AZRRegString -Session $s -SubKey $k -ValueName '_ProgramID'); State = (Get-AZRRegString -Session $s -SubKey $k -ValueName '_State'); RunStart = (Get-AZRRegString -Session $s -SubKey $k -ValueName '_RunStartTime') }
                })
            if (-not $backup.Count) { throw "No execution history for $PackageId on $ComputerName." }
            $file = Join-Path (Get-AZRLogDirectory) ('exechistory-{0}-{1}-{2:yyyyMMddHHmmss}.json' -f $ComputerName, $PackageId, (Get-Date))
            $backup | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
            # StdRegProv.DeleteKey is not recursive: remove program sub-keys first, then the package key.
            foreach ($prog in Get-AZRRegSubKey -Session $s -SubKey "$root\$PackageId") {
                $r = Invoke-AZRReg -Session $s -Method DeleteKey -SubKey "$root\$PackageId\$prog"
                if ($r.ReturnValue -ne 0) { throw "DeleteKey returned $($r.ReturnValue) for $prog" }
            }
            $r = Invoke-AZRReg -Session $s -Method DeleteKey -SubKey "$root\$PackageId"
            if ($r.ReturnValue -ne 0) { throw "DeleteKey returned $($r.ReturnValue)" }
            $file
        }
        $null = Invoke-AZRClientAction -ComputerName $ComputerName -Action MachinePolicyRetrieval -Credential $Credential -Confirm:$false
        $result.Success = $true
        $result.Message = "History removed (backup: $removed). Machine policy retrieval triggered."
    }
    catch { $result.Message = $_.Exception.Message }
    [pscustomobject]$result
}
