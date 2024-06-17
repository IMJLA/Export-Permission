param (

    # Path to an existing SVG file
    [Parameter( Mandatory )]
    [ValidateScript(
        {
        ([system.io.path]::GetExtension($_) -eq '.svg') -and
        (Test-Path -Path $_)
        }
    )]
    [System.IO.FileInfo]$Path,

    [PSCustomObject[]]$ExportSize,

    [string]$OutputFormat = 'png',

    # Path to the Inkscape executable
    [ValidateScript( { Test-Path $_ } )]
    [System.IO.FileInfo]$ExecutablePath = 'C:\Program Files\Inkscape\bin\inkscape.exe'

)

$InkscapeParams = @{
    ExecutablePath = $ExecutablePath
    SourceFileName = $Path
}

$Folder = $Path | Split-Path

ForEach ($Size in $ExportSize) {

    $FileName = "$($Path.BaseName)-$($Size.Width)`x$($Size.Height).$OutputFormat"
    $ExportFileName = [System.IO.Path]::Combine( $Folder, $FileName )

    $ScriptToRun = [IO.Path]::Combine('.', 'Invoke-Inkscape.ps1')
    Write-Host "`t. $ScriptToRun -SourceFileName '$Path' -ExportFileName '$ExportFileName' -ExportWidth $($Size.Width) -ExportHeight $($Size.Height) -ExecutablePath '$ExecutablePath'"
    . $ScriptToRun -ExportFileName $ExportFileName -ExportWidth $Size.Width -ExportHeight $Size.Height @InkscapeParams

}
