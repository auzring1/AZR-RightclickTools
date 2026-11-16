function Show-AZRWindow {
    <#
    .SYNOPSIS
        Shows the AZR WPF host window: tabs of data grids with filter, CSV/JSON/clipboard export and optional action buttons.
    .EXAMPLE
        Show-AZRWindow -Title 'Demo' -Tab @(@{ Name = 'Services'; Loader = { Get-AZRService -ComputerName PC01 } })
    .PARAMETER Tab
        @{ Name = '...'; Data = <objects> } for ready data or @{ Name = '...'; Loader = { ... } } to load when the tab is first shown.
    .PARAMETER Action
        @{ Name = '...'; Script = { param($row) ... }; Risk = 'Change'|'Destructive'; NeedsSelection = $true } buttons. Each click
        is confirmed according to Risk and written to the audit log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Tab,
        [object[]]$Action = @(),
        [string[]]$Target = @()
    )
    if (-not (Test-AZRWindows)) { throw 'The WPF window host requires Windows.' }
    Invoke-AZRSta -ArgumentList @($Title, $Tab, $Action, $Target) -ScriptBlock {
        param($Title, $Tab, $Action, $Target)
        # Run inside the module so private helpers are visible, also when this is a fresh STA runspace.
        & (Get-Module AZR.RightClickTools) {
            param($Title, $Tab, $Action, $Target)
            $w = New-AZRWindowObject -Title $Title -Tab $Tab -Action $Action -Target $Target
            [void]$w.Window.ShowDialog()
        } $Title $Tab $Action $Target
    }
}

function Show-AZRSecretWindow {
    <#
    .SYNOPSIS
        Shows secret values (recovery keys, passwords) in a window only. Nothing is logged or exported.
        A Copy button puts a value on the clipboard and clears it again after the configured number of seconds
        (and when the window closes), but only if the clipboard still holds that value.
    .PARAMETER Item
        @{ Label = 'Volume C:'; Value = <SecureString> } entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Item,
        [string]$Notice = 'This secret is shown once and is not stored or logged. Close this window when finished.',
        [int]$ClearSeconds = 0
    )
    if (-not (Test-AZRWindows)) { throw 'The secret window requires Windows.' }
    if ($ClearSeconds -le 0) { $ClearSeconds = (Get-AZRSettings).SecretClipboardClearSeconds }
    Invoke-AZRSta -ArgumentList @($Title, $Item, $Notice, $ClearSeconds) -ScriptBlock {
        param($Title, $Item, $Notice, $ClearSeconds)
        & (Get-Module AZR.RightClickTools) {
            param($Title, $Item, $Notice, $ClearSeconds)
            $w = New-AZRSecretWindowObject -Title $Title -Item $Item -Notice $Notice -ClearSeconds $ClearSeconds
            [void]$w.ShowDialog()
        } $Title $Item $Notice $ClearSeconds
    }
}
