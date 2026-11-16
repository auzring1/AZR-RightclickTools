@{
    RootModule        = 'AZR.RightClickTools.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '6f1d6a3e-5b0c-4c52-9a0e-3d2a7b9c41e8'
    Author            = 'AZR-RightClickTools contributors'
    Description       = 'Free, open-source right-click tools for the Configuration Manager console.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-AZRClientAction'
        'Get-AZRClientActionList'
        'Get-AZRDeviceInfo'
        'Test-AZRConnection'
        'Get-AZRService'
        'Restart-AZRService'
        'Get-AZREventLog'
        'Open-AZRCDrive'
        'Open-AZRClientLogs'
        'Start-AZRRdp'
        'Start-AZRRemoteShell'
        'Start-AZRComputerManagement'
        'Get-AZRCollectionMember'
        'Invoke-AZRAction'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
