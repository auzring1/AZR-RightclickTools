# Power, network and messaging (roadmap D6, D12).

function Get-AZRMagicPacket {
    <# Builds a Wake-on-LAN magic packet: 6 x 0xFF followed by the MAC address 16 times (102 bytes). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MacAddress)
    $hex = Assert-AZRMacAddress -MacAddress $MacAddress
    $mac = [byte[]]::new(6)
    for ($i = 0; $i -lt 6; $i++) { $mac[$i] = [Convert]::ToByte($hex.Substring(2 * $i, 2), 16) }
    $packet = New-Object byte[] 102
    for ($i = 0; $i -lt 6; $i++) { $packet[$i] = 0xFF }
    for ($n = 0; $n -lt 16; $n++) { [Array]::Copy($mac, 0, $packet, 6 + 6 * $n, 6) }
    , $packet
}

function Send-AZRWakeOnLan {
    <#
    .SYNOPSIS
        Sends a Wake-on-LAN magic packet (UDP) from this computer. The packet must be able to reach the target's
        subnet: use -BroadcastAddress with the subnet-directed broadcast (e.g. 10.1.2.255) for other subnets.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string[]]$MacAddress,
        [string]$BroadcastAddress = '255.255.255.255',
        [ValidateRange(1, 65535)][int]$Port = 9
    )
    begin {
        $ip = $null
        if (-not [System.Net.IPAddress]::TryParse($BroadcastAddress, [ref]$ip)) { throw "Invalid broadcast address: '$BroadcastAddress'" }
    }
    process {
        foreach ($m in $MacAddress) {
            $packet = Get-AZRMagicPacket -MacAddress $m
            if ($PSCmdlet.ShouldProcess($m, "Send magic packet to ${BroadcastAddress}:$Port")) {
                $udp = New-Object System.Net.Sockets.UdpClient
                try {
                    $udp.EnableBroadcast = $true
                    [void]$udp.Send($packet, $packet.Length, (New-Object System.Net.IPEndPoint($ip, $Port)))
                }
                finally { $udp.Close() }
                [pscustomobject]@{ MacAddress = (Assert-AZRMacAddress -MacAddress $m); Broadcast = $BroadcastAddress; Port = $Port; Sent = $true }
            }
        }
    }
}

function Get-AZRDeviceMac {
    <#
    .SYNOPSIS
        Looks up MAC addresses from the SMS Provider (SMS_R_System). Pass -CollectionId to get every member, or -ComputerName for one device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [string]$ComputerName,
        [string]$CollectionId
    )
    $null = Assert-AZRComputerName -ComputerName $SiteServer
    $SiteCode = Assert-AZRSiteCode -SiteCode $SiteCode
    if ($CollectionId) {
        $CollectionId = Assert-AZRCollectionId -CollectionId $CollectionId
        $query = "SELECT Name, MACAddresses FROM SMS_R_System WHERE ResourceID IN (SELECT ResourceID FROM SMS_FullCollectionMembership WHERE CollectionID = '$CollectionId')"
    }
    elseif ($ComputerName) {
        $null = Assert-AZRComputerName -ComputerName $ComputerName
        $query = New-AZRWql -Class SMS_R_System -Property Name, MACAddresses -Equals @{ Name = $ComputerName }
    }
    else { throw 'Pass -ComputerName or -CollectionId.' }
    Invoke-AZRWithCimSession -ComputerName $SiteServer -ScriptBlock {
        param($s)
        Get-AZRCimQuery -Session $s -Namespace "root\sms\site_$SiteCode" -Query $query | ForEach-Object {
            $macs = @($_.MACAddresses | Where-Object { $_ })
            [pscustomobject]@{ ComputerName = $_.Name; MacAddress = $macs }
        }
    }
}

function Restart-AZRComputer {
    <#
    .SYNOPSIS
        Restarts a computer with a delay and a message to logged-on users (shutdown.exe on the target).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName,
        [ValidateRange(0, 86400)][int]$DelaySeconds = 60,
        [string]$Message = 'This computer will restart for maintenance',
        [pscredential]$Credential
    )
    process {
        foreach ($c in $ComputerName) {
            if ($PSCmdlet.ShouldProcess($c, "Restart in $DelaySeconds s")) {
                Invoke-AZRRemoteTemplate -ComputerName $c -Template Restart -Parameter @{ DelaySeconds = $DelaySeconds; Text = $Message } -Credential $Credential -Label 'Restart'
            }
        }
    }
}

function Stop-AZRComputer {
    <#
    .SYNOPSIS
        Shuts a computer down with a delay and a message (shutdown.exe on the target). A powered-off device needs Wake-on-LAN to come back.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName,
        [ValidateRange(0, 86400)][int]$DelaySeconds = 60,
        [string]$Message = 'This computer will shut down for maintenance',
        [pscredential]$Credential
    )
    process {
        foreach ($c in $ComputerName) {
            if ($PSCmdlet.ShouldProcess($c, "Shut down in $DelaySeconds s")) {
                Invoke-AZRRemoteTemplate -ComputerName $c -Template Shutdown -Parameter @{ DelaySeconds = $DelaySeconds; Text = $Message } -Credential $Credential -Label 'Shutdown'
            }
        }
    }
}

function Stop-AZRPendingShutdown {
    <# Cancels a delayed restart or shutdown (shutdown.exe /a). #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName, [pscredential]$Credential)
    process {
        foreach ($c in $ComputerName) {
            if ($PSCmdlet.ShouldProcess($c, 'Cancel pending shutdown')) {
                Invoke-AZRRemoteTemplate -ComputerName $c -Template AbortShutdown -Credential $Credential -Label 'Cancel shutdown'
            }
        }
    }
}

function Invoke-AZRGpUpdate {
    <# Runs gpupdate /force on the target (computer policy, as SYSTEM). #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName, [pscredential]$Credential)
    process {
        foreach ($c in $ComputerName) {
            if ($PSCmdlet.ShouldProcess($c, 'gpupdate /force')) {
                Invoke-AZRRemoteTemplate -ComputerName $c -Template GpUpdate -Credential $Credential -Label 'gpupdate'
            }
        }
    }
}

function Send-AZRNotification {
    <#
    .SYNOPSIS
        Shows a message to the logged-on users (msg.exe on the target). Text is limited to letters, digits and basic punctuation.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][string[]]$ComputerName,
        [Parameter(Mandatory)][string]$Message,
        [ValidateRange(5, 86400)][int]$DisplaySeconds = 300,
        [pscredential]$Credential
    )
    begin { $null = Assert-AZRMessageText -Text $Message }
    process {
        foreach ($c in $ComputerName) {
            if ($PSCmdlet.ShouldProcess($c, 'Send notification')) {
                Invoke-AZRRemoteTemplate -ComputerName $c -Template Notify -Parameter @{ Text = $Message; DisplaySeconds = $DisplaySeconds } -Credential $Credential -Label 'Notification'
            }
        }
    }
}
