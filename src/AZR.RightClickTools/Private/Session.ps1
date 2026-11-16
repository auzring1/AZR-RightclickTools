function New-AZRCimSession {
    <#
    .SYNOPSIS
        Opens a CIM session to a computer, trying WSMan first and falling back to DCOM.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential
    )
    $common = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
    if ($Credential) { $common.Credential = $Credential }
    try {
        New-CimSession @common -OperationTimeoutSec 30
    }
    catch {
        Write-AZRLog -Level Warn -Message "WSMan CIM session to $ComputerName failed ($($_.Exception.Message)); trying DCOM."
        $opt = New-CimSessionOption -Protocol Dcom
        New-CimSession @common -SessionOption $opt -OperationTimeoutSec 30
    }
}

function Invoke-AZRWithCimSession {
    <#
    .SYNOPSIS
        Runs a script block with a CIM session, always disposing the session.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [pscredential]$Credential
    )
    $session = New-AZRCimSession -ComputerName $ComputerName -Credential $Credential
    try { & $ScriptBlock $session }
    finally { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
}
