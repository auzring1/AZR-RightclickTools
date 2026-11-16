# Architecture notes

## Console extension mechanism
The ConfigMgr console loads XML from `<AdminConsole>\XmlStorage\Extensions\Actions\<node GUID>\*.xml`. Each file describes `ActionDescription` entries; `Class="Executable"` entries launch a program, and `Class="Group"` creates a submenu. Placeholders such as `##SUB:Name##`, `##SUB:CollectionID##`, `##SUB:__Server##` and `##SUB:__Namespace##` are replaced by the console from the selected object. See Microsoft's [console extension docs](https://learn.microsoft.com/mem/configmgr/develop/core/servers/console/console-extension-deployment).

## Node GUIDs (assumption to verify)
`tools/Build-ConsoleExtension.ps1` uses `ed9dee86-eadd-4ac8-82a1-7234a4646e62` (Devices) and `3fd01cd1-9e01-461e-92cd-94866b8d1f39` (Device Collections), taken from a published community example. Confirm on your console version (Microsoft's ConfigMgr Admin Console GUID documentor can list them). They are isolated in one hashtable.

## Transport
* Client actions: `Invoke-CimMethod root\ccm:SMS_Client.TriggerSchedule`.
* Device info: `Win32_*` classes, `root\ccm\ClientSDK`, and `root\cimv2\Security\MicrosoftVolumeEncryption`.
* Sessions try WSMan first, then DCOM.
* Collection membership: SMS Provider class `SMS_FullCollectionMembership`.

## Planned (see FEATURES.md)
Admin Service (REST) support so the SMS Provider/DCOM is not required, a WPF device-info window, credential prompt for alternate credentials, and bulk-result export.
