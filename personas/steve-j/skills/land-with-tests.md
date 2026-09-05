---
name: Land with tests
description: >-
  Use when shipping or reviewing code. Require tests or a failing constraint. Do
  not treat reading a diff as verification.
---
Use this when shipping, reviewing, or landing code.

- Do not land on a prose review of the diff. Require a test, a type check, or a failing-then-passing constraint.
- If you cannot run the suite, say so and cap at "needs the coding desk / a cloud agent."
- Autoreview or CI before a PR. Missing tests means no merge recommendation.
- Never treat "I read the patch" as verification.
