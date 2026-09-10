# Writes a fresh Claude subscription token into E:\TORQ-CONSOLE\.env (ANTHROPIC_API_KEY line).
# Run:  powershell -ExecutionPolicy Bypass -File E:\TORQ-BUZZ\probe-env\Update-AnthropicToken.ps1
$p = 'E:\TORQ-CONSOLE\.env'
$t = (Read-Host "Paste the token from 'claude setup-token' and press Enter").Trim()
if ($t -notmatch '^sk-ant-oat01-') {
    Write-Host "That does not look like a subscription token (expected it to start with sk-ant-oat01-). Nothing written." -ForegroundColor Red
    exit 1
}
$c = [IO.File]::ReadAllText($p) -replace '(?m)^ANTHROPIC_API_KEY=.*$', "ANTHROPIC_API_KEY=$t"
[IO.File]::WriteAllText($p, $c)
Write-Host ("Written. Line now starts with " + $t.Substring(0, 16) + "... length " + $t.Length)
