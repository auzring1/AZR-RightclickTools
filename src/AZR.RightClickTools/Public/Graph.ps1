function Get-AZRGraphScope {
    <#
    .SYNOPSIS
        Least-privilege Microsoft Graph delegated scopes per AZR feature. Documented so tenant admins know what each feature asks for.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('DeviceLookup', 'BitLockerKeys', 'Laps')][string[]]$Feature)
    $map = @{
        DeviceLookup  = @('Device.Read.All')
        BitLockerKeys = @('BitLockerKey.Read.All', 'Device.Read.All')
        Laps          = @('DeviceLocalCredential.Read.All', 'Device.Read.All')
    }
    $Feature | ForEach-Object { $map[$_] } | Select-Object -Unique
}

function Connect-AZRGraph {
    <#
    .SYNOPSIS
        Signs in to Microsoft Graph (delegated, interactive) with only the scopes the requested features need.
    .DESCRIPTION
        Wraps Connect-MgGraph from the MIT-licensed Microsoft.Graph.Authentication module. No secrets or refresh tokens are
        stored by AZR; the Graph SDK keeps its own token cache for the signed-in user.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('DeviceLookup', 'BitLockerKeys', 'Laps')][string[]]$Feature)
    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        throw "Microsoft Graph PowerShell is not installed. Run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }
    $scopes = Get-AZRGraphScope -Feature $Feature
    $ctx = $null
    try { $ctx = Get-MgContext } catch { $ctx = $null }
    $missing = @($scopes | Where-Object { -not $ctx -or $ctx.Scopes -notcontains $_ })
    if (-not $missing.Count) { return $ctx }
    Write-AZRLog -Message "Connecting to Graph with scopes: $($scopes -join ', ')"
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null
    Get-MgContext
}

function Invoke-AZRGraph {
    <#
    .SYNOPSIS
        Calls Microsoft Graph through the signed-in Graph SDK session and follows @odata.nextLink paging.
    .EXAMPLE
        Invoke-AZRGraph -Uri "/v1.0/devices?`$filter=displayName eq 'PC01'&`$select=id,deviceId"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method = 'GET',
        $Body,
        [ValidateRange(1, 500)][int]$MaxPages = 50
    )
    if ($Uri -notmatch '^/(v1\.0|beta)/[A-Za-z0-9_/\-\.\(\)\$\?=&,%'' ]+$') { throw "Invalid Graph URI (use a relative /v1.0/... or /beta/... path): '$Uri'" }
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) { throw 'Microsoft Graph PowerShell is not installed or not connected. Use Connect-AZRGraph first.' }
    $results = New-Object System.Collections.Generic.List[object]
    $next = "https://graph.microsoft.com$Uri"
    $page = 0
    while ($next) {
        $page++
        if ($page -gt $MaxPages) { throw "Graph paging stopped after $MaxPages pages." }
        $p = @{ Method = $Method; Uri = $next; ErrorAction = 'Stop' }
        if ($null -ne $Body -and $page -eq 1) { $p.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 6 -Compress } }
        try { $resp = Invoke-MgGraphRequest @p }
        catch { throw "Graph call failed: $($_.Exception.Message)" }
        if ($resp -is [System.Collections.IDictionary] -and $resp.Contains('value')) { foreach ($v in @($resp['value'])) { $results.Add($v) } }
        elseif ($null -ne $resp) { $results.Add($resp) }
        $next = $null
        if ($resp -is [System.Collections.IDictionary] -and $resp.Contains('@odata.nextLink')) {
            $link = [string]$resp['@odata.nextLink']
            if (([uri]$link).Authority -ne 'graph.microsoft.com') { throw 'Graph returned a paging link to a different host; refusing to follow it.' }
            $next = $link
        }
    }
    $results.ToArray()
}
