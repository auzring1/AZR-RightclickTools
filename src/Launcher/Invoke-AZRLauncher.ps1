<#
.SYNOPSIS
    Entry point started by the ConfigMgr console for each right-click action.
.NOTES
    The console passes values using ##SUB:...## substitution. Everything is validated again
    inside the module before use.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Action,
    [string]$ComputerName,
    [string]$CollectionId,
    [string]$SiteServer,
    [string]$Namespace,
    [string]$SiteCode
)
$ErrorActionPreference = 'Stop'

# Installed layout: <root>\Launcher\this.ps1 and <root>\Module\AZR.RightClickTools
# Repo layout:      src\Launcher\this.ps1     and src\AZR.RightClickTools
$candidates = @(
    (Join-Path $PSScriptRoot '..\Module\AZR.RightClickTools\AZR.RightClickTools.psd1'),
    (Join-Path $PSScriptRoot '..\AZR.RightClickTools\AZR.RightClickTools.psd1')
)
$manifest = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $manifest) { throw 'AZR.RightClickTools module not found next to the launcher.' }
Import-Module $manifest -Force

# '##SUB:__Namespace##' resolves to e.g. root\sms\site_ABC
if (-not $SiteCode -and $Namespace -match 'site_([A-Za-z0-9]{3})$') { $SiteCode = $Matches[1] }

$params = @{ Action = $Action }
foreach ($k in 'ComputerName', 'CollectionId', 'SiteServer', 'SiteCode') {
    $v = Get-Variable -Name $k -ValueOnly
    if ($v) { $params[$k] = $v }
}
Invoke-AZRAction @params
