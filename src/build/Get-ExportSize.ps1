param (

    # XML content of the SVG whose size to evaluate
    [xml]$Content,

    [double]$Scale = 1.0,

    [int[]]$Width

)

$ScriptToRun = [IO.Path]::Combine('.', 'Get-SVGDimension.ps1')
$srcDimensions = . $ScriptToRun -Content $Content

if ($PSBoundParameters.ContainsKey('Width')) {

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
