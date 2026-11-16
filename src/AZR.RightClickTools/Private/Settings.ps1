# Settings: defaults < per-user file < machine policy file. Invalid values are ignored (and logged), never fatal.
#   User:    %APPDATA%\AZR-RightClickTools\settings.json
#   Machine: %ProgramData%\AZR-RightClickTools\settings.json  (or a UNC path in AZR_SETTINGS_MACHINE)
# Tests and labs can point at other files with AZR_SETTINGS_USER / AZR_SETTINGS_MACHINE.

function Get-AZRSettingsSchema {
    # Name -> Type, optional Min/Max/Allowed, Default
    [ordered]@{
        MaxParallel                 = @{ Type = 'int'; Min = 1; Max = 64; Default = 10 }
        BulkConfirmThreshold        = @{ Type = 'int'; Min = 1; Max = 100000; Default = 1 }
        UseWpfResults               = @{ Type = 'bool'; Default = $true }
        ExportDirectory             = @{ Type = 'string'; Default = '' }
        AuditToFile                 = @{ Type = 'bool'; Default = $true }
        AuditPath                   = @{ Type = 'string'; Default = '' }
        AuditToEventLog             = @{ Type = 'bool'; Default = $false }
        RequireReasonForSecrets     = @{ Type = 'bool'; Default = $true }
        SecretClipboardClearSeconds = @{ Type = 'int'; Min = 5; Max = 600; Default = 30 }
        DefaultCredentialName       = @{ Type = 'string'; Default = '' }
        UseAdminService             = @{ Type = 'bool'; Default = $false }
        AdminServiceServer          = @{ Type = 'string'; Default = '' }
        AdServer                    = @{ Type = 'string'; Default = '' }
    }
}

function Get-AZRDefaultSettings {
    $d = [ordered]@{}
    $schema = Get-AZRSettingsSchema
    foreach ($k in $schema.Keys) { $d[$k] = $schema[$k].Default }
    $d
}

function Test-AZRSettingValue {
    <# Returns $null when the value is valid for the key, otherwise an error string. #>
    param([string]$Key, $Value)
    $schema = Get-AZRSettingsSchema
    if (-not $schema.Contains($Key)) { return "Unknown setting '$Key'" }
    $s = $schema[$Key]
    switch ($s.Type) {
        'bool' { if ($Value -isnot [bool]) { return "'$Key' must be true or false" } }
        'int' {
            if (($Value -isnot [int]) -and ($Value -isnot [long])) { return "'$Key' must be a whole number" }
            if ($Value -lt $s.Min -or $Value -gt $s.Max) { return "'$Key' must be between $($s.Min) and $($s.Max)" }
        }
        'string' { if ($Value -isnot [string]) { return "'$Key' must be text" } }
    }
    $null
}

function Get-AZRSettingsPath {
    param([ValidateSet('User', 'Machine')][string]$Scope)
    if ($Scope -eq 'User') {
        if ($env:AZR_SETTINGS_USER) { return $env:AZR_SETTINGS_USER }
        if ($env:APPDATA) { return (Join-Path $env:APPDATA 'AZR-RightClickTools\settings.json') }
    }
    else {
        if ($env:AZR_SETTINGS_MACHINE) { return $env:AZR_SETTINGS_MACHINE }
        if ($env:ProgramData) { return (Join-Path $env:ProgramData 'AZR-RightClickTools\settings.json') }
    }
    $null
}

function Read-AZRSettingsFile {
    param([string]$Path)
    $result = @{ Values = @{}; Errors = @() }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    try { $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { $result.Errors += "Cannot read ${Path}: $($_.Exception.Message)"; return $result }
    foreach ($p in $json.PSObject.Properties) {
        $err = Test-AZRSettingValue -Key $p.Name -Value $p.Value
        if ($err) { $result.Errors += "${Path}: $err" } else { $result.Values[$p.Name] = $p.Value }
    }
    $result
}

function Get-AZRSettings {
    <#
    .SYNOPSIS
        Returns the effective settings (defaults, then user file, then machine policy file).
    .DESCRIPTION
        The machine file overrides the user file, so an administrator can enforce values.
        Invalid entries are ignored and written to the log. Use -Detailed to also get the errors.
    #>
    [CmdletBinding()]
    param([switch]$Detailed)
    $effective = Get-AZRDefaultSettings
    $errors = @()
    foreach ($scope in 'User', 'Machine') {
        $r = Read-AZRSettingsFile -Path (Get-AZRSettingsPath -Scope $scope)
        foreach ($k in $r.Values.Keys) { $effective[$k] = $r.Values[$k] }
        $errors += $r.Errors
    }
    foreach ($e in $errors) { Write-AZRLog -Level Warn -Message "Settings: $e" }
    if ($Detailed) { return [pscustomobject]@{ Settings = [pscustomobject]$effective; Errors = $errors } }
    [pscustomobject]$effective
}
