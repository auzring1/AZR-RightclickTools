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

# $PSScriptRoot is empty when the script text is pasted into a console or run via Invoke-Expression.
if ([string]::IsNullOrEmpty($PSScriptRoot)) {
    throw ('Install-AZRRightClickTools.ps1 must be run as a file, not pasted into a console. ' +
        'Clone or extract the repository, open an elevated PowerShell, cd into it and run: ' +
        '.\installer\Install-AZRRightClickTools.ps1  ' +
        "(if script execution is blocked, use: powershell -ExecutionPolicy Bypass -File .\installer\Install-AZRRightClickTools.ps1).")
}

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
$srcNodes    = Join-Path $repoRoot 'src\Nodes.psd1'
foreach ($p in $srcModule, $srcLauncher, $srcManifest, $srcNodes) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing source: $p" } }

$dstModule   = Join-Path $InstallDir 'Module\AZR.RightClickTools'
$dstLauncher = Join-Path $InstallDir 'Launcher'

if ($PSCmdlet.ShouldProcess($InstallDir, 'Copy module and launcher')) {
    New-Item -ItemType Directory -Path $dstModule, $dstLauncher -Force | Out-Null
    Copy-Item -Path (Join-Path $srcModule '*') -Destination $dstModule -Recurse -Force
    Copy-Item -Path $srcLauncher -Destination $dstLauncher -Force
    Copy-Item -Path $srcManifest -Destination $InstallDir -Force
    Copy-Item -Path $srcNodes -Destination $InstallDir -Force
    Get-ChildItem -Path $InstallDir -Recurse -File | Unblock-File
}

$launcherPath = Join-Path $dstLauncher 'Invoke-AZRLauncher.ps1'
if ($PSCmdlet.ShouldProcess($actionsDir, 'Write console extension XML')) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('azr-' + [guid]::NewGuid())
    try {
        & (Join-Path $repoRoot 'tools\Build-ConsoleExtension.ps1') -LauncherPath $launcherPath -OutputPath $tmp -ManifestPath $srcManifest -NodesPath $srcNodes
        New-Item -ItemType Directory -Path $actionsDir -Force | Out-Null
        Copy-Item -Path (Join-Path $tmp '*') -Destination $actionsDir -Recurse -Force
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
# Self-check so a lab run shows immediately whether the install is usable.
if (-not $WhatIfPreference) {
    try {
        $mod = Import-Module (Join-Path $dstModule 'AZR.RightClickTools.psd1') -Force -PassThru -ErrorAction Stop
        Write-Host ("Module check OK: {0} functions load from {1}" -f $mod.ExportedFunctions.Count, $dstModule) -ForegroundColor Green
    }
    catch { Write-Warning "Module check FAILED: $($_.Exception.Message). The menu items would not work; see README 'Troubleshooting'." }
    $written = @(Get-ChildItem -Path $actionsDir -Recurse -Filter 'AZR-RightClickTools.xml' -ErrorAction SilentlyContinue)
    foreach ($f in $written) { Write-Host ("Menu XML: {0}" -f $f.FullName) }
    if (-not $written) { Write-Warning "No AZR-RightClickTools.xml found under $actionsDir." }
}
Write-Host "Installed to $InstallDir. Extension XML written under $actionsDir. Restart the ConfigMgr console." -ForegroundColor Green
Write-Host "No menu after restart? Run tools\Get-AZRConsoleNodes.ps1 and compare the GUIDs with src\Nodes.psd1 (see README 'Troubleshooting')." -ForegroundColor Yellow
