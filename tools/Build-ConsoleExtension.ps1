<#
.SYNOPSIS
    Generates ConfigMgr console extension XML files from src\Actions.psd1.
.DESCRIPTION
    Writes <OutputPath>\<NodeGuid>\AZR-RightClickTools.xml for the Devices and Device Collections nodes.
    Copy the contents of OutputPath into <ConsoleDir>\XmlStorage\Extensions\Actions (the installer does this).
.PARAMETER LauncherPath
    Full path of Invoke-AZRLauncher.ps1 as it will exist on the admin workstation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LauncherPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ManifestPath = $(if ($PSScriptRoot) { Join-Path $PSScriptRoot '..\src\Actions.psd1' })
)
$ErrorActionPreference = 'Stop'
if (-not $ManifestPath) { throw 'Run Build-ConsoleExtension.ps1 as a file (or pass -ManifestPath); it cannot be pasted into a console.' }

# Console node GUIDs (see docs\ARCHITECTURE.md; verify against your console version).
$NodeGuids = @{
    Device     = 'ed9dee86-eadd-4ac8-82a1-7234a4646e62'
    Collection = '3fd01cd1-9e01-461e-92cd-94866b8d1f39'
}

function ConvertTo-AZRXmlText([string]$Text) { [System.Security.SecurityElement]::Escape($Text) }

function New-AZRActionXml {
    param($Manifest, [string]$Target, [string]$Launcher)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine('<ActionDescription Class="Group" DisplayName="' + (ConvertTo-AZRXmlText $Manifest.Menu) + '" MnemonicDisplayName="' + (ConvertTo-AZRXmlText $Manifest.Menu) + '" Description="Free right-click tools">')
    [void]$sb.AppendLine('  <ShowOn><string>ContextMenu</string></ShowOn>')
    [void]$sb.AppendLine('  <ActionGroups>')
    foreach ($group in $Manifest.Groups) {
        $actions = @($group.Actions | Where-Object { $_.Targets -contains $Target })
        if (-not $actions) { continue }
        [void]$sb.AppendLine('    <ActionDescription Class="Group" DisplayName="' + (ConvertTo-AZRXmlText $group.Name) + '" MnemonicDisplayName="' + (ConvertTo-AZRXmlText $group.Name) + '" Description="">')
        [void]$sb.AppendLine('      <ShowOn><string>ContextMenu</string></ShowOn>')
        [void]$sb.AppendLine('      <ActionGroups>')
        foreach ($a in $actions) {
            if ($Target -eq 'Device') { $targetArgs = '-ComputerName "##SUB:Name##"' }
            else { $targetArgs = '-CollectionId "##SUB:CollectionID##"' }
            $params = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action {1} {2} -SiteServer "##SUB:__Server##" -Namespace "##SUB:__Namespace##"' -f $Launcher, $a.Id, $targetArgs
            $name = ConvertTo-AZRXmlText $a.Name
            [void]$sb.AppendLine('        <ActionDescription Class="Executable" DisplayName="' + $name + '" MnemonicDisplayName="' + $name + '" Description="' + (ConvertTo-AZRXmlText $a.Description) + '">')
            [void]$sb.AppendLine('          <ShowOn><string>ContextMenu</string></ShowOn>')
            [void]$sb.AppendLine('          <Executable>')
            [void]$sb.AppendLine('            <FilePath>PowerShell.exe</FilePath>')
            [void]$sb.AppendLine('            <Parameters>' + (ConvertTo-AZRXmlText $params) + '</Parameters>')
            [void]$sb.AppendLine('          </Executable>')
            [void]$sb.AppendLine('        </ActionDescription>')
        }
        [void]$sb.AppendLine('      </ActionGroups>')
        [void]$sb.AppendLine('    </ActionDescription>')
    }
    [void]$sb.AppendLine('  </ActionGroups>')
    [void]$sb.AppendLine('</ActionDescription>')
    $sb.ToString()
}

$manifest = Import-PowerShellDataFile -Path $ManifestPath
foreach ($target in $NodeGuids.Keys) {
    $dir = Join-Path $OutputPath $NodeGuids[$target]
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $xml = New-AZRActionXml -Manifest $manifest -Target $target -Launcher $LauncherPath
    [void][xml]$xml   # throws if not well-formed
    [System.IO.File]::WriteAllText((Join-Path $dir 'AZR-RightClickTools.xml'), $xml, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Verbose "Extension XML written to $OutputPath"
