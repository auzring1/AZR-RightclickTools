<#
.SYNOPSIS
    Installs AZR-RightClickTools on a workstation that has the ConfigMgr console.
.DESCRIPTION
    1. Copies the module and launcher to InstallDir.
    2. Generates the console extension XML and writes it to
       <ConsoleDir>\XmlStorage\Extensions\Actions\<node GUID>\.
    Restart the console afterwards.
.EXAMPLE
    .\Install-AZRRightClickTools.ps1
.EXAMPLE
    .\Install-AZRRightClickTools.ps1 -ConsoleDir 'D:\ConfigMgr\AdminConsole' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'AZR-RightClickTools'),
    [string]$ConsoleDir
)
$ErrorActionPreference = 'Stop'

function Get-AZRConsoleDir {
    if ($env:SMS_ADMIN_UI_PATH) {
        # e.g. C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin
        $bin = $env:SMS_ADMIN_UI_PATH.TrimEnd('\')
        $root = Split-Path -Parent (Split-Path -Parent $bin)
        if ((Split-Path -Leaf $bin) -eq 'i386') { return $root }
        return Split-Path -Parent $bin
    }
    $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConsoleDir) { $ConsoleDir = Get-AZRConsoleDir }
if (-not $ConsoleDir -or -not (Test-Path -LiteralPath $ConsoleDir)) {
    throw 'ConfigMgr console not found. Install the console first or pass -ConsoleDir <path to AdminConsole>.'
}
$actionsDir = Join-Path $ConsoleDir 'XmlStorage\Extensions\Actions'

$srcModule   = Join-Path $repoRoot 'src\AZR.RightClickTools'
$srcLauncher = Join-Path $repoRoot 'src\Launcher\Invoke-AZRLauncher.ps1'
$srcManifest = Join-Path $repoRoot 'src\Actions.psd1'
foreach ($p in $srcModule, $srcLauncher, $srcManifest) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing source: $p" } }

$dstModule   = Join-Path $InstallDir 'Module\AZR.RightClickTools'
$dstLauncher = Join-Path $InstallDir 'Launcher'

if ($PSCmdlet.ShouldProcess($InstallDir, 'Copy module and launcher')) {
    New-Item -ItemType Directory -Path $dstModule, $dstLauncher -Force | Out-Null
    Copy-Item -Path (Join-Path $srcModule '*') -Destination $dstModule -Recurse -Force
    Copy-Item -Path $srcLauncher -Destination $dstLauncher -Force
    Copy-Item -Path $srcManifest -Destination $InstallDir -Force
    Get-ChildItem -Path $InstallDir -Recurse -File | Unblock-File
}

$launcherPath = Join-Path $dstLauncher 'Invoke-AZRLauncher.ps1'
if ($PSCmdlet.ShouldProcess($actionsDir, 'Write console extension XML')) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('azr-' + [guid]::NewGuid())
    try {
        & (Join-Path $repoRoot 'tools\Build-ConsoleExtension.ps1') -LauncherPath $launcherPath -OutputPath $tmp -ManifestPath $srcManifest
        New-Item -ItemType Directory -Path $actionsDir -Force | Out-Null
        Copy-Item -Path (Join-Path $tmp '*') -Destination $actionsDir -Recurse -Force
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host "Installed to $InstallDir. Extension XML written under $actionsDir. Restart the ConfigMgr console." -ForegroundColor Green
