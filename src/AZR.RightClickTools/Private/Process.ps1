# Remote execution primitive: Win32_Process.Create. Commands are built ONLY from the fixed templates below plus
# validated parameters, never from free text. The command text is written to the log (it contains no secrets).

function Get-AZRWindowsDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session)
    $os = Get-AZRCim -Session $Session -ClassName Win32_OperatingSystem
    $dir = [string]$os.WindowsDirectory
    if ($dir -notmatch '^[A-Za-z]:\\[A-Za-z0-9 _\\\-\.]{1,100}$') { throw "Unexpected Windows directory on target: '$dir'" }
    $dir.TrimEnd('\')
}

function New-AZRCommandLine {
    <#
    .SYNOPSIS
        Builds a remote command line from a fixed template. Free text only enters through validated parameters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('CcmUninstall', 'CcmRepairExe', 'ClientHealthCheck', 'ClearClientCache', 'GpUpdate', 'Notify', 'Restart', 'Shutdown', 'AbortShutdown', 'MsiUninstall')][string]$Template,
        [Parameter(Mandatory)][string]$WindowsDirectory,
        [hashtable]$Parameter = @{}
    )
    if ($WindowsDirectory -notmatch '^[A-Za-z]:\\[A-Za-z0-9 _\\\-\.]{1,100}$') { throw "Invalid Windows directory: '$WindowsDirectory'" }
    $win = $WindowsDirectory.TrimEnd('\')
    $delay = 60
    if ($Parameter.ContainsKey('DelaySeconds')) {
        $delay = [int]$Parameter.DelaySeconds
        if ($delay -lt 0 -or $delay -gt 86400) { throw 'DelaySeconds must be between 0 and 86400.' }
    }
    switch ($Template) {
        'CcmUninstall'      { return ('"{0}\ccmsetup\ccmsetup.exe" /uninstall' -f $win) }
        'CcmRepairExe'      { return ('"{0}\CCM\ccmrepair.exe"' -f $win) }
        'ClientHealthCheck' { return ('"{0}\System32\schtasks.exe" /Run /TN "\Microsoft\Configuration Manager\Configuration Manager Health Evaluation"' -f $win) }
        'ClearClientCache'  {
            # Fixed script, no inputs: deletes every cache element the client allows to be deleted.
            $script = '$m = New-Object -ComObject UIResource.UIResourceMgr; $c = $m.GetCacheInfo(); $c.GetCacheElements() | ForEach-Object { $c.DeleteCacheElement($_.CacheElementID) }'
            $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
            return ('"{0}\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -EncodedCommand {1}' -f $win, $enc)
        }
        'GpUpdate'          { return ('"{0}\System32\gpupdate.exe" /force' -f $win) }
        'Notify'            {
            $text = Assert-AZRMessageText -Text ([string]$Parameter.Text)
            return ('"{0}\System32\msg.exe" * /TIME:{1} "{2}"' -f $win, [int]$(if ($Parameter.ContainsKey('DisplaySeconds')) { [math]::Min([math]::Max([int]$Parameter.DisplaySeconds, 5), 86400) } else { 300 }), $text)
        }
        'Restart'           { return ('"{0}\System32\shutdown.exe" /r /t {1} /c "{2}" /d p:4:1' -f $win, $delay, (Assert-AZRMessageText -Text ([string]$Parameter.Text) -MaxLength 120)) }
        'Shutdown'          { return ('"{0}\System32\shutdown.exe" /s /t {1} /c "{2}" /d p:4:1' -f $win, $delay, (Assert-AZRMessageText -Text ([string]$Parameter.Text) -MaxLength 120)) }
        'AbortShutdown'     { return ('"{0}\System32\shutdown.exe" /a' -f $win) }
        'MsiUninstall'      { return ('"{0}\System32\msiexec.exe" /x {1} /qn /norestart' -f $win, (Assert-AZRProductCode -ProductCode ([string]$Parameter.ProductCode))) }
    }
}

function Invoke-AZRRemoteProcess {
    <#
    .SYNOPSIS
        Starts a process on the target through Win32_Process.Create (fire and forget; the exit code is not available).
        The command line must come from New-AZRCommandLine.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$CommandLine, [string]$ComputerName)
    Write-AZRLog -Message "Remote process on ${ComputerName}: $CommandLine"
    $r = Invoke-AZRCim -Session $Session -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $CommandLine }
    if ($r.ReturnValue -ne 0) { throw "Win32_Process.Create returned $($r.ReturnValue) on $ComputerName" }
    $r.ProcessId
}

function Invoke-AZRRemoteTemplate {
    <# Opens a session, resolves the Windows directory, builds the templated command and starts it. Returns a result row. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$Template,
        [hashtable]$Parameter = @{},
        [pscredential]$Credential,
        [string]$Label
    )
    $null = Assert-AZRComputerName -ComputerName $ComputerName
    $result = [ordered]@{ ComputerName = $ComputerName; Action = $(if ($Label) { $Label } else { $Template }); Success = $false; Message = '' }
    try {
        Invoke-AZRWithCimSession -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($s)
            $win = Get-AZRWindowsDirectory -Session $s
            $cmd = New-AZRCommandLine -Template $Template -WindowsDirectory $win -Parameter $Parameter
            $null = Invoke-AZRRemoteProcess -Session $s -CommandLine $cmd -ComputerName $ComputerName
        }
        $result.Success = $true
        $result.Message = 'Started'
    }
    catch {
        $result.Message = $_.Exception.Message
        Write-AZRLog -Level Error -Message "$Template failed on ${ComputerName}: $($result.Message)"
    }
    [pscustomobject]$result
}
