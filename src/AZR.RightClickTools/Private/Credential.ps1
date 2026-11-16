# Alternate credentials, stored per user with DPAPI (Export-Clixml encrypts the password for this
# user on this machine only). Nothing is ever stored as plain text.

function Get-AZRCredentialDirectory {
    $root = if ($env:AZR_CREDENTIAL_DIR) { $env:AZR_CREDENTIAL_DIR }
            elseif ($env:APPDATA) { Join-Path $env:APPDATA 'AZR-RightClickTools\Credentials' }
            else { Join-Path ([System.IO.Path]::GetTempPath()) 'AZR-RightClickTools-Credentials' }
    $root
}

function Get-AZRCredentialFile {
    param([Parameter(Mandatory)][string]$Name)
    $Name = Assert-AZRCredentialName -Name $Name
    Join-Path (Get-AZRCredentialDirectory) "$Name.cred.xml"
}

function Save-AZRCredential {
    <#
    .SYNOPSIS
        Saves a credential under a short name (DPAPI-protected, current user and machine only).
    .EXAMPLE
        Save-AZRCredential -Name Corp -Credential (Get-Credential)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][pscredential]$Credential
    )
    $file = Get-AZRCredentialFile -Name $Name
    if ($PSCmdlet.ShouldProcess($file, 'Save credential')) {
        $dir = Split-Path -Parent $file
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Credential | Export-Clixml -LiteralPath $file
        Write-AZRLog -Message "Stored credential '$Name' for $($Credential.UserName)"
    }
}

function Get-AZRStoredCredential {
    <#
    .SYNOPSIS
        Loads a saved credential, or returns $null when it does not exist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $file = Get-AZRCredentialFile -Name $Name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    try { Import-Clixml -LiteralPath $file -ErrorAction Stop }
    catch { Write-AZRLog -Level Warn -Message "Credential '$Name' could not be read: $($_.Exception.Message)"; $null }
}

function Remove-AZRStoredCredential {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)
    $file = Get-AZRCredentialFile -Name $Name
    if ((Test-Path -LiteralPath $file) -and $PSCmdlet.ShouldProcess($file, 'Remove credential')) {
        Remove-Item -LiteralPath $file -Force
    }
}

function Get-AZRDefaultCredential {
    <# The credential named by the DefaultCredentialName setting, or $null. #>
    $name = (Get-AZRSettings).DefaultCredentialName
    if (-not $name) { return $null }
    try { Get-AZRStoredCredential -Name $name } catch { $null }
}
