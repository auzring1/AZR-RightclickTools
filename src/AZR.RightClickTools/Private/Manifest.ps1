function Get-AZRManifestPath {
    <# Installed layout: <root>\Module\AZR.RightClickTools + <root>\Actions.psd1. Repo layout: src\AZR.RightClickTools + src\Actions.psd1. #>
    $candidates = @(
        (Join-Path $PSScriptRoot '..\..\..\Actions.psd1'),   # Private\ -> module -> Module\ -> install root
        (Join-Path $PSScriptRoot '..\..\Actions.psd1')       # Private\ -> module -> src
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path } }
    $null
}

function Get-AZRActionDefinition {
    <#
    .SYNOPSIS
        Returns the manifest entry for an action id (with Group, Risk and Confirm defaulted), or $null when it is not in the manifest.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [string]$ManifestPath)
    if (-not $ManifestPath) { $ManifestPath = Get-AZRManifestPath }
    if (-not $ManifestPath) { return $null }
    $m = Import-PowerShellDataFile -Path $ManifestPath
    foreach ($g in $m.Groups) {
        foreach ($a in $g.Actions) {
            if ($a.Id -eq $Id) {
                return [pscustomobject]@{
                    Id          = $a.Id
                    Name        = $a.Name
                    Group       = $g.Name
                    Targets     = @($a.Targets)
                    Risk        = if ($a.Risk) { $a.Risk } else { 'Read' }
                    Confirm     = if ($a.Confirm) { $a.Confirm } else { 'Auto' }
                    Requires    = @($a.Requires | Where-Object { $_ })
                    Ui          = if ($a.Ui) { $a.Ui } else { 'None' }
                    Description = $a.Description
                }
            }
        }
    }
    $null
}
