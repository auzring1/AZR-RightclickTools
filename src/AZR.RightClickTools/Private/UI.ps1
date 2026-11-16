function Show-AZRResult {
    <#
    .SYNOPSIS
        Shows data in a sortable grid window (Out-GridView), falling back to the pipeline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(ValueFromPipeline)]$InputObject
    )
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $items.Add($InputObject) } }
    end {
        if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
            $items | Out-GridView -Title $Title -Wait
        }
        else { $items }
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
