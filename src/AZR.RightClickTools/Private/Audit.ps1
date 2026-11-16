# Structured audit trail: one JSON object per line. Secrets are never written; any detail field whose
# name looks secret is replaced with '[redacted]' as a second line of defence.

function Get-AZRAuditPath {
    $s = Get-AZRSettings
    if ($s.AuditPath) {
        $dir = Split-Path -Parent $s.AuditPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        return $s.AuditPath
    }
    Join-Path (Get-AZRLogDirectory) ('audit-{0:yyyyMM}.jsonl' -f (Get-Date))
}

function Test-AZRSecretName {
    param([string]$Name)
    $Name -match '(?i)(password|passwd|secret|recoverykey|recoverypassword|token|credential|\bkey\b|protectorpassword)'
}

function Remove-AZRSecretValue {
    <# Returns a copy of a hashtable with secret-looking keys redacted (recursively). #>
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($k in $InputObject.Keys) {
            if (Test-AZRSecretName -Name ([string]$k)) { $copy[$k] = '[redacted]' }
            else { $copy[$k] = Remove-AZRSecretValue -InputObject $InputObject[$k] }
        }
        return $copy
    }
    if ($InputObject -is [securestring]) { return '[redacted]' }
    $InputObject
}

function Write-AZRAudit {
    <#
    .SYNOPSIS
        Appends an audit entry (JSON line): time, user, action, targets, outcome, risk class, reason.
    .DESCRIPTION
        Never include secret values in -Detail or -Message. Keys that look like secrets are redacted anyway.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [string[]]$Target = @(),
        [ValidateSet('Success', 'Failure', 'Cancelled', 'Partial')][string]$Outcome = 'Success',
        [ValidateSet('Read', 'Change', 'Destructive', 'Secret')][string]$Risk = 'Read',
        [string]$Reason,
        [string]$Message,
        [System.Collections.IDictionary]$Detail
    )
    $targets = @($Target | Where-Object { $_ })
    $entry = [ordered]@{
        time        = (Get-Date).ToUniversalTime().ToString('o')
        user        = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
        machine     = $env:COMPUTERNAME
        action      = $Action
        risk        = $Risk
        outcome     = $Outcome
        targetCount = $targets.Count
        targets     = $targets
    }
    if ($Reason) { $entry.reason = $Reason }
    if ($Message) { $entry.message = $Message }
    if ($Detail) { $entry.detail = Remove-AZRSecretValue -InputObject $Detail }
    $line = $entry | ConvertTo-Json -Compress -Depth 6
    $s = Get-AZRSettings
    if ($s.AuditToFile) {
        try { Add-Content -LiteralPath (Get-AZRAuditPath) -Value $line -Encoding UTF8 }
        catch { Write-AZRLog -Level Warn -Message "Audit file write failed: $($_.Exception.Message)" }
    }
    if ($s.AuditToEventLog) {
        try {
            $src = 'AZR-RightClickTools'
            if ([System.Diagnostics.EventLog]::SourceExists($src)) {
                $type = if ($Outcome -eq 'Failure') { 'Warning' } else { 'Information' }
                [System.Diagnostics.EventLog]::WriteEntry($src, $line, $type, 1000)
            }
            else { Write-AZRLog -Level Warn -Message "Event log source '$src' does not exist (create it once from an elevated prompt: New-EventLog -LogName Application -Source $src)." }
        }
        catch { Write-AZRLog -Level Warn -Message "Event log write failed: $($_.Exception.Message)" }
    }
    Write-Verbose $line
}
