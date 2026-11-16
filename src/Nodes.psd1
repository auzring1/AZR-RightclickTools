# Console nodes the generator can add the AZR menu to.
# Guid         : folder name under <Console>\XmlStorage\Extensions\Actions. $null = node not discovered yet (skipped).
# TargetArgs   : launcher arguments that pass the selected object. Every ##SUB:x## used must be listed in Placeholders.
# Placeholders : substitution names this node supports on the console version we verified. Run
#                tools\Get-AZRConsoleNodes.ps1 on a console to list what your version ships.
# Verified     : $true only after a lab check on a real console; the GUIDs below come from published community
#                examples and are still assumptions (see docs\ARCHITECTURE.md).
@{
    Device = @{
        Guid         = 'ed9dee86-eadd-4ac8-82a1-7234a4646e62'
        Verified     = $false
        TargetArgs   = '-ComputerName "##SUB:Name##"'
        Placeholders = @('Name', 'ResourceID', '__Server', '__Namespace')
    }
    Collection = @{
        Guid         = '3fd01cd1-9e01-461e-92cd-94866b8d1f39'
        Verified     = $false
        TargetArgs   = '-CollectionId "##SUB:CollectionID##"'
        Placeholders = @('CollectionID', 'Name', '__Server', '__Namespace')
    }
    # Planned nodes: GUIDs and placeholders are unknown until discovered on a console (tools\Get-AZRConsoleNodes.ps1).
    User              = @{ Guid = $null; Verified = $false; TargetArgs = $null; Placeholders = @() }
    UserCollection    = @{ Guid = $null; Verified = $false; TargetArgs = $null; Placeholders = @() }
    Application       = @{ Guid = $null; Verified = $false; TargetArgs = $null; Placeholders = @() }
    SoftwareUpdate    = @{ Guid = $null; Verified = $false; TargetArgs = $null; Placeholders = @() }
    DistributionPoint = @{ Guid = $null; Verified = $false; TargetArgs = $null; Placeholders = @() }
    DPGroup           = @{ Guid = $null; Verified = $false; TargetArgs = $null; Placeholders = @() }
}
