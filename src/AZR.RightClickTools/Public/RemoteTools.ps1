function Test-AZRConnection {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$ComputerName, [int]$Count = 4)
    process {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        $up = $false
        try { $up = Test-Connection -ComputerName $ComputerName -Count $Count -Quiet -ErrorAction Stop } catch { $up = $false }
        $wsman = $false
        try { $null = Test-WSMan -ComputerName $ComputerName -ErrorAction Stop; $wsman = $true } catch { $wsman = $false }
        [pscustomobject]@{ ComputerName = $ComputerName; Ping = $up; WinRM = $wsman }
    }
}

function Get-AZRService {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [string]$Name = '*', [pscredential]$Credential)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
        param($s)
        Get-CimInstance -CimSession $s -ClassName Win32_Service -ErrorAction Stop |
            Where-Object Name -like $Name |
            Select-Object @{n = 'ComputerName'; e = { $ComputerName } }, Name, DisplayName, State, StartMode, StartName |
            Sort-Object Name
    }
}

function Restart-AZRService {
    <#
    .SYNOPSIS
        Restarts a service on a remote computer (e.g. CcmExec) using the Win32_Service methods.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_\-\$\.]+$')][string]$Name,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    if (-not $PSCmdlet.ShouldProcess("$ComputerName\$Name", 'Restart service')) { return }
    Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
        param($s)
        $svc = Get-CimInstance -CimSession $s -ClassName Win32_Service -Filter "Name = '$Name'" -ErrorAction Stop
        if (-not $svc) { throw "Service '$Name' not found on $ComputerName" }
        if ($svc.State -ne 'Stopped') {
            $r = Invoke-CimMethod -InputObject $svc -MethodName StopService
            if ($r.ReturnValue -ne 0) { throw "StopService returned $($r.ReturnValue)" }
            $deadline = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 500
                $svc = Get-CimInstance -CimSession $s -ClassName Win32_Service -Filter "Name = '$Name'"
            } while ($svc.State -ne 'Stopped' -and (Get-Date) -lt $deadline)
            if ($svc.State -ne 'Stopped') { throw "Service '$Name' did not stop within 30 seconds" }
        }
        $r = Invoke-CimMethod -InputObject $svc -MethodName StartService
        if ($r.ReturnValue -ne 0) { throw "StartService returned $($r.ReturnValue)" }
        Write-AZRLog -Message "Restarted service $Name on $ComputerName"
        [pscustomobject]@{ ComputerName = $ComputerName; Service = $Name; Result = 'Restarted' }
    }
}

function Get-AZREventLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [string]$LogName = 'System',
        [ValidateSet('Critical', 'Error', 'Warning', 'Information')][string[]]$Level = @('Critical', 'Error', 'Warning'),
        [int]$MaxEvents = 200,
        [pscredential]$Credential
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $levelMap = @{ Critical = 1; Error = 2; Warning = 3; Information = 4 }
    $filter = @{ LogName = $LogName; Level = @($Level | ForEach-Object { $levelMap[$_] }) }
    $p = @{ ComputerName = $ComputerName; FilterHashtable = $filter; MaxEvents = $MaxEvents; ErrorAction = 'Stop' }
    if ($Credential) { $p.Credential = $Credential }
    Get-WinEvent @p | Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, Message
}

function Open-AZRCDrive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [string]$Share = 'C$')
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"\\{0}\{1}"' -f $ComputerName, $Share)
}

function Open-AZRClientLogs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"\\{0}\C$\Windows\CCM\Logs"' -f $ComputerName)
}

function Start-AZRRdp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [switch]$Admin)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $rdpArgs = @("/v:$ComputerName")
    if ($Admin) { $rdpArgs += '/admin' }
    Start-Process -FilePath 'mstsc.exe' -ArgumentList $rdpArgs
}

function Start-AZRRemoteShell {
    <#
    .SYNOPSIS
        Opens a new PowerShell window with an interactive remoting session to the computer.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    # ComputerName was validated against a strict allow-list above, so embedding it is safe.
    $cmd = "Enter-PSSession -ComputerName '$ComputerName'"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-NoProfile', '-Command', $cmd)
}

function Start-AZRComputerManagement {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    Start-Process -FilePath 'compmgmt.msc' -ArgumentList "/computer:$ComputerName"
}
