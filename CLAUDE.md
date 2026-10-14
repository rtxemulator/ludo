# Project rules for AI assistants

- Never import Flutter (package:flutter/*) into lib/engine/.
- Every rule change or engine addition requires a corresponding unit test.
- The engine is the single source of truth; the UI never mutates state directly.
- Add no external dependencies without asking first.
- Prefer procedural CustomPainter drawing over raster image assets.
- Create a Git commit before and after every AI-assisted code change.

Specs live in docs/. Start with docs/ludo-roadmap.md (Milestone 1: engine + tests only, no UI).
