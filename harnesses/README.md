# Custom ACP harnesses

These JSON definitions register additional CLI-backed ACP harnesses with Buzz Desktop.

| File | Harness | Model pin |
|---|---|---|
| `qwen.json` | Qwen Code | Qwen CLI default |
| `qwen-max.json` | Qwen Code (Qwen3.8 Max) | `qwen3.8-max-preview` |
| `qwen-deepseek.json` | Qwen Code (DeepSeek) | `deepseek-v4-pro` |
| `qwen-glm.json` | Qwen Code (GLM 5.2) | `glm-5.2` |
| `gemini.json` | Gemini CLI | `gemini-3.5-flash-lite` |

Install them into the current user's Buzz app-data directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-CustomHarnesses.ps1
```

The installer never overwrites an existing harness unless `-Force` is provided.

The DeepSeek harness includes `QWEN_CODE_API_TIMEOUT_MS=600000` so long Buzz prompts do not hit Qwen Code's shorter request timeout. The Gemini harness includes `GEMINI_PTY_INFO=child_process` so Gemini CLI does not use node-pty when Buzz spawns it without a Windows console. Harness definitions do not contain API keys; Qwen and Gemini credentials stay in their own user-level CLI configuration.
