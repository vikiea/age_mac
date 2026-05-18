<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->

# Age Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SwiftUI macOS app equivalent to Age Android with a bundled Go age engine and live long-running task progress.

**Architecture:** SwiftUI owns desktop UI, JSON persistence, file panels, and task state. A local Go CLI owns tar/gzip/age streaming work and reports progress as JSON Lines. A project-local run script builds both pieces and stages a real `.app` bundle.

**Tech Stack:** SwiftPM, SwiftUI, AppKit panels, Foundation `Process`, Go 1.26, `filippo.io/age`.

---

### Task 1: Project Bootstrap

- [x] Create SwiftPM app layout under `age_mac`.
- [x] Add design and implementation notes.
- [x] Add build/run script and Codex Run environment.

### Task 2: Go Engine

- [x] Implement CLI commands for key generation, batch encryption, separate encryption, and decryption.
- [x] Emit progress and completion events as JSON Lines.
- [x] Use streaming tar/gzip and age readers/writers.

### Task 3: Swift App Core

- [x] Add models, JSON store, engine client, and file panel service.
- [x] Add cancellable long-running task state.
- [x] Persist keys, settings, and history.

### Task 4: SwiftUI Interface

- [x] Add split-view shell, Liquid Glass-compatible surfaces, encryption/decryption screens, key management, history, and settings.
- [x] Wire menus and toolbar actions.

### Task 5: Verification

- [x] Build Go engine.
- [x] Run engine roundtrip test.
- [x] Build Swift app.
- [x] Launch staged macOS app bundle with process verification.
