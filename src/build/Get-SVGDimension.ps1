param (

    # XML content of the SVG whose dimensions to return
    [xml]$Content

)

if ([string]::IsNullOrEmpty($Content.svg.viewBox)) {
    [double]$Height = $Content.svg.width.Replace('px', '')
    [double]$Width = $Content.svg.width.Replace('px', '')
} else {
    $x, $y, [double]$Width, [double]$Height = $Content.svg.viewBox -split '[^\d]'
}

[PSCustomObject]@{
    Height = $Height
    Width  = $Width
}
