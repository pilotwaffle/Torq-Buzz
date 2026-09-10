# S16 spike - Windows launcher for the dev desktop (throwaway, outside the repo).
# Replaces `just desktop-standalone` / `pnpm tauri dev`, both of which assume bash.
#   .\Start-S16Desktop.ps1                 build sidecars if missing, start vite, launch Tauri dev (.dev nest)
#   .\Start-S16Desktop.ps1 -Prepare        build + copy sidecars only (no window)
#   .\Start-S16Desktop.ps1 -Nest s16test5  launch an ISOLATED nest via the repo's compile-time demo slug:
#                                          nest %USERPROFILE%\.buzz-demo-<slug>, keyring buzz-desktop-demo.<slug>,
#                                          app data %APPDATA%\xyz.block.buzz.app.demo.<slug>. Daily nests untouched.
#                                          Changing the slug forces a desktop-crate rebuild; close any running
#                                          Buzz Dev window first (the exe cannot be relinked while it runs).
param([switch]$Prepare, [string]$Nest = '')

$ErrorActionPreference = 'Stop'
$repo    = 'E:\TORQ-BUZZ\source\buzz'
$desktop = "$repo\desktop"
$binDir  = "$desktop\src-tauri\binaries"
$triple  = 'x86_64-pc-windows-msvc'
$bins    = @('buzz-acp','buzz-agent','buzz-backend-kubernetes','buzz-dev-mcp','git-credential-nostr','buzz')
$vitePort = 1420

if ($Nest -and $Nest -notmatch '^[a-z0-9][a-z0-9-]{0,46}[a-z0-9]$') { throw "-Nest must be a lowercase slug (a-z, 0-9, -), e.g. s16test5" }

# --- sidecars -------------------------------------------------------------
$missing = $bins | Where-Object { -not (Test-Path "$binDir\$_-$triple.exe") }
if ($missing -or $Prepare) {
    Write-Host "Building sidecars: $($bins -join ', ')"
    Push-Location $repo
    cargo build -p buzz-acp -p buzz-agent -p buzz-backend-kubernetes -p buzz-dev-mcp -p buzz-cli -p git-credential-nostr
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "cargo build failed ($LASTEXITCODE)" }
    Pop-Location
    New-Item -ItemType Directory -Force $binDir | Out-Null
    foreach ($b in $bins) {
        Copy-Item "$repo\target\debug\$b.exe" "$binDir\$b-$triple.exe" -Force
    }
    Write-Host "Sidecars copied to $binDir"
}
if ($Prepare) { Get-ChildItem $binDir | Select-Object Name, Length; return }

# --- vite (separate window; Tauri's beforeDevCommand uses bash `exec`) ------
function Test-VitePort { [bool](Get-NetTCPConnection -LocalPort $vitePort -State Listen -ErrorAction SilentlyContinue) }
$viteUp = Test-VitePort
if ($viteUp) { Write-Host "Vite already listening on $vitePort; reusing it" } else {
    Start-Process powershell -ArgumentList '-NoExit','-Command',"Set-Location '$desktop'; `$env:VITE_PORT='$vitePort'; pnpm exec vite --host 127.0.0.1 --port $vitePort --strictPort"
    Write-Host "Waiting for vite on $vitePort..."
    $deadline = (Get-Date).AddSeconds(90)
    do { Start-Sleep 2; $viteUp = Test-VitePort } until ($viteUp -or (Get-Date) -gt $deadline)
    if (-not $viteUp) { throw "vite did not come up on port $vitePort" }
}

# --- tauri dev --------------------------------------------------------------
Remove-Item Env:BUZZ_PRIVATE_KEY, Env:BUZZ_SHARE_IDENTITY -ErrorAction SilentlyContinue
$env:RUST_LOG = 'observer=debug'
# Slice 1 gate (design answer Q1): explicit 500 ms observer publish tick, inherited by the
# desktop-spawned buzz-acp sidecars. Equal to the built-in default; set so the evidence is explicit.
$env:BUZZ_OBSERVER_PUBLISH_TICK_MS = '500'
# Expose the WebView2 remote-debugging port so probe-env\s1-cdp.mjs can read the paint log,
# set the feature override and navigate without the operator clicking through dev tools.
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9222'
# S16 spike: pin the desktop to the permanent relay (schtasks TORQ-Buzz-PermanentRelay,
# ws://127.0.0.1:3300). Default is ws://localhost:3000 (dead in dev) — the observer
# subscription otherwise connects nowhere and no frames paint. relay_ws_url() reads
# this env var at runtime (relay.rs:40), so it must be set before `tauri dev`.
$env:BUZZ_RELAY_URL = 'ws://127.0.0.1:3300'

if ($Nest) {
    # Isolated nest via the demo-slug build contract (desktop/src-tauri/build.rs,
    # build_identity.rs). The slug only changes nest name, keyring service and CLI name.
    $env:BUZZ_BUILD_DEMO_SLUG = $Nest
    Remove-Item Env:BUZZ_DEV_KEYRING_SERVICE -ErrorAction SilentlyContinue
    $identifier = "xyz.block.buzz.app.demo.$Nest"
    $product    = "Buzz S16 $Nest"
    $override   = "E:\TORQ-BUZZ\probe-env\s16-tauri-override-$Nest.json"
    $json = '{"build":{"devUrl":"http://127.0.0.1:' + $vitePort + '/","beforeDevCommand":"cmd /c echo vite-started-separately"},"identifier":"' + $identifier + '","productName":"' + $product + '"}'
    [IO.File]::WriteAllText($override, $json)
    Write-Host "ISOLATED NEST  slug=$Nest"
    Write-Host "  nest dir : $env:USERPROFILE\.buzz-demo-$Nest"
    Write-Host "  archive  : $env:USERPROFILE\.buzz-demo-$Nest\archive\archive.db"
    Write-Host "  app data : $env:APPDATA\$identifier"
    Write-Host "  keyring  : buzz-desktop-demo.$Nest"
} else {
    Remove-Item Env:BUZZ_BUILD_DEMO_SLUG -ErrorAction SilentlyContinue
    $env:BUZZ_DEV_KEYRING_SERVICE = 'buzz-desktop-dev.main'
    $override = 'E:\TORQ-BUZZ\probe-env\s16-tauri-override.json'
    Write-Host "DEV NEST (identifier xyz.block.buzz.app.dev, nest ~\.buzz-dev)"
}

Set-Location $desktop
Write-Host "Launching Tauri dev with config $override (RUST_LOG=observer=debug)"
# Capture the desktop process output (incl. Rust `[decrypt_observer_event]` timing lines) for gate evidence.
$desktopLog = "E:\TORQ-BUZZ\probe-env\desktop-stderr-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Write-Host "Desktop output tee'd to $desktopLog"
# Tee-Object buffers native output until exit; use a direct redirect so Rust eprintln lines
# ([decrypt_observer_event], stall probes) land in the file as they happen.
cmd /c "pnpm exec tauri dev --config `"$override`" 2>&1 1>`"$desktopLog`""
