function New-AZRCimSession {
    <#
    .SYNOPSIS
        Opens a CIM session to a computer, trying WSMan first and falling back to DCOM.
        When no -Credential is given the DefaultCredentialName setting (if any) is used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential
    )
    if (-not $Credential) { $Credential = Get-AZRDefaultCredential }
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

function Close-AZRCimSession {
    param($Session)
    try { if ($Session) { Remove-CimSession -CimSession $Session -ErrorAction SilentlyContinue } } catch { Write-Verbose "Session close failed: $_" }
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
    finally { Close-AZRCimSession -Session $session }
}

# Thin wrappers around the CIM cmdlets so every remote read/write funnels through two functions
# (easy to mock in tests, one place to add logging or throttling later).
function Get-AZRCim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Namespace = 'root\cimv2',
        [string]$Filter
    )
    $p = @{ CimSession = $Session; Namespace = $Namespace; ClassName = $ClassName; ErrorAction = 'Stop' }
    if ($Filter) { $p.Filter = $Filter }
    Get-CimInstance @p
}

function Invoke-AZRCim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ClassName,
        [Parameter(Mandatory)][string]$MethodName,
        [string]$Namespace = 'root\cimv2',
        [hashtable]$Arguments = @{}
    )
    Invoke-CimMethod -CimSession $Session -Namespace $Namespace -ClassName $ClassName -MethodName $MethodName -Arguments $Arguments -ErrorAction Stop
}

function Get-AZRCimQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Query,
        [string]$Namespace = 'root\cimv2'
    )
    Get-CimInstance -CimSession $Session -Namespace $Namespace -Query $Query -ErrorAction Stop
}

function Get-AZRCimAssociated {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][string]$Association)
    Get-CimAssociatedInstance -CimSession $Session -InputObject $InputObject -Association $Association -ErrorAction Stop
}

function Set-AZRCimProperty {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][hashtable]$Property)
    Set-CimInstance -CimSession $Session -InputObject $InputObject -Property $Property -ErrorAction Stop
}

function Remove-AZRCimInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$InputObject)
    Remove-CimInstance -CimSession $Session -InputObject $InputObject -ErrorAction Stop
}

function Invoke-AZRCimOnInstance {
    <# Calls a method on a CIM instance (e.g. Win32_UserProfile.Delete, Win32_Process.Terminate). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][string]$MethodName, [hashtable]$Arguments = @{})
    Invoke-CimMethod -CimSession $Session -InputObject $InputObject -MethodName $MethodName -Arguments $Arguments -ErrorAction Stop
}

# Remote registry through the StdRegProv CIM class: no Remote Registry service and no extra firewall rule needed.
function Invoke-AZRReg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][ValidateSet('EnumKey', 'EnumValues', 'GetStringValue', 'GetDWORDValue', 'DeleteKey')][string]$Method,
        [Parameter(Mandatory)][string]$SubKey,
        [string]$ValueName
    )
    $regArgs = @{ hDefKey = [uint32]2147483650; sSubKeyName = $SubKey }   # HKEY_LOCAL_MACHINE
    if ($ValueName) { $regArgs.sValueName = $ValueName }
    Invoke-AZRCim -Session $Session -Namespace 'root\default' -ClassName StdRegProv -MethodName $Method -Arguments $regArgs
}

function Get-AZRRegSubKey {
    param($Session, [string]$SubKey)
    $r = Invoke-AZRReg -Session $Session -Method EnumKey -SubKey $SubKey
    if ($r.ReturnValue -eq 0 -and $r.sNames) { @($r.sNames) } else { @() }
}

function Get-AZRRegString {
    param($Session, [string]$SubKey, [string]$ValueName)
    $r = Invoke-AZRReg -Session $Session -Method GetStringValue -SubKey $SubKey -ValueName $ValueName
    if ($r.ReturnValue -eq 0) { $r.sValue } else { $null }
}

function Get-AZRRegDword {
    param($Session, [string]$SubKey, [string]$ValueName)
    $r = Invoke-AZRReg -Session $Session -Method GetDWORDValue -SubKey $SubKey -ValueName $ValueName
    if ($r.ReturnValue -eq 0) { $r.uValue } else { $null }
}
