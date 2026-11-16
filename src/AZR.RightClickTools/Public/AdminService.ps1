function Invoke-AZRAdminService {
    <#
    .SYNOPSIS
        Calls the ConfigMgr Administration Service (REST/OData) and returns the result, following @odata.nextLink paging.
    .DESCRIPTION
        Uses the current Windows identity (Kerberos/NTLM) unless -Credential is given. The server name and path are validated,
        query values are URL-encoded, and a paging link that points to a different host is refused.
    .EXAMPLE
        Invoke-AZRAdminService -Server cm01.corp.example -Path 'wmi/SMS_R_System' -Query @{ '$filter' = "Name eq 'PC01'"; '$select' = 'Name,ResourceId' }
    .PARAMETER BaseUri
        Overrides https://<Server>/AdminService (used by tests and unusual deployments).
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Get', 'Post', 'Patch', 'Delete')][string]$Method = 'Get',
        [System.Collections.IDictionary]$Query,
        $Body,
        [pscredential]$Credential,
        [string]$BaseUri,
        [ValidateRange(1, 500)][int]$MaxPages = 50
    )
    if (-not $BaseUri) {
        if (-not $Server) { $Server = (Get-AZRSettings).AdminServiceServer }
        if (-not $Server) { throw 'No AdminService server given. Pass -Server or set AdminServiceServer in settings.' }
        $null = Assert-AZRComputerName -ComputerName $Server
        $BaseUri = "https://$Server/AdminService"
    }
    if ($Path -notmatch '^[A-Za-z0-9_\-\./\(\)]+$' -or $Path -match '\.\.') { throw "Invalid AdminService path: '$Path'" }
    $uri = '{0}/{1}' -f $BaseUri.TrimEnd('/'), $Path.TrimStart('/')
    if ($Query -and $Query.Count) {
        $uri += '?' + ((($Query.Keys | Sort-Object) | ForEach-Object { '{0}={1}' -f $_, [uri]::EscapeDataString([string]$Query[$_]) }) -join '&')
    }
    $baseHost = ([uri]$uri).Authority
    $common = @{ Method = $Method; ContentType = 'application/json'; ErrorAction = 'Stop' }
    if ($Credential) { $common.Credential = $Credential } else { $common.UseDefaultCredentials = $true }
    if ($null -ne $Body) { $common.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 6 -Compress } }

    $results = New-Object System.Collections.Generic.List[object]
    $page = 0
    while ($uri) {
        $page++
        if ($page -gt $MaxPages) { throw "AdminService paging stopped after $MaxPages pages." }
        try { $resp = Invoke-RestMethod -Uri $uri @common }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
            $hint = switch ($status) { 401 { ' (not authorised: check ConfigMgr role/permissions)' } 403 { ' (forbidden: check ConfigMgr role/permissions)' } 404 { ' (not found: check the path and that the AdminService is installed)' } default { '' } }
            throw "AdminService call failed$hint`: $($_.Exception.Message)"
        }
        if ($null -ne $resp -and $resp.PSObject.Properties.Name -contains 'value') { foreach ($v in @($resp.value)) { $results.Add($v) } }
        elseif ($null -ne $resp) { $results.Add($resp) }
        $next = if ($null -ne $resp) { $resp.'@odata.nextLink' } else { $null }
        if ($next) {
            if (([uri]$next).Authority -ne $baseHost) { throw 'AdminService returned a paging link to a different host; refusing to follow it.' }
            $uri = $next
        }
        else { $uri = $null }
        $common.Remove('Body')   # paging requests are always GET without a body
    }
    $results.ToArray()
}
