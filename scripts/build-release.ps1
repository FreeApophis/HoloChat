# Builds the production release into _build\prod\rel\holo_chat.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1
#
# Then, with the environment variables from the README's Deployment section set:
#
#   _build\prod\rel\holo_chat\bin\migrate.bat
#   _build\prod\rel\holo_chat\bin\server.bat
#
# The release only runs on the OS it was built on (here: Windows).

$ErrorActionPreference = "Stop"

# Erlang and Elixir from their default install folders, unless already on the PATH.
if (-not (Get-Command mix -ErrorAction SilentlyContinue)) {
    $env:Path = "C:\Program Files\Erlang OTP\bin;C:\Program Files\Elixir\bin;$env:Path"
}

function Invoke-Step([string] $Description, [scriptblock] $Command) {
    Write-Host "==> $Description" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Description failed (exit code $LASTEXITCODE)" }
}

$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root "_build\prod\rel\holo_chat"

# Windows can't replace files a running release has open; a half-replaced
# release would break it. Refuse before touching anything.
$running = Get-Process | Where-Object { $_.Path -and $_.Path -like "$release\*" }
if ($running) {
    $running | Format-Table Id, ProcessName -AutoSize | Out-String | Write-Host
    throw "The release is running. Stop it first (_build\prod\rel\holo_chat\bin\holo_chat.bat stop, " +
        "then Stop-Process -Name epmd if it is still listed) and build again."
}

Push-Location $root
$previousMixEnv = $env:MIX_ENV

try {
    $env:MIX_ENV = "prod"
    Invoke-Step "Fetching dependencies" { mix deps.get --only prod }
    Invoke-Step "Compiling" { mix compile }
    Invoke-Step "Building assets" { mix assets.deploy }
    Invoke-Step "Building the release" { mix release --overwrite }

    Write-Host "`nRelease ready in _build\prod\rel\holo_chat" -ForegroundColor Green
}
finally {
    # The release has its own copy; the digested files would only clutter git status.
    $env:MIX_ENV = "dev"
    Write-Host "==> Removing digested assets from priv/static" -ForegroundColor Cyan
    mix phx.digest.clean --all | Out-Null

    $env:MIX_ENV = $previousMixEnv
    Pop-Location
}
