# Thin wrappers around the RSAT ActiveDirectory / Windows LAPS cmdlets so they can be mocked in tests and so the
# optional AdServer setting and alternate credentials are applied in one place.

function Test-AZRAdAvailable { [bool](Get-Command -Name Get-ADComputer -ErrorAction SilentlyContinue) }
function Test-AZRWindowsLapsAvailable { [bool](Get-Command -Name Get-LapsADPassword -ErrorAction SilentlyContinue) }

function Get-AZRAdParameter {
    param([pscredential]$Credential)
    $p = @{ ErrorAction = 'Stop' }
    $server = (Get-AZRSettings).AdServer
    if ($server) { $p.Server = $server }
    if (-not $Credential) { $Credential = Get-AZRDefaultCredential }
    if ($Credential) { $p.Credential = $Credential }
    $p
}

function Get-AZRAdComputer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [string[]]$Property = @(), [pscredential]$Credential)
    if (-not (Test-AZRAdAvailable)) { throw 'The ActiveDirectory PowerShell module (RSAT) is required for this feature.' }
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $p = Get-AZRAdParameter -Credential $Credential
    $p.Identity = $ComputerName.Split('.')[0] + '$'
    if ($Property.Count) { $p.Properties = $Property }
    Get-ADComputer @p
}

function Get-AZRAdRecoveryObject {
    <# BitLocker recovery information objects under a computer object (msFVE-RecoveryInformation). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerDn, [switch]$IncludePassword, [pscredential]$Credential)
    $p = Get-AZRAdParameter -Credential $Credential
    $props = @('msFVE-RecoveryGuid', 'whenCreated')
    if ($IncludePassword) { $props += 'msFVE-RecoveryPassword' }
    Get-ADObject @p -SearchBase $ComputerDn -SearchScope OneLevel -Filter "objectClass -eq 'msFVE-RecoveryInformation'" -Properties $props
}

function Get-AZRWindowsLapsRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [pscredential]$Credential)
    $p = @{ Identity = $ComputerName; ErrorAction = 'Stop' }
    $server = (Get-AZRSettings).AdServer
    if ($server) { $p.DomainController = $server }
    if (-not $Credential) { $Credential = Get-AZRDefaultCredential }
    if ($Credential) { $p.Credential = $Credential }
    Get-LapsADPassword @p    # Password is returned as a SecureString (no -AsPlainText)
}

function Set-AZRWindowsLapsExpiration {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$ComputerName, [Parameter(Mandatory)][datetime]$When, [pscredential]$Credential)
    $p = @{ Identity = $ComputerName; WhenEffective = $When; ErrorAction = 'Stop' }
    $server = (Get-AZRSettings).AdServer
    if ($server) { $p.DomainController = $server }
    if ($Credential) { $p.Credential = $Credential }
    Set-LapsADPasswordExpirationTime @p
}
