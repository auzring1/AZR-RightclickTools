<#
.SYNOPSIS
    Lab helper: lists the console node GUIDs and the ##SUB:...## placeholders found in your installed ConfigMgr console.
.DESCRIPTION
    Microsoft's own extension XML files (and any other vendor files) live in one folder per node:
        <Console>\XmlStorage\Extensions\Actions\<node GUID>\*.xml
    This tool reads them and reports, per node GUID, which placeholders are used and which menu names appear, so you
    can recognise the node (e.g. "Delete" + "Client Notification" = Devices) and confirm the values in src\Nodes.psd1.
    It also scans XmlStorage\ConsoleRoot for GUID-bearing elements with a name, which can help map names to GUIDs.
    It only reads files and changes nothing.
.EXAMPLE
    .\tools\Get-AZRConsoleNodes.ps1
.EXAMPLE
    .\tools\Get-AZRConsoleNodes.ps1 -ConsoleDir 'D:\ConfigMgr\AdminConsole' | Format-Table -AutoSize
#>
[CmdletBinding()]
param([string]$ConsoleDir)

$guidPattern = '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

function Get-AZRConsoleNodeInfo {
    <# Reads an Extensions\Actions folder and returns one record per node GUID folder. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ActionsPath)
    foreach ($dir in Get-ChildItem -LiteralPath $ActionsPath -Directory -ErrorAction SilentlyContinue) {
        if ($dir.Name -notmatch "^$guidPattern$") { continue }
        $placeholders = New-Object System.Collections.Generic.SortedSet[string]
        $names = New-Object System.Collections.Generic.SortedSet[string]
        $files = @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.xml' -File -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $text) { continue }
            foreach ($m in [regex]::Matches($text, '##SUB:([^#]+)##')) { [void]$placeholders.Add($m.Groups[1].Value) }
            foreach ($m in [regex]::Matches($text, 'DisplayName="([^"]+)"')) { [void]$names.Add($m.Groups[1].Value) }
        }
        [pscustomobject]@{
            Guid         = $dir.Name
            Files        = $files.Count
            Placeholders = @($placeholders)
            MenuNames    = @($names | Select-Object -First 12)
        }
    }
}

function Get-AZRConsoleRootNames {
    <# Best effort: elements under ConsoleRoot that carry a GUID attribute and a readable name. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RootPath)
    foreach ($f in Get-ChildItem -LiteralPath $RootPath -Filter '*.xml' -File -ErrorAction SilentlyContinue) {
        try { $xml = [xml](Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop) } catch { continue }
        foreach ($node in $xml.SelectNodes('//*[@ID or @Id or @NodeGuid]')) {
            $id = @($node.GetAttribute('ID'), $node.GetAttribute('Id'), $node.GetAttribute('NodeGuid')) | Where-Object { $_ -match "^$guidPattern$" } | Select-Object -First 1
            $name = @($node.GetAttribute('DisplayName'), $node.GetAttribute('Name')) | Where-Object { $_ } | Select-Object -First 1
            if ($id -and $name) { [pscustomobject]@{ Guid = $id; Name = $name; File = $f.Name } }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $ConsoleDir -and $env:SMS_ADMIN_UI_PATH) {
        $bin = $env:SMS_ADMIN_UI_PATH.TrimEnd('\')
        $ConsoleDir = if ((Split-Path -Leaf $bin) -eq 'i386') { Split-Path -Parent (Split-Path -Parent $bin) } else { Split-Path -Parent $bin }
    }
    if (-not $ConsoleDir -or -not (Test-Path -LiteralPath $ConsoleDir)) { throw 'ConfigMgr console not found. Pass -ConsoleDir <path to AdminConsole>.' }
    $actions = Join-Path $ConsoleDir 'XmlStorage\Extensions\Actions'
    $root = Join-Path $ConsoleDir 'XmlStorage\ConsoleRoot'
    $names = @{}
    if (Test-Path -LiteralPath $root) { foreach ($n in Get-AZRConsoleRootNames -RootPath $root) { $names[$n.Guid.ToLower()] = $n.Name } }
    Get-AZRConsoleNodeInfo -ActionsPath $actions | ForEach-Object {
        $_ | Add-Member -NotePropertyName KnownName -NotePropertyValue $names[$_.Guid.ToLower()] -PassThru
    }
}
