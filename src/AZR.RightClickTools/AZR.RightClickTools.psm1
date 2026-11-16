# AZR.RightClickTools root module: dot-source Private then Public.
$ErrorActionPreference = 'Stop'
foreach ($folder in 'Private', 'Public') {
    $path = Join-Path $PSScriptRoot $folder
    Get-ChildItem -Path $path -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { . $_.FullName }
}
