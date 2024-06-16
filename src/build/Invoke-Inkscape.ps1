param (

    # Path to an existing SVG file
    [Parameter( Mandatory )]
    [ValidateScript(
        {
        ([system.io.path]::GetExtension($_) -eq '.svg') -and
        (Test-Path -Path $_)
        }
    )]
    [System.IO.FileInfo]$SourceFileName,

    [System.IO.FileInfo]$ExportFileName,

    [int]$ExportWidth,

    [int]$ExportHeight,

    # Path to the Inkscape executable
    [ValidateScript( { Test-Path $_ } )]
    [System.IO.FileInfo]$ExecutablePath = 'C:\Program Files\Inkscape\bin\inkscape.exe'

)

$command = "& `"$ExecutablePath`" --export-filename=`"$ExportFileName`" --export-width=$ExportWidth --export-height=$ExportHeight `"$SourceFileName`""
Write-Debug $command
Invoke-Expression $command
