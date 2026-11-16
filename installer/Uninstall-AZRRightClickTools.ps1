<#
.SYNOPSIS
    Removes AZR-RightClickTools files and console extension XML.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'AZR-RightClickTools'),
    [string]$ConsoleDir
)
$ErrorActionPreference = 'Stop'
if (-not $ConsoleDir -and $env:SMS_ADMIN_UI_PATH) {
    $bin = $env:SMS_ADMIN_UI_PATH.TrimEnd('\')
    $ConsoleDir = if ((Split-Path -Leaf $bin) -eq 'i386') { Split-Path -Parent (Split-Path -Parent $bin) } else { Split-Path -Parent $bin }
}
if ($ConsoleDir) {
    Get-ChildItem -Path (Join-Path $ConsoleDir 'XmlStorage\Extensions\Actions') -Recurse -Filter 'AZR-RightClickTools.xml' -ErrorAction SilentlyContinue |
        ForEach-Object { if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove')) { Remove-Item -LiteralPath $_.FullName -Force } }
}
if ((Test-Path -LiteralPath $InstallDir) -and $PSCmdlet.ShouldProcess($InstallDir, 'Remove')) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
Write-Host 'Uninstalled. Restart the ConfigMgr console.' -ForegroundColor Green
