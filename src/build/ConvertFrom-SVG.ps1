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

    [int[]]$ExportWidth,

    # Path to the Inkscape executable
    [ValidateScript( { Test-Path $_ } )]
    [System.IO.FileInfo]$ExecutablePath = 'C:\Program Files\Inkscape\bin\inkscape.exe'

)

begin {

    if ($PSBoundParameters.ContainsKey('ExportWidth')) {

        $ExportSizeParams = @{
            Scale = $Scale
            Width = $ExportWidth
        }
        $WidthString = " -Width ($($ExportWidth -join ','))"

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

        $ScriptToRun = [IO.Path]::Combine('.', 'Get-ExportSize.ps1')
        "`t`$ExportSizes = . $ScriptToRun -Content `$Content -Scale $Scale$WidthString"
        $ExportSizes = . $ScriptToRun -Content $Content @ExportSizeParams

        $NewLine

        $ScriptToRun = [IO.Path]::Combine('.', 'Export-Inkscape.ps1')
        "`t. $ScriptToRun -Path '$ThisPath' -ExportSize `$ExportSizes -OutputFormat '$OutputFormat' -ExecutablePath '$ExecutablePath'"
        . $ScriptToRun -Path $ThisPath -ExportSize $ExportSizes -OutputFormat $OutputFormat -ExecutablePath $ExecutablePath

    }

}

