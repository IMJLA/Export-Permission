#requires -Module PSSVG

param (
    $OutputDir = '.',
    [string]$ProjectName = 'Export-Permission',
    [string]$ProjectSynopsisLine1 = 'Create CSV, HTML, JSON, and XML',
    [string]$ProjectSynopsisLine2 = 'exports of permissions'
)

function SvgAcct {

    param (

        # X coordinate (top right)
        [double]$X = 0,

        # Y coordinate (top right)
        [double]$Y = 0,

        # Scale (default 1:1)
        [double]$Scale = 1,

        # True generates a Checkmark, False generates a No Entry sign
        [Switch]$Permit

    )

    #account (head+torso+action)
    #head
    $strokeWidth = $Scale
    $headRadius = 4 * $Scale
    $torsoRadius = $headRadius * 2
    $bold = $strokeWidth * 2
    $headCx = $X + $strokeWidth + $torsoRadius
    $headCy = $Y + $strokeWidth + $headRadius
    SVG.circle -Cx $headCx -Cy $headCy -R $headRadius -Fill none -Stroke black -StrokeWidth $strokeWidth
    #torso
    $torsoCy = $headCy + $headRadius + $torsoRadius
    $clipRadius = $torsoRadius + $Scale
    $torsoClipPath = SVG.path -D "M $headCx $torsoCy l $clipRadius -$clipRadius 0 -$Scale -$(2 * $clipRadius) 0 0 $($Scale + $clipRadius) z"
    $clipPathID = [guid]::NewGuid().Guid.ToString()
    SVG.clipPath -Content $torsoClipPath -Id $clipPathID
    SVG.circle -Cx $headCx -Cy $torsoCy -R $torsoRadius -Fill none -Stroke black -StrokeWidth $strokeWidth -ClipPath "url(#$clipPathID)"

    #action
    if ($Permit) {
        $shortSide = 3 * $Scale
        $longSide = $shortSide * 2.5
        SVG.path -D "M$($headCx-$strokeWidth) $($torsoCy-$strokeWidth)l$shortSide $shortSide $longSide-$longSide" -Fill none -Stroke green -StrokeWidth $bold -StrokeLinecap round
    } else {
        # Stop Sign (not in use)
        #$Left = $headCx + $headRadius*2/5
        #$Right = $headCx + $torsoRadius - $headRadius*1/5
        #SVG.polygon -Points "$Left,59 106,59 $Right,62 $Right,66 106,69 $Left,69 99,66 99,62"  -Fill red -Stroke red

        # Do Not Enter sign (replaced the Stop sign)
        $denyCx = $headCx + $headRadius - $strokeWidth
        $denyCy = $torsoCy - $headRadius * .2
        SVG.circle -Cx $denyCx -Cy $denyCy -R $headRadius -Fill red -Stroke red
        SVG.rect -X ($denyCX - $headRadius + $strokeWidth) -Y ($denyCy - $strokeWidth) -Width ($headRadius * 1.6) -Height ($headRadius * .4) -Fill white
    }

}

function SvgLockedFolder {
    param (

        # X coordinate (top right)
        [double]$X = 0,

        # Y coordinate (top right)
        [double]$Y = 0,

        # Scale (default 1:1)
        [double]$scale = 1

    )

    $strokeWidth = 1 * $scale
    $leftX = $X + $strokeWidth
    $leftSide = 15 * $scale
    $bottomSide = 15 * $scale
    $rise = -9 * $scale
    $run = 4 * $scale
    $frontTabRise = -2 * $scale #$rise * $scale / $run
    $frontRightRun = $run * $frontTabRise / $rise
    $frontTabRun = $frontRightRun * 2
    $nontabWidth = 10 * $scale
    $tabWidth = 5 * $scale
    $backTabRun = 1 * $scale
    $backTabRise = 2 * $scale
    $backRightSide = 2 * $scale
    $lockX = $X + $strokeWidth + $bottomSide
    $folderBottomY = $Y + $strokeWidth + $leftSide
    $shackleX = $lockX + $scale
    $shackleY = $Y + 12 * $scale
    $shackleCurveY = $shackleY - $scale
    $straightPartOfShackle = $scale
    $shackleControlY = $Y + 6 * $scale
    $lockHeight = 6 * $scale
    $lockWidth = $lockHeight
    $lockY = $shackleY + $lockHeight
    $lockRightX = $lockX + $lockHeight
    $shackleControlX = $lockRightX - $scale #$X + 24 * $scale
    $bodyControlY = $lockY + $scale
    $keyholeCx = $lockX + $lockWidth / 2
    $keyholeCY = $lockY - $lockHeight / 2 - $scale / 2

    $BlackRoundStroke = @{
        Stroke        = 'black'
        StrokeWidth   = $strokeWidth
        StrokeLinecap = 'round'
    }
    $NoFill = @{
        Fill = 'none'
    }
    $WhiteFill = @{
        Fill = 'white'
    }

    #Folder Back
    SVG.path -D "M $lockX $folderBottomY l -$bottomSide 0 0 -$leftSide $tabWidth 0 $backTabRun $backTabRise $nontabWidth 0 0 $backRightSide" @BlackRoundStroke @NoFill

    #Folder Front
    SVG.path -D "M $leftX $folderBottomY l $run$rise $nontabWidth 0 $frontTabRun $frontTabRise $tabWidth 0 -$($frontRightRun + $run) $(($rise + $frontTabRise) * -1)" @BlackRoundStroke @NoFill

    #Lock Shackle
    SVG.path -D "M $shackleX $shackleY l 0 -$straightPartOfShackle C $shackleX $shackleControlY $shackleControlX $shackleControlY $shackleControlX $shackleCurveY l 0 $straightPartOfShackle" @BlackRoundStroke @WhiteFill

    #Lock Body
    SVG.path -D "M $lockX $lockY l 0 -$lockHeight l $lockWidth 0 0 $lockHeight C $lockRightX $bodyControlY $lockX $bodyControlY $lockX $lockY" @BlackRoundStroke @WhiteFill

    #Lock Keyhole
    SVG.circle -Cx $keyholeCx -Cy $keyholeCY -R $scale @BlackRoundStroke @NoFill
    SVG.path -D "M $keyholeCx $($keyholeCY + $scale) l 0 $(1.5*$scale)" @BlackRoundStroke @NoFill
}

function SvgPage {

    param (

        # X coordinate (top right)
        [double]$X = 0,

        # Y coordinate (top right)
        [double]$Y = 0,

        # Scale (default 1:1)
        [double]$Scale = 1,

        # Radius of the corners
        [double]$Radius = 2 * $Scale

    )

    $rectX = $X + $Scale
    $rectY = $Y + $Scale
    $foldWidth = 6 * $Scale
    $pageWidth = 46 * $Scale
    $remainingWidth = $pageWidth - $foldWidth - $Radius
    $clipX = $X + $Scale * 0.5
    $clipY = $Y + $pageWidth - $Scale * 0.5
    $clipLine1y = $pageWidth - $foldWidth - $Scale * 1.5
    $clipLine2xy = $foldWidth + $Scale * 0.5
    $clipLine3x = $clipLine1y + $Scale * 2
    $clipLine4y = $pageWidth + $Scale
    $clipLine5x = $clipLine4y

    # Clipped page corner
    $pathToClip = SVG.path -D "M $clipX $clipY l 0 -$clipLine1y $clipLine2xy -$clipLine2xy $clipLine3x 0 0 $clipLine4y -$clipLine5x 0 z"
    SVG.clipPath -Id foldedPageCorner -Content $pathToClip

    # Page
    SVG.rect -ClipPath 'url(#foldedPageCorner)' -X $rectX -Y $rectY -Rx $Radius -Ry $Radius -Width $pageWidth -Height $pageWidth -Stroke black -StrokeWidth $scale -Fill white #-StrokeDasharray 0, $Hidden, $Visible, $Hidden -PathLength $Perimeter -StrokeDashoffset $Offset

    # Flap
    SVG.rect -ClipPath 'url(#foldedPageCorner)' -Id flap -X ($rectX - $Radius) -Y ($rectY - $Radius) -Rx $Radius -Ry $Radius -Width ($foldWidth + $radius) -Height ($foldWidth + $Radius) -Stroke black -StrokeWidth $scale -Fill white #-StrokeDasharray 0, $Hidden, $Visible, $Hidden -PathLength $Perimeter -StrokeDashoffset $Offset

    # Fold
    SVG.path -D "M $rectX $($rectY + $foldWidth + $scale) l 0 -$scale $foldWidth -$foldWidth $remainingWidth 0" -Fill none -Stroke black -StrokeWidth $scale

}

# Create the SVG file for the social card, based on the logo
$OutputPath = Join-Path -Path $OutputDir -ChildPath 'social-card.svg'
$null = svg -OutputPath $OutputPath -ViewBox 188, 96 -Content @(
    SvgPage -X 12 -Y 36
    SvgLockedFolder -X 25 -Y 38
    SvgAcct -Permit -X 15 -Y 59
    SvgAcct -X 40 -Y 59
    SVG.text -X 50% -Y 25% -Text $ProjectName -FontSize 12 -DominantBaseline 'middle' -TextAnchor 'middle' -Fill 'black'
    SVG.text -X 61% -Y 61% -FontSize 6 -DominantBaseline 'middle' -TextAnchor 'middle' -Fill 'black' -Content @(
        SVG.tspan -Content $ProjectSynopsisLine1 -Dy '-1.2em'
        SVG.tspan -Content $ProjectSynopsisLine2 -X 61% -Dy '1.2em'
    )

)

##Uncomment for convenient testing
#Invoke-Item $OutputPath
