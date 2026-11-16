function ConvertTo-AZRSafeRecord {
    <#
    .SYNOPSIS
        Flattens an object for grids and exports: SecureString values become '[hidden]' (so secrets can never be
        exported or copied by accident), collections are joined, nested objects use their string form.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)]$InputObject)
    process {
        $rec = [ordered]@{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $v = $p.Value
            if ($v -is [securestring]) { $rec[$p.Name] = '[hidden]' }
            elseif ($null -eq $v) { $rec[$p.Name] = $null }
            elseif ($v -is [string] -or $v -is [ValueType]) { $rec[$p.Name] = $v }
            elseif ($v -is [System.Collections.IEnumerable]) {
                $rec[$p.Name] = (@($v) | ForEach-Object { if ($_ -is [securestring]) { '[hidden]' } else { [string]$_ } }) -join '; '
            }
            else { $rec[$p.Name] = [string]$v }
        }
        [pscustomobject]$rec
    }
}

function Protect-AZRCsvCell {
    <# Prefixes cells that a spreadsheet would run as a formula (= + - @) so exported text stays text. #>
    param($Value)
    if ($Value -is [string] -and $Value.Length -gt 0 -and $Value[0] -in '=', '+', '-', '@', "`t", "`r") { return "'" + $Value }
    $Value
}

function Export-AZRResult {
    <#
    .SYNOPSIS
        Exports objects to CSV, JSON or the clipboard. Secrets (SecureString) are never written.
    .DESCRIPTION
        Without -Path the file goes to the ExportDirectory setting (or the temp folder) with a timestamped name.
        CSV cells that start with = + - @ are prefixed with an apostrophe to prevent spreadsheet formula injection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$InputObject,
        [ValidateSet('Csv', 'Json', 'Clipboard')][string]$Format = 'Csv',
        [string]$Path,
        [string]$Name = 'azr-result'
    )
    begin { $rows = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $rows.Add((ConvertTo-AZRSafeRecord -InputObject $InputObject)) } }
    end {
        if ($Format -eq 'Json') {
            $text = ConvertTo-Json -InputObject $rows.ToArray() -Depth 4
        }
        else {
            $guarded = foreach ($r in $rows) {
                $o = [ordered]@{}
                foreach ($p in $r.PSObject.Properties) { $o[$p.Name] = Protect-AZRCsvCell -Value $p.Value }
                [pscustomobject]$o
            }
            $text = (@($guarded) | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
        }
        if ($Format -eq 'Clipboard') {
            if ($rows.Count -eq 0) { return }
            Set-Clipboard -Value $text
            return
        }
        if (-not $Path) {
            $dir = (Get-AZRSettings).ExportDirectory
            if (-not $dir) { $dir = [System.IO.Path]::GetTempPath() }
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $ext = if ($Format -eq 'Json') { 'json' } else { 'csv' }
            $safeName = $Name -replace '[^A-Za-z0-9_\-]', '_'
            $Path = Join-Path $dir ('{0}-{1:yyyyMMdd-HHmmss}.{2}' -f $safeName, (Get-Date), $ext)
        }
        [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
        Write-AZRLog -Message "Exported $($rows.Count) row(s) to $Path"
        $Path
    }
}
