# Desktop shortcuts / scheduled task — PREP ONLY (C1)

C1 prepares documentation only. **Do not create shortcuts or scheduled tasks** without separate operator authorization (related to C5 activation).

## Planned (later)

| Name | Target | Notes |
|---|---|---|
| Start Buzz | `powershell -File E:\TORQ-BUZZ\scripts\Start-Buzz.ps1` | Live only after C5 |
| Stop Buzz | `powershell -File E:\TORQ-BUZZ\scripts\Stop-Buzz.ps1` | Receipt-owned only |
| Buzz Status | `powershell -File E:\TORQ-BUZZ\scripts\Buzz-Status.ps1` | Read-only OK earlier |

## Scheduled task

- Default: **disabled**
- At-logon start requires explicit operator approval (T32)
