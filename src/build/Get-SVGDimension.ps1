param (

    # XML content of the SVG whose dimensions to return
    [xml]$Content

)

if ([string]::IsNullOrEmpty($Content.svg.viewBox)) {
    [double]$svgHeight = $Content.svg.width.Replace('px', '')
    [double]$svgWidth = $Content.svg.width.Replace('px', '')
} else {
    $x, $y, [double]$svgWidth, [double]$svgHeight = $Content.svg.viewBox -split '[^\d]'
}

[PSCustomObject]@{
    Height = $svgHeight
    Width  = $svgWidth
}
