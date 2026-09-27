# Windows entry equal to tools/godot.sh's core: run Godot in this checkout and fail on diagnostics even
# when Godot exits zero. No bash needed (Windows PowerShell 5.1 or PowerShell 7).
#
#   powershell -ExecutionPolicy Bypass -File tools\godot.ps1 --headless --import
#   powershell -ExecutionPolicy Bypass -File tools\godot.ps1 --headless --script res://tests/run_x_tests.gd
#
# PowerShell swallows a bare -- before the script sees it: pass Godot user arguments after ++ (Godot reads
# both) or a quoted '--'.
#
# Godot: $env:GODOT_BIN (use the *_console.exe build so output reaches the terminal), else godot／godot4 on
# PATH. Differences from godot.sh: --import always imports (godot.sh skips it when nothing Godot imports
# changed and seeds a missing cache from another worktree); the macOS Dock workaround does not apply.
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
$GodotArgs = @($args)
if ($GodotArgs.Count -eq 0) {
    [Console]::Error.WriteLine('usage: tools\godot.ps1 GODOT_ARGS... (use tools\play.ps1 to play)')
    exit 2
}

# Git ignore rules do not stop Godot importing raw captures (same as godot.sh).
$Ignored = Join-Path $Root 'ignored'
New-Item -ItemType Directory -Force -Path $Ignored | Out-Null
$GdIgnore = Join-Path $Ignored '.gdignore'
if (-not (Test-Path -LiteralPath $GdIgnore)) {
    Set-Content -LiteralPath $GdIgnore -Value '# Local capture output; not a Godot resource input.' -Encoding Ascii
}

# A rule suite (`extends "res://tests/support/TestSuite.gd"`) is not a MainLoop: route it through the
# in-process runner, as godot.sh does (`--script res://tests/run_all.gd -- run_x_tests.gd`).
$Suite = $null
for ($i = 0; $i -lt $GodotArgs.Count - 1; $i++) {
    $target = [string]$GodotArgs[$i + 1]
    if ($GodotArgs[$i] -eq '--script' -and $target -like 'res://tests/run_*.gd') {
        $file = Join-Path $Root ($target.Substring('res://'.Length))
        if ((Test-Path -LiteralPath $file) -and ((Get-Content -LiteralPath $file -TotalCount 1) -eq 'extends "res://tests/support/TestSuite.gd"')) {
            $Suite = $target.Substring('res://tests/'.Length)
            $GodotArgs[$i + 1] = 'res://tests/run_all.gd'
        }
    }
}
if ($Suite) {
    if ($GodotArgs -contains '--' -or $GodotArgs -contains '++') {
        [Console]::Error.WriteLine("tools\godot.ps1: a rule suite takes no user arguments; run tools\godot.ps1 --headless --script res://tests/run_all.gd ++ $Suite")
        exit 2
    }
    [Console]::Error.WriteLine("tools\godot.ps1: $Suite is an in-process rule suite; running it as --script res://tests/run_all.gd ++ $Suite")
    $GodotArgs += @('++', $Suite)  # ++ = Godot's user-argument separator; a native -- is dropped by Windows PowerShell 5.1
}

$Log = [System.IO.Path]::GetTempFileName()
try {
    $ErrorActionPreference = 'Continue'  # Godot writes diagnostics to stderr; they are checked below
    & $Godot --path $Root @GodotArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $Log
    $Result = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if (Select-String -LiteralPath $Log -Pattern 'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked|resources still in use' -Quiet) {
        [Console]::Error.WriteLine('Godot diagnostics failed verification')
        if ($Result -eq 0) { $Result = 1 }
    }
} finally {
    Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue
}
exit $Result
