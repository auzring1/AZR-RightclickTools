# WPF host: XAML lives here, styling is plain WPF (no third-party UI libraries). Works in Windows PowerShell 5.1
# and PowerShell 7 on Windows. WPF needs an STA thread; Invoke-AZRSta takes care of that.

function Get-AZRWindowXaml {
    @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="1050" Height="640" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="12">
  <DockPanel Margin="8">
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,6">
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <Button x:Name="BtnRefresh" Content="Refresh" Margin="4,0,0,0" Padding="10,3"/>
        <Button x:Name="BtnCsv" Content="Export CSV" Margin="4,0,0,0" Padding="10,3"/>
        <Button x:Name="BtnJson" Content="Export JSON" Margin="4,0,0,0" Padding="10,3"/>
        <Button x:Name="BtnCopy" Content="Copy" Margin="4,0,0,0" Padding="10,3"/>
      </StackPanel>
      <TextBlock Text="Filter:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="FilterBox" VerticalContentAlignment="Center" Padding="4,2"/>
    </DockPanel>
    <WrapPanel x:Name="ActionBar" DockPanel.Dock="Top" Margin="0,0,0,6"/>
    <TextBlock x:Name="StatusText" DockPanel.Dock="Bottom" Margin="0,6,0,0" Foreground="#555555"/>
    <TabControl x:Name="Tabs"/>
  </DockPanel>
</Window>
'@
}

function Get-AZRSecretWindowXaml {
    @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="640" SizeToContent="Height" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="12"
        ResizeMode="CanMinimize" Topmost="True">
  <StackPanel Margin="12">
    <TextBlock x:Name="Notice" TextWrapping="Wrap" Margin="0,0,0,8" Foreground="#9a3412"/>
    <StackPanel x:Name="Items"/>
    <TextBlock x:Name="StatusText" Margin="0,8,0,0" Foreground="#555555"/>
    <Button x:Name="BtnClose" Content="Close" HorizontalAlignment="Right" Padding="14,3" Margin="0,8,0,0"/>
  </StackPanel>
</Window>
'@
}

function Invoke-AZRSta {
    <# Runs a script block on an STA thread (required by WPF); reuses the current thread when it already is STA. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') { return & $ScriptBlock @ArgumentList }
    $mod = $ExecutionContext.SessionState.Module
    $manifest = Join-Path $mod.ModuleBase ($mod.Name + '.psd1')
    $iss = [initialsessionstate]::CreateDefault()
    if ($env:OS -eq 'Windows_NT') { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass }
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddCommand('Import-Module').AddParameter('Name', $manifest).AddParameter('Force').AddParameter('ErrorAction', 'Stop')
        [void]$ps.AddStatement().AddScript($ScriptBlock.ToString())
        foreach ($a in $ArgumentList) { [void]$ps.AddArgument($a) }
        $out = $ps.Invoke()
        if ($ps.Streams.Error.Count -gt 0) { throw $ps.Streams.Error[0].Exception }
        $out
    }
    finally { $rs.Close(); $rs.Dispose() }
}

function Test-AZRRowMatch {
    <# Case-insensitive "any property contains text" match used by the filter box. #>
    param($Row, [string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    foreach ($p in $Row.PSObject.Properties) {
        if ($null -ne $p.Value -and ([string]$p.Value).IndexOf($Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    $false
}

function New-AZRWindowObject {
    <#
    .SYNOPSIS
        Builds (but does not show) the host window. Returns @{ Window; State }. State holds the tab list for tests.
    .PARAMETER Tab
        Array of @{ Name; Data = <objects> } or @{ Name; Loader = <scriptblock returning objects> } (loaded when the tab is first shown).
    .PARAMETER Action
        Array of @{ Name; Script = <scriptblock taking the selected row>; Risk; NeedsSelection } buttons.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Tab,
        [object[]]$Action = @(),
        [string[]]$Target = @()
    )
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $window = [System.Windows.Markup.XamlReader]::Parse((Get-AZRWindowXaml))
    $window.Title = $Title
    $state = @{
        Window  = $window
        Tabs    = New-Object System.Collections.Generic.List[object]
        Target  = $Target
        Title   = $Title
        Actions = $Action
        Name    = ($Title -replace '[^A-Za-z0-9_\-]', '_')
        ActionButtons = @()
    }
    $state.TabControl = $window.FindName('Tabs')
    $state.Status = $window.FindName('StatusText')
    $state.Filter = $window.FindName('FilterBox')
    $actionBar = $window.FindName('ActionBar')

    foreach ($t in $Tab) {
        $grid = New-Object System.Windows.Controls.DataGrid
        $grid.IsReadOnly = $true
        $grid.AutoGenerateColumns = $true
        $grid.SelectionMode = 'Extended'
        $grid.CanUserAddRows = $false
        $item = New-Object System.Windows.Controls.TabItem
        $item.Header = $t.Name
        $item.Content = $grid
        [void]$state.TabControl.Items.Add($item)
        # Re-create script blocks here so they are bound to this module and runspace.
        $loader = if ($t.Loader) { [scriptblock]::Create($t.Loader.ToString()) } else { $null }
        $entry = @{ Name = $t.Name; Grid = $grid; Loader = $loader; Loaded = $false; Data = $t.Data }
        $state.Tabs.Add($entry)
        if (-not $t.Loader) { Set-AZRWindowTabData -State $state -Entry $entry -Rows $t.Data }
    }

    foreach ($a in $Action) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $a.Name
        $btn.Margin = '0,0,6,0'
        $btn.Padding = '10,3'
        $btn.Tag = @{ Tab = $a.Tab; Name = $a.Name; Risk = $a.Risk; NeedsSelection = [bool]$a.NeedsSelection; Script = [scriptblock]::Create($a.Script.ToString()) }
        $btn.Add_Click({ param($s, $e) Invoke-AZRWindowAction -State $script:AZRWindowState -Action $s.Tag })
        [void]$actionBar.Children.Add($btn)
        $state.ActionButtons += $btn
    }
    if (-not $Action) { $actionBar.Visibility = 'Collapsed' }

    $script:AZRWindowState = $state
    $state.TabControl.Add_SelectionChanged({ param($s, $e) if ($e.OriginalSource -eq $s) { Update-AZRWindowTab -State $script:AZRWindowState; Update-AZRActionBar -State $script:AZRWindowState } })
    $state.Filter.Add_TextChanged({ Update-AZRWindowFilter -State $script:AZRWindowState })
    $window.FindName('BtnRefresh').Add_Click({ Update-AZRWindowTab -State $script:AZRWindowState -Force })
    $window.FindName('BtnCsv').Add_Click({ Export-AZRWindowRows -State $script:AZRWindowState -Format Csv })
    $window.FindName('BtnJson').Add_Click({ Export-AZRWindowRows -State $script:AZRWindowState -Format Json })
    $window.FindName('BtnCopy').Add_Click({ Export-AZRWindowRows -State $script:AZRWindowState -Format Clipboard })
    $window.Add_Loaded({ Update-AZRWindowTab -State $script:AZRWindowState; Update-AZRActionBar -State $script:AZRWindowState })
    @{ Window = $window; State = $state }
}

function Set-AZRWindowTabData {
    param($State, $Entry, $Rows)
    $safe = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($r in @($Rows)) { if ($null -ne $r) { $safe.Add((ConvertTo-AZRSafeRecord -InputObject $r)) } }
    $Entry.Grid.ItemsSource = $safe
    $Entry.Loaded = $true
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($safe)
    $view.Filter = [Predicate[object]]{ param($row) Test-AZRRowMatch -Row $row -Text $script:AZRWindowState.Filter.Text }
    $State.Status.Text = '{0}: {1} row(s)' -f $Entry.Name, $safe.Count
}

function Update-AZRActionBar {
    <# Shows only the action buttons that belong to the current tab (buttons without a Tab show everywhere). #>
    param($State)
    $entry = Get-AZRCurrentTabEntry -State $State
    foreach ($b in $State.ActionButtons) {
        $show = (-not $b.Tag.Tab) -or ($entry -and $entry.Name -eq $b.Tag.Tab)
        $b.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
    }
}

function Get-AZRCurrentTabEntry {
    param($State)
    $idx = $State.TabControl.SelectedIndex
    if ($idx -lt 0) { return $null }
    $State.Tabs[$idx]
}

function Update-AZRWindowTab {
    param($State, [switch]$Force)
    $entry = Get-AZRCurrentTabEntry -State $State
    if (-not $entry -or (-not $entry.Loader) -or ($entry.Loaded -and -not $Force)) { return }
    $State.Status.Text = "Loading $($entry.Name)..."
    $State.Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try { Set-AZRWindowTabData -State $State -Entry $entry -Rows (& $entry.Loader) }
    catch { $State.Status.Text = "Error: $($_.Exception.Message)"; Write-AZRLog -Level Error -Message "Window tab '$($entry.Name)' failed: $($_.Exception.Message)" }
    finally { $State.Window.Cursor = $null }
}

function Update-AZRWindowFilter {
    param($State)
    $entry = Get-AZRCurrentTabEntry -State $State
    if ($entry -and $entry.Grid.ItemsSource) { [System.Windows.Data.CollectionViewSource]::GetDefaultView($entry.Grid.ItemsSource).Refresh() }
}

function Export-AZRWindowRows {
    param($State, [string]$Format)
    $entry = Get-AZRCurrentTabEntry -State $State
    if (-not $entry -or -not $entry.Grid.ItemsSource) { return }
    $rows = @([System.Windows.Data.CollectionViewSource]::GetDefaultView($entry.Grid.ItemsSource) | ForEach-Object { $_ })
    if ($rows.Count -eq 0) { $State.Status.Text = 'Nothing to export.'; return }
    if ($Format -eq 'Clipboard') { $rows | Export-AZRResult -Format Clipboard; $State.Status.Text = "Copied $($rows.Count) row(s)."; return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $ext = if ($Format -eq 'Json') { 'json' } else { 'csv' }
    $dlg.Filter = "$($ext.ToUpper()) file (*.$ext)|*.$ext"
    $dlg.FileName = '{0}-{1}.{2}' -f $State.Name, $entry.Name, $ext
    $dir = (Get-AZRSettings).ExportDirectory
    if ($dir -and (Test-Path -LiteralPath $dir)) { $dlg.InitialDirectory = $dir }
    if ($dlg.ShowDialog()) {
        $rows | Export-AZRResult -Format $Format -Path $dlg.FileName | Out-Null
        $State.Status.Text = "Saved $($rows.Count) row(s) to $($dlg.FileName)"
    }
}

function Invoke-AZRWindowAction {
    param($State, $Action)
    $entry = Get-AZRCurrentTabEntry -State $State
    $selected = @()
    if ($entry) { $selected = @($entry.Grid.SelectedItems) }
    if ($Action.NeedsSelection -and $selected.Count -eq 0) { $State.Status.Text = "Select at least one row first."; return }
    $risk = if ($Action.Risk) { $Action.Risk } else { 'Change' }
    $label = if ($selected.Count) { "$($Action.Name) ($($selected.Count) selected)" } else { $Action.Name }
    $targetText = if ($State.Target.Count) { $State.Target[0] } else { 'target' }
    $approval = Confirm-AZRRisk -Action $label -Risk $risk -Scope Device -Target @($(if ($risk -eq 'Destructive') { $targetText } else { $label }))
    if (-not $approval.Approved) {
        Write-AZRAudit -Action $Action.Name -Target $State.Target -Outcome Cancelled -Risk $risk
        $State.Status.Text = 'Cancelled.'
        return
    }
    try {
        if ($selected.Count) { foreach ($row in $selected) { & $Action.Script $row } } else { & $Action.Script $null }
        Write-AZRAudit -Action $Action.Name -Target $State.Target -Outcome Success -Risk $risk -Detail @{ rows = $selected.Count }
        $State.Status.Text = "$($Action.Name): done."
        Update-AZRWindowTab -State $State -Force
    }
    catch {
        Write-AZRAudit -Action $Action.Name -Target $State.Target -Outcome Failure -Risk $risk -Message $_.Exception.Message
        $State.Status.Text = "$($Action.Name) failed: $($_.Exception.Message)"
    }
}

function ConvertTo-AZRPlainText {
    <# Converts a SecureString to plain text for display in the secret window only. #>
    param([securestring]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function New-AZRSecretWindowObject {
    [CmdletBinding()]
    param([string]$Title, [object[]]$Item, [string]$Notice, [int]$ClearSeconds)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $window = [System.Windows.Markup.XamlReader]::Parse((Get-AZRSecretWindowXaml))
    $window.Title = $Title
    $window.FindName('Notice').Text = $Notice
    $panel = $window.FindName('Items')
    $secretState = @{ LastCopied = $null; Seconds = $ClearSeconds; Status = $window.FindName('StatusText'); Timer = $null }
    foreach ($i in $Item) {
        $plain = if ($i.Value -is [securestring]) { ConvertTo-AZRPlainText -Secure $i.Value } else { [string]$i.Value }
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = [string]$i.Label
        $label.FontWeight = 'SemiBold'
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '0,0,0,8'
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = 'Copy'
        $btn.Padding = '10,3'
        $btn.Margin = '6,0,0,0'
        $btn.Tag = $plain
        [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
        $box = New-Object System.Windows.Controls.TextBox
        $box.Text = $plain
        $box.IsReadOnly = $true
        $box.FontFamily = 'Consolas'
        $box.Padding = '4,3'
        [void]$row.Children.Add($btn)
        [void]$row.Children.Add($box)
        [void]$panel.Children.Add($label)
        [void]$panel.Children.Add($row)
        $btn.Add_Click({ param($s, $e) Copy-AZRSecretToClipboard -State $script:AZRSecretState -Text ([string]$s.Tag) })
    }
    $script:AZRSecretState = $secretState
    $window.FindName('BtnClose').Add_Click({ param($s, $e) $script:AZRSecretState.Window.Close() })
    $secretState.Window = $window
    $window.Add_Closed({ Clear-AZRSecretClipboard -State $script:AZRSecretState })
    $window
}

function Copy-AZRSecretToClipboard {
    param($State, [string]$Text)
    [System.Windows.Clipboard]::SetText($Text)
    $State.LastCopied = $Text
    $State.Status.Text = "Copied. The clipboard is cleared in $($State.Seconds) seconds."
    if ($State.Timer) { $State.Timer.Stop() }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($State.Seconds)
    $timer.Add_Tick({ Clear-AZRSecretClipboard -State $script:AZRSecretState; $script:AZRSecretState.Status.Text = 'Clipboard cleared.' })
    $State.Timer = $timer
    $timer.Start()
}

function Clear-AZRSecretClipboard {
    param($State)
    if ($State.Timer) { $State.Timer.Stop() }
    if ($State.LastCopied) {
        try { if ([System.Windows.Clipboard]::ContainsText() -and [System.Windows.Clipboard]::GetText() -eq $State.LastCopied) { [System.Windows.Clipboard]::Clear() } }
        catch { Write-Verbose "Clipboard clear failed: $_" }
        $State.LastCopied = $null
    }
}
