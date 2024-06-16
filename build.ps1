[cmdletbinding(DefaultParameterSetName = 'Task')]
param(

    # Build task(s) to execute
    [parameter(ParameterSetName = 'task', position = 0)]
    [System.Collections.Generic.List[string]]$Task = @('default'),

    [switch]$NoPublish,

    # List available build tasks
    [parameter(ParameterSetName = 'Help')]
    [switch]$Help,

    # Optional properties to pass to psake
    [hashtable]$Properties = @{PortableVersionGuid = 'c7308309-badf-44ea-8717-28e5f5beffd5' },

    # Optional parameters to pass to psake
    [hashtable]$Parameters,

    # Commit message for source control
    [parameter(Mandatory)]
    [string]$CommitMessage

)

$ErrorActionPreference = 'Stop'

if (!($PSBoundParameters.ContainsKey('Parameters'))) {
    $Parameters = @{}
}
$Parameters['CommitMessage'] = $CommitMessage

if (-not $NoPublish) {
    $Task.Add('Publish')
}

Write-Host "PSAKE TASKS: $Task"

# Execute psake task(s)
$psakeFile = [IO.Path]::Combine('.', 'src', 'build', 'psakeFile.ps1')
if ($PSCmdlet.ParameterSetName -eq 'Help') {
    Get-PSakeScriptTasks -buildFile $psakeFile |
    Format-Table -Property Name, Description, Alias, DependsOn
} else {
    Invoke-psake -buildFile $psakeFile -taskList $Task -properties $Properties -parameters $Parameters
    exit ([int](-not $psake.build_success))
}
