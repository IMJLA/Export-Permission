# https://www.harrytraynor.io/converting-an-svg-to-png-using-powershell/
param(

    # Path to an existing SVG file
    [Parameter( Mandatory, ValueFromPipeline )]
    [ValidateScript(
        {
            ([system.io.path]::GetExtension($_) -eq '.svg') -and
            (Test-Path -Path $_)
        }
    )]
    [System.IO.FileInfo[]]$Path,

    [string]$OutputFormat = 'png',

    [double]$Scale = 1.0,

    [int[]]$Width,

    # Path to the Inkscape executable
    [ValidateScript( { Test-Path $_ } )]
    [System.IO.FileInfo]$ExecutablePath = 'C:\Program Files\Inkscape\bin\inkscape.exe'

)

begin {

    if ($PSBoundParameters.ContainsKey('Width')) {

        $GetIconSizeParams = @{
            Scale = $Scale
            Width = $Width
        }

    } else {

        $GetIconSizeParams = @{
            Scale = $Scale
        }

    }

}

process {

    ForEach ($ThisPath in $Path) {

        # Read the SVG file and parse the XML, storing it as an object
        [xml]$Content = Get-Content -Path $ThisPath

        $ExportSizes = . ./Get-ExportSize.ps1 -Content $Content @GetIconSizeParams

        . ./Export-Inkscape.ps1 -Path $ThisPath -ExportSize $ExportSizes -OutputFormat $OutputFormat -ExecutablePath $ExecutablePath

    }

}

