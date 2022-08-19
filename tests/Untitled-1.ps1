


## This one works
#$TestPermission = $Permissions | Where-Object -FilterScript { $_.IdentityReference -eq 'S-1-5-32-544' }

## This one throws errors all the time
$TestPermission = $Permissions | Where-Object -FilterScript { $_.IdentityReference -eq 'S-1-5-32-545' }

$ResolveAceParams = @{
    Command              = 'Resolve-Ace3'
    InputObject          = $TestPermission
    InputParameter       = 'InputObject'
    ObjectStringProperty = 'IdentityReference'
    TodaysHostname       = $ThisHostname
    DebugOutputStream    = 'Debug'
    AddParam             = @{
        AdsiServersByDns       = $AdsiServersByDns
        DirectoryEntryCache    = $DirectoryEntryCache
        Win32AccountsBySID     = $Win32AccountsBySID
        Win32AccountsByCaption = $Win32AccountsByCaption
        DomainsBySID           = $DomainsBySID
        DomainsByNetbios       = $DomainsByNetbios
        DomainsByFqdn          = $DomainsByFqdn
    }
}
Write-Debug "  $(Get-Date -Format s)`t$ThisHostname`tExport-Permission`tSplit-Thread -Command 'Resolve-Ace' -InputParameter InputObject -InputObject `$Permissions -ObjectStringProperty 'IdentityReference' -DebugOutputStream 'Debug'"
Split-Thread @ResolveAceParams



<#
$InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$null = $InitialSessionState.ImportPSModulesFromPath('C:\Users\Owner\Documents\PowerShell\Modules\Adsi\3.0.15')
$null = $InitialSessionState.ImportPSModulesFromPath('C:\Users\Owner\Documents\PowerShell\Modules\PsNtfs\2.0.28')

$VariableName = 'DebugPreference'
$VariableValue = (Get-Variable -Name $VariableName).Value
$VariableEntry = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new($VariableName, $VariableValue, '')
$null = $InitialSessionState.Variables.Add($VariableEntry)

$RunspacePool = [runspacefactory]::CreateRunspacePool(1, 20, $InitialSessionState, $Host)
$null = $RunspacePool.Open()
$PowershellInterface = [powershell]::Create()
$null = $PowershellInterface.RunspacePool = $RunspacePool
$null = $PowershellInterface.Commands.Clear()
$null = $PowershellInterface.AddStatement().AddCommand('Resolve-Ace')
$null = $PowershellInterface.AddParameter('InputObject', $TestPermission)
$null = $PowershellInterface.AddParameter('AdsiServersByDns', $AdsiServersByDns)
$null = $PowershellInterface.AddParameter('DomainsByNetbios', $DomainsByNetbios)
$null = $PowershellInterface.AddParameter('DomainsBySID', $DomainsBySID)
$null = $PowershellInterface.AddParameter('DomainsByFqdn', $DomainsByFqdn)
$null = $PowershellInterface.AddParameter('DirectoryEntryCache', $DirectoryEntryCache)
$null = $PowershellInterface.AddParameter('Win32AccountsByCaption', $Win32AccountsByCaption)
$null = $PowershellInterface.AddParameter('Win32AccountsBySID', $Win32AccountsBySID)
$Handle = $PowershellInterface.BeginInvoke()
do {Start-Sleep -Seconds 1}
while ($Handle.IsCompleted -eq $false)
$PowerShellInterface.Streams.ClearStreams()
$PowerShellInterface.EndInvoke($Handle)
$PowerShellInterface.Dispose()
#>
