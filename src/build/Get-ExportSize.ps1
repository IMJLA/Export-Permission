param (

    # XML content of the SVG whose size to evaluate
    [xml]$Content,

    [double]$Scale = 1.0,

    [int[]]$Width

)

$srcDimensions = . ./Get-SVGDimension.ps1 -Content $Content

if ($Width) {

    Write-Host "Width parameter specified: $Width" -ForegroundColor Cyan

    ForEach ($ThisWidth in $Width) {

        $Scale = $ThisWidth / $srcDimensions.Width

        [PSCustomObject]@{
            Height = $srcDimensions.Height * $Scale
            Width  = $ThisWidth
        }

    }

} else {

    # Scale the width and height as specified
    [PSCustomObject]@{
        Height = $srcDimensions.Height * $Scale
        Width  = $srcDimensions.Width * $Scale
    }

}
