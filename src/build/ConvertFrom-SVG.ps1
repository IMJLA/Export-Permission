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

        Write-Host "Width parameter specified: $Width" -ForegroundColor Cyan

        $ExportSizeParams = @{
            Scale = $Scale
            Width = $Width
        }
        $WidthString = " -Width ($($Width -join ','))"

    } else {

        $ExportSizeParams = @{
            Scale = $Scale
        }

    }

}

process {

    ForEach ($ThisPath in $Path) {

        # Read the SVG file and parse the XML, storing it as an object
        "`t[xml]`$Content = Get-Content -Path '$ThisPath'"
        [xml]$Content = Get-Content -Path $ThisPath

        "`t`$ExportSizes = . ./Get-ExportSize.ps1 -Content `$Content -Scale $Scale$WidthString"
        $ExportSizes = . ./Get-ExportSize.ps1 -Content $Content @ExportSizeParams

        $NewLine

        "EXPORT SIZES: $($ExportSizes.Count)"
        for ($i = 0; $i -lt $ExportSizes.Count; $i++) {
            "-SIZE $($i + 1)"
            "--HEIGHT $($ExportSizes[$i].Height)"
            "--WIDTH $($ExportSizes[$i].Width)"
            $NewLine
        }

        "`t. ./Export-Inkscape.ps1 -Path '$ThisPath' -ExportSize `$ExportSizes -OutputFormat '$OutputFormat' -ExecutablePath '$ExecutablePath'"
        . ./Export-Inkscape.ps1 -Path $ThisPath -ExportSize $ExportSizes -OutputFormat $OutputFormat -ExecutablePath $ExecutablePath

    }

}

