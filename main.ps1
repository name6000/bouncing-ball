# Bouncing ball + bytebeat audio (fixed)
# Exit with Q or Esc (Ctrl+C also works).

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Build block characters from code points so the script works even if it is
# saved without a UTF-8 BOM (Windows PowerShell 5.1 would otherwise garble them).
$Full  = [string][char]0x2588   # full block
$Shade = [string][char]0x2592   # medium shade (trail)

# --- Sprite ---
$BallSprite = @(
    "  ###  ",
    " ##### ",
    "#######",
    " ##### ",
    "  ###  "
) | ForEach-Object { $_ -replace '#', $Full }

$BallHeight = $BallSprite.Count
$BallWidth  = $BallSprite[0].Length          # was $BallSprite.Length (array count = 5)
$TrailSprite = $BallSprite | ForEach-Object { $_ -replace $Full, $Shade }

$Colors = @("Magenta", "Cyan", "Yellow", "Green", "Red", "White")
$ColorIndex = 0

$Trail = [System.Collections.Generic.List[PSCustomObject]]::new()
$MaxTrailLength = 12

# --- Setup ---
$wsh = New-Object -ComObject WScript.Shell
[Console]::BackgroundColor = 'Black'
[Console]::ForegroundColor = 'White'
[Console]::Clear()
[Console]::CursorVisible = $false            # was [cursor]::Visible (invalid type)

# Toggle fullscreen (works in Windows Terminal; in classic conhost use Alt+Enter instead)
$wsh.SendKeys('{F11}')
Start-Sleep -Milliseconds 600                # give the window time to resize before measuring

$WinWidth  = [Console]::WindowWidth
$WinHeight = [Console]::WindowHeight

# Keep one column/row spare so writing the last cell never scrolls the buffer
$MaxX = $WinWidth  - $BallWidth
$MaxY = $WinHeight - $BallHeight - 1

$X  = [Math]::Max(0, [Math]::Floor($MaxX / 2))
$Y  = [Math]::Max(0, [Math]::Floor($MaxY / 2))
$DX = 1
$DY = 1

function Draw-Sprite($sprite, [int]$px, [int]$py, $color) {
    [Console]::ForegroundColor = $color
    for ($row = 0; $row -lt $sprite.Count; $row++) {
        [Console]::SetCursorPosition($px, $py + $row)
        [Console]::Write($sprite[$row])
    }
}

function Erase-Sprite([int]$px, [int]$py) {
    $blank = " " * $BallWidth
    for ($row = 0; $row -lt $BallHeight; $row++) {
        [Console]::SetCursorPosition($px, $py + $row)
        [Console]::Write($blank)
    }
}

# --- Bytebeat engine ---
# NOTE: in PowerShell, -band/-bor/-bxor/-shr/-shl all share ONE precedence level
# (lower than + - * /) and evaluate left to right, unlike C/JS. Everything is
# explicitly parenthesised below to preserve the intended formula.
# Also: `-and` is a logical operator (returns $true/$false); bitwise needs `-band`.
function Get-Bytebeat([long]$t) {
    [long]$res = 0
    try {
        if ($t -gt 0 -and $t -lt 237568) {
            $res = $t -band ($t -shr 8)
        }
        elseif ($t -gt 245760 -and $t -lt 475136) {
            $res = ($t -shr 5) -bor (($t -shr 2) * ($t -shr 5))
        }
        elseif ($t -gt 483328 -and $t -lt 724992) {
            $a = (($t -shr 5) -band $t) - ($t -shr 5) + (($t -shr 5) -band $t)
            $b = $t * ((($t + 40960) -shr 14) -band 14)
            $res = $a + $b
        }
        elseif ($t -gt 729088 -and $t -lt 966656) {
            $c = if (($t % 16) -ne 0) { 2L } else { 6L }
            $res = $t + ($t -band ($t -bxor ($t -shr 6))) - ($t * ((($t -shr 9) -band $c) -band ($t -shr 9)))
        }
        elseif ($t -gt 970752 -and $t -lt 1208320) {
            $x = (($t - 970752) -shr 15) -bor 1
            $res = $t * ($t -bxor ($t + $x) -bxor ((($t - 1280) -bxor $t) -shr 10))
        }
        elseif ($t -gt 1212416 -and $t -lt 1437696) {
            # integer shifts instead of "/" (which produces doubles in PowerShell)
            $p = ($t -shr 11) -bor ((($t % 16) * $t) -shr 8)
            $q = $p -band (($t * 8) -shr 12) -band 18
            $res = $t * ($q -bor (64 - ($t -shr 4)))
        }
        elseif ($t -gt 1441792 -and $t -lt 1679360) {
            $m = if (($t -band 16384) -ne 0) { 6L } else { 5L }
            $left = ($t * $m * (4 - (1 -band ($t -shr 8)))) -shr (3 -band ($t -shr 9))   # was -and
            $res = $left -bor (($t -bor ($t * 3)) -shr 5)
        }
        elseif ($t -gt 1683456 -and $t -lt 1900544) {
            $hi = (($t -band 4096) -ne 0)
            $c1 = if ($hi) { 6L } else { 16L }
            $c2 = if ($hi) { 3 } else { 4 }
            $left = ($t * ($c1 + (1 -band (($t + 16384) -shr 14)))) -shr (3 -band ($t -shr 8))  # was -and
            $res = $left -bor ($t -shr $c2)
        }
        elseif ($t -gt 1900544) {
            $inner = if (($t -band 65536) -lt 59392) { 7L } else { $t -band 7L }
            $c1 = if (($t -band 4096) -ne 0) { $inner } else { 16L }
            $c2 = if (($t -band 2048) -ne 0) { 2 } else { 10 }
            $c3 = if (($t -band 16384) -ne 0) { if (($t -band 4096) -ne 0) { 10L } else { 3L } } else { 2L }
            $left = ($t * ($c1 -bxor (1 -band ($t -shr 14)))) -shr (3 -band ((-$t) -shr $c2))
            $res = $left -bor $c3
        }
        else {
            $res = $t -band ($t -shr 8)
        }
    }
    catch {
        $res = 0
    }

    # True 8-bit wrap (Abs()+% 256 mirrors negatives instead of wrapping them)
    $raw = $res -band 255
    return [int](60 + ($raw * 4))            # 60..1080 Hz, safely inside Beep's 37..32767 range
}

[long]$t = 0

# --- Main loop ---
try {
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { break }
        }

        $X += $DX
        $Y += $DY
        $HitWall = $false

        if     ($X -le 0)     { $X = 0;     $DX = -$DX; $HitWall = $true }
        elseif ($X -ge $MaxX) { $X = $MaxX; $DX = -$DX; $HitWall = $true }

        if     ($Y -le 0)     { $Y = 0;     $DY = -$DY; $HitWall = $true }
        elseif ($Y -ge $MaxY) { $Y = $MaxY; $DY = -$DY; $HitWall = $true }

        if ($HitWall) {
            $ColorIndex = ($ColorIndex + 1) % $Colors.Count

            # Impact flash: fill screen white briefly, then really clear back to black.
            # (Originally the screen was cleared white and never cleared back to black.)
            [Console]::BackgroundColor = 'White'
            [Console]::Clear()
            Start-Sleep -Milliseconds 40
            [Console]::BackgroundColor = 'Black'
            [Console]::Clear()
            $Trail.Clear()                   # screen was wiped, so old trail points are gone
        }

        # Erase the oldest trail point first, THEN redraw everything on top,
        # so erasing never punches holes in newer trail/sprite cells.
        if ($Trail.Count -ge $MaxTrailLength) {
            $Old = $Trail[0]
            Erase-Sprite $Old.X $Old.Y
            $Trail.RemoveAt(0)
        }

        foreach ($Point in $Trail) {
            Draw-Sprite $TrailSprite $Point.X $Point.Y $Point.Color
        }

        $CurrentColor = $Colors[$ColorIndex]
        Draw-Sprite $BallSprite $X $Y $CurrentColor

        $Trail.Add([PSCustomObject]@{ X = $X; Y = $Y; Color = $CurrentColor })

        # Audio (blocks ~30 ms, which also paces the animation)
        [Console]::Beep((Get-Bytebeat $t), 30)
        $t += 128
    }
}
finally {
    [Console]::CursorVisible = $true         # was [cursor]::Visible
    [Console]::ResetColor()
    [Console]::Clear()
    $wsh.SendKeys('{F11}')                   # leave fullscreen again
}