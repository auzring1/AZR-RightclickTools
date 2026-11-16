function Test-AZRWindows { $env:OS -eq 'Windows_NT' }

function Show-AZRResult {
    <#
    .SYNOPSIS
        Shows data in a sortable, filterable window with CSV/JSON/clipboard export (WPF), falling back to
        Out-GridView and finally to the pipeline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(ValueFromPipeline)]$InputObject
    )
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $items.Add($InputObject) } }
    end {
        if ((Test-AZRWindows) -and (Get-AZRSettings).UseWpfResults) {
            try {
                Show-AZRWindow -Title $Title -Tab @(@{ Name = 'Results'; Data = $items.ToArray() })
                return
            }
            catch { Write-AZRLog -Level Warn -Message "WPF result window failed ($($_.Exception.Message)); falling back to grid." }
        }
        if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
            $items | ForEach-Object { ConvertTo-AZRSafeRecord -InputObject $_ } | Out-GridView -Title $Title -Wait
        }
        else { $items | ForEach-Object { ConvertTo-AZRSafeRecord -InputObject $_ } }
    }
}

function Show-AZRMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'AZR-RightClickTools',
        [ValidateSet('Information', 'Warning', 'Error')][string]$Icon = 'Information'
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', $Icon)
    }
    catch { Write-Host "$Title`: $Message" }
}

function Confirm-AZRAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message, [string]$Title = 'AZR-RightClickTools')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $r = [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'YesNo', 'Question')
        return ($r -eq 'Yes')
    }
    catch { return $false }
}

function Read-AZRInput {
    <# Asks for one line of text (returns $null when cancelled). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Prompt, [string]$Title = 'AZR-RightClickTools', [string]$Default = '')
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        $r = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default)
        if ([string]::IsNullOrEmpty($r)) { return $null }
        $r
    }
    catch { $null }
}

function Get-AZRConfirmationPlan {
    <#
    .SYNOPSIS
        Pure policy: what confirmation does an action need? Kind is None, YesNo, Typed or SecretReason.
        Read: none (bulk: Yes/No with the count). Change: Yes/No (unless the manifest says Confirm=None for a single device).
        Destructive: the admin must type the device name (single) or the number of devices (bulk).
        Secret: Yes/No plus a reason when RequireReasonForSecrets is on.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Read', 'Change', 'Destructive', 'Secret')][string]$Risk = 'Read',
        [ValidateSet('Device', 'Collection')][string]$Scope = 'Device',
        [Parameter(Mandatory)][int]$Count,
        [string]$ComputerName,
        [string]$Confirm = 'Auto',
        $Settings
    )
    if (-not $Settings) { $Settings = Get-AZRSettings }
    $bulk = $Scope -eq 'Collection'
    switch ($Risk) {
        'Read' {
            if ($bulk -and $Count -ge $Settings.BulkConfirmThreshold) { return @{ Kind = 'YesNo'; Expected = $null; NeedsReason = $false } }
            return @{ Kind = 'None'; Expected = $null; NeedsReason = $false }
        }
        'Change' {
            if ($bulk) { return @{ Kind = 'YesNo'; Expected = $null; NeedsReason = $false } }
            if ($Confirm -eq 'None') { return @{ Kind = 'None'; Expected = $null; NeedsReason = $false } }
            return @{ Kind = 'YesNo'; Expected = $null; NeedsReason = $false }
        }
        'Destructive' {
            $expected = if ($bulk) { [string]$Count } else { $ComputerName }
            return @{ Kind = 'Typed'; Expected = $expected; NeedsReason = $false }
        }
        'Secret' { return @{ Kind = 'SecretReason'; Expected = $null; NeedsReason = [bool]$Settings.RequireReasonForSecrets } }
    }
}

function Confirm-AZRRisk {
    <#
    .SYNOPSIS
        Runs the confirmation required by Get-AZRConfirmationPlan. Returns @{ Approved; Reason }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Risk = 'Read',
        [string]$Scope = 'Device',
        [Parameter(Mandatory)][string[]]$Target,
        [string]$Confirm = 'Auto'
    )
    $count = @($Target).Count
    $name = if ($count -eq 1) { $Target[0] } else { "$count devices" }
    $plan = Get-AZRConfirmationPlan -Risk $Risk -Scope $Scope -Count $count -ComputerName $Target[0] -Confirm $Confirm
    $no = @{ Approved = $false; Reason = $null }
    switch ($plan.Kind) {
        'None' { return @{ Approved = $true; Reason = $null } }
        'YesNo' {
            if (Confirm-AZRAction -Message "Run '$Action' on $name?") { return @{ Approved = $true; Reason = $null } }
            return $no
        }
        'Typed' {
            $what = if ($Scope -eq 'Collection') { "the number of devices ($($plan.Expected))" } else { "the device name ($($plan.Expected))" }
            $typed = Read-AZRInput -Title "Confirm: $Action" -Prompt "'$Action' is destructive and will affect $name.`nType $what to continue."
            if ($typed -and $typed.Trim() -ieq $plan.Expected) { return @{ Approved = $true; Reason = $null } }
            return $no
        }
        'SecretReason' {
            if (-not (Confirm-AZRAction -Message "'$Action' reveals a secret for $name. This is audited. Continue?")) { return $no }
            $reason = $null
            if ($plan.NeedsReason) {
                $raw = Read-AZRInput -Title "Reason: $Action" -Prompt "Enter the reason (ticket or short text) for revealing this secret on $name."
                try { $reason = Assert-AZRReason -Reason ([string]$raw) } catch { return $no }
            }
            return @{ Approved = $true; Reason = $reason }
        }
    }
}
