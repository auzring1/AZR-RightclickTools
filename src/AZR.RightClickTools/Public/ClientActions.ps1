function Get-AZRClientActionList {
    <#
    .SYNOPSIS
        Returns the supported ConfigMgr client actions and their schedule IDs.
    #>
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ Name = 'MachinePolicyRetrieval';   DisplayName = 'Machine Policy Retrieval & Evaluation'; ScheduleId = '{00000000-0000-0000-0000-000000000021}' }
        [pscustomobject]@{ Name = 'MachinePolicyEvaluation';  DisplayName = 'Machine Policy Evaluation';             ScheduleId = '{00000000-0000-0000-0000-000000000022}' }
        [pscustomobject]@{ Name = 'UserPolicyRetrieval';      DisplayName = 'User Policy Retrieval';                 ScheduleId = '{00000000-0000-0000-0000-000000000026}' }
        [pscustomobject]@{ Name = 'UserPolicyEvaluation';     DisplayName = 'User Policy Evaluation';                ScheduleId = '{00000000-0000-0000-0000-000000000027}' }
        [pscustomobject]@{ Name = 'HardwareInventory';        DisplayName = 'Hardware Inventory';                    ScheduleId = '{00000000-0000-0000-0000-000000000001}' }
        [pscustomobject]@{ Name = 'SoftwareInventory';        DisplayName = 'Software Inventory';                    ScheduleId = '{00000000-0000-0000-0000-000000000002}' }
        [pscustomobject]@{ Name = 'DiscoveryDataCollection';  DisplayName = 'Discovery Data Collection';             ScheduleId = '{00000000-0000-0000-0000-000000000003}' }
        [pscustomobject]@{ Name = 'SoftwareUpdatesScan';      DisplayName = 'Software Updates Scan';                 ScheduleId = '{00000000-0000-0000-0000-000000000113}' }
        [pscustomobject]@{ Name = 'SoftwareUpdatesEvaluation';DisplayName = 'Software Updates Deployment Evaluation'; ScheduleId = '{00000000-0000-0000-0000-000000000108}' }
        [pscustomobject]@{ Name = 'ApplicationEvaluation';    DisplayName = 'Application Deployment Evaluation';    ScheduleId = '{00000000-0000-0000-0000-000000000121}' }
    )
}

function Invoke-AZRClientAction {
    <#
    .SYNOPSIS
        Triggers a ConfigMgr client schedule on one or more computers via CIM (root\ccm SMS_Client.TriggerSchedule).
    .EXAMPLE
        Invoke-AZRClientAction -ComputerName PC01 -Action HardwareInventory
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)][string[]]$ComputerName,
        [Parameter(Mandatory)]
        [ValidateScript({ $_ -in (Get-AZRClientActionList).Name })]
        [string]$Action,
        [pscredential]$Credential
    )
    begin { $def = Get-AZRClientActionList | Where-Object Name -eq $Action }
    process {
        foreach ($name in $ComputerName) {
            $result = [ordered]@{ ComputerName = $name; Action = $def.DisplayName; Success = $false; Message = '' }
            try {
                $null = Assert-AZRComputerName -ComputerName $name
                if ($PSCmdlet.ShouldProcess($name, $def.DisplayName)) {
                    Invoke-AZRWithCimSession -ComputerName $name -Credential $Credential -ScriptBlock {
                        param($s)
                        $null = Invoke-CimMethod -CimSession $s -Namespace 'root\ccm' -ClassName 'SMS_Client' `
                            -MethodName 'TriggerSchedule' -Arguments @{ sScheduleID = $def.ScheduleId } -ErrorAction Stop
                    }
                    $result.Success = $true
                    $result.Message = 'Triggered'
                    Write-AZRLog -Message "$($def.Name) triggered on $name"
                }
            }
            catch {
                $result.Message = $_.Exception.Message
                Write-AZRLog -Level Error -Message "$($def.Name) failed on ${name}: $($result.Message)"
            }
            [pscustomobject]$result
        }
    }
}
