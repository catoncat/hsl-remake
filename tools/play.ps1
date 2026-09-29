# Windows entry equal to tools/play.sh: import the assets when this checkout has no import cache yet, then
# open the game. No bash needed (Windows PowerShell 5.1 or PowerShell 7).
#
#   powershell -ExecutionPolicy Bypass -File tools\play.ps1 [GODOT_ARGS...]
#
# Import rule (simpler than play.sh): import when .godot\imported is missing or $env:HSL_FORCE_IMPORT is 1;
# after `python tools\hsl.py generate ...` wrote new images or sounds, run it with HSL_FORCE_IMPORT=1 once.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Find-Godot {
    if ($env:GODOT_BIN) { return $env:GODOT_BIN }
    foreach ($name in 'godot', 'godot4') {
        $found = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.Source }
    }
    return $null
}

$Godot = Find-Godot
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    [Console]::Error.WriteLine('Godot executable not found; set GODOT_BIN or put godot on PATH.')
    exit 1
}
$env:GODOT_BIN = $Godot

if ($env:HSL_FORCE_IMPORT -eq '1' -or -not (Test-Path -LiteralPath (Join-Path $Root '.godot\imported'))) {
    $Log = [System.IO.Path]::GetTempFileName()
    try {
        $ErrorActionPreference = 'Continue'
        & (Join-Path $PSScriptRoot 'godot.ps1') --headless --import *> $Log
        $ImportResult = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($ImportResult -ne 0) {
            Get-Content -LiteralPath $Log | ForEach-Object { [Console]::Error.WriteLine($_) }
            [Console]::Error.WriteLine('Asset import failed; refusing to open an incomplete game window.')
            exit 1
        }
    } finally {
        Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue
    }
}

# Development switch: P freezes the game and N steps one frame (game/debug/DebugPause.gd); HSL_DEBUG_PAUSE=0 turns it off.
if (-not $env:HSL_DEBUG_PAUSE) { $env:HSL_DEBUG_PAUSE = '1' }
# Product self-heal (game/sim/ProgressionRules.gd self_heal), as in tools/play.sh; HSL_SELF_HEAL=0 turns it off.
if (-not $env:HSL_SELF_HEAL) { $env:HSL_SELF_HEAL = '1' }
& $Godot --path $Root @args
exit $LASTEXITCODE
