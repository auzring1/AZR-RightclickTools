<#
.SYNOPSIS
    Generates ConfigMgr console extension XML files from src\Actions.psd1 and src\Nodes.psd1.
.DESCRIPTION
    Writes <OutputPath>\<NodeGuid>\AZR-RightClickTools.xml for every node that has a GUID and at least one action.
    The manifest is validated first (schema version, ids, targets, risk, requires, ui, placeholders); a bad
    manifest stops the build with all problems listed.
    Copy the contents of OutputPath into <ConsoleDir>\XmlStorage\Extensions\Actions (the installer does this).
.PARAMETER LauncherPath
    Full path of Invoke-AZRLauncher.ps1 as it will exist on the admin workstation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LauncherPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ManifestPath = $(if ($PSScriptRoot) { Join-Path $PSScriptRoot '..\src\Actions.psd1' }),
    [string]$NodesPath = $(if ($PSScriptRoot) { Join-Path $PSScriptRoot '..\src\Nodes.psd1' })
)
$ErrorActionPreference = 'Stop'
if (-not $ManifestPath -or -not $NodesPath) { throw 'Run Build-ConsoleExtension.ps1 as a file (or pass -ManifestPath and -NodesPath); it cannot be pasted into a console.' }

$ValidRisk     = 'Read', 'Change', 'Destructive', 'Secret'
$ValidRequires = 'AD', 'Graph', 'AdminSvc', 'ConfigMgrModule', 'SmsProvider'
$ValidConfirm  = 'Auto', 'None'

function ConvertTo-AZRXmlText([string]$Text) { [System.Security.SecurityElement]::Escape($Text) }

function Test-AZRManifestDefinition {
    param($Manifest, $Nodes)
    $errors = New-Object System.Collections.Generic.List[string]
    if ($Manifest.SchemaVersion -ne 2) { $errors.Add('Manifest SchemaVersion must be 2.') }
    $seen = @{}
    foreach ($group in $Manifest.Groups) {
        foreach ($a in $group.Actions) {
            $id = [string]$a.Id
            if ($id -notmatch '^[A-Za-z][A-Za-z0-9]{1,48}$') { $errors.Add("Action id '$id' is not a plain identifier.") }
            if ($seen.ContainsKey($id)) { $errors.Add("Duplicate action id '$id'.") }
            $seen[$id] = $true
            if (-not $a.Name) { $errors.Add("[$id] missing Name.") }
            if (-not $a.Description) { $errors.Add("[$id] missing Description.") }
            if (-not $a.Targets) { $errors.Add("[$id] needs at least one target.") }
            foreach ($t in @($a.Targets)) {
                if (-not $Nodes.ContainsKey($t)) { $errors.Add("[$id] unknown target '$t'.") }
                elseif (-not $Nodes[$t].Guid) { $errors.Add("[$id] target '$t' has no node GUID yet (see Nodes.psd1).") }
            }
            $risk = if ($a.Risk) { $a.Risk } else { 'Read' }
            if ($risk -notin $ValidRisk) { $errors.Add("[$id] invalid Risk '$risk'.") }
            foreach ($r in @($a.Requires)) { if ($r -and $r -notin $ValidRequires) { $errors.Add("[$id] invalid Requires '$r'.") } }
            if ($a.Ui -and $a.Ui -notmatch '^(None|Grid|Window:[A-Za-z]+)$') { $errors.Add("[$id] invalid Ui '$($a.Ui)'.") }
            $confirm = if ($a.Confirm) { $a.Confirm } else { 'Auto' }
            if ($confirm -notin $ValidConfirm) { $errors.Add("[$id] invalid Confirm '$confirm'.") }
            if ($confirm -eq 'None' -and $risk -in 'Destructive', 'Secret') { $errors.Add("[$id] Confirm=None is not allowed for $risk actions.") }
            if ($risk -eq 'Secret' -and ($a.Targets -contains 'Collection')) { $errors.Add("[$id] Secret actions must be single-device only.") }
        }
    }
    foreach ($name in $Nodes.Keys) {
        $n = $Nodes[$name]
        if ($n.Guid -and $n.TargetArgs) {
            foreach ($m in [regex]::Matches($n.TargetArgs, '##SUB:([^#]+)##')) {
                if ($m.Groups[1].Value -notin $n.Placeholders) { $errors.Add("Node '$name' uses placeholder '$($m.Groups[1].Value)' that is not in its Placeholders list.") }
            }
        }
        if ($n.Guid -and $n.Guid -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { $errors.Add("Node '$name' has a malformed GUID.") }
    }
    $errors
}

function New-AZRActionXml {
    param($Manifest, [string]$Target, $Node, [string]$Launcher)
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
            # -STA: WPF windows (results, system information, secrets) need a single-threaded apartment.
            $params = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}" -Action {1} {2} -SiteServer "##SUB:__Server##" -Namespace "##SUB:__Namespace##"' -f $Launcher, $a.Id, $Node.TargetArgs
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
$nodes = Import-PowerShellDataFile -Path $NodesPath
$problems = @(Test-AZRManifestDefinition -Manifest $manifest -Nodes $nodes)
if ($problems.Count) { throw ("Action manifest is invalid:`n  " + ($problems -join "`n  ")) }

foreach ($target in $nodes.Keys) {
    $node = $nodes[$target]
    if (-not $node.Guid) { continue }
    $hasActions = @($manifest.Groups.Actions | Where-Object { $_.Targets -contains $target }).Count -gt 0
    if (-not $hasActions) { continue }
    $dir = Join-Path $OutputPath $node.Guid
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $xml = New-AZRActionXml -Manifest $manifest -Target $target -Node $node -Launcher $LauncherPath
    [void][xml]$xml   # throws if not well-formed
    [System.IO.File]::WriteAllText((Join-Path $dir 'AZR-RightClickTools.xml'), $xml, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Verbose "Extension XML written to $OutputPath"
