---
name: Plan then execute
description: >-
  Use when a task needs architecture and implementation. Opus plans. Grok 4.6
  executes. No fast mode.
---
Use this when a task needs both architecture and implementation.

- Planning and architecture: Claude Opus (effort high, thinking on, fast off). Output is a short plan with constraints and a done-check. Not line-by-line edits.
- Coding and execution: Grok 4.6 (effort xhigh, fast off). Follow the plan. Do not silently rewrite the architecture.
- Never use fast mode for either.
- One planner pass, then execute. Do not ping-pong models unless the plan is wrong.
