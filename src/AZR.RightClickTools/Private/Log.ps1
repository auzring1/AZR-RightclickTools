function Get-AZRLogPath {
    $root = if ($env:AZR_LOG_DIR) { $env:AZR_LOG_DIR }
            elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'AZR-RightClickTools\Logs' }
            else { Join-Path ([System.IO.Path]::GetTempPath()) 'AZR-RightClickTools' }
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    Join-Path $root ('azr-{0:yyyyMMdd}.log' -f (Get-Date))
}

function Write-AZRLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Warn', 'Error')][string]$Level = 'Info'
    )
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2} ({3})' -f (Get-Date), $Level.ToUpper(), $Message, $env:USERNAME
    try { Add-Content -LiteralPath (Get-AZRLogPath) -Value $line } catch { Write-Verbose "Log write failed: $_" }
    Write-Verbose $line
}
