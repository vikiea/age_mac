<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->

# Open Source Release And Sparkle Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare Age Mac for public GitHub release with documentation, licensing, privacy pages, copyright headers, About information, and Sparkle-based update checking.

**Architecture:** Keep the existing SwiftPM macOS app plus bundled Go engine layout. Add Sparkle as a SwiftPM dependency, wrap it in a focused `UpdateService`, expose About/open-source/update actions through native macOS commands, and serve privacy/appcast metadata from GitHub Pages.

**Tech Stack:** SwiftPM, SwiftUI, AppKit, Sparkle 2, Go age engine, GitHub Pages, GitHub Actions, MIT License.

---

### Task 1: Release Documentation And Legal Files

**Files:**
- Modify: `README.md`
- Create: `COOKBOOK.md`
- Create: `LICENSE`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `PRIVACY.md`
- Create: `pages/index.md`
- Create: `pages/privacy/index.md`
- Create: `pages/appcast.xml`

- [ ] **Step 1: Rewrite README with project overview**

Add sections for purpose, features, architecture map, privacy model, local build, verification, release/update flow, and links to privacy/license.

- [ ] **Step 2: Add cookbook**

Document local build, verification, engine roundtrip, adding keys from `~/.config/age`, packaging, Sparkle key handling, release archive creation, appcast update, and GitHub Pages deployment.

- [ ] **Step 3: Add legal files**

Add MIT `LICENSE`, `THIRD_PARTY_NOTICES.md`, and `PRIVACY.md`. State that Age Mac processes files locally and that Sparkle update checks fetch public update metadata from GitHub Pages.

- [ ] **Step 4: Add Pages content**

Add `pages/index.md`, `pages/privacy/index.md`, and a placeholder `pages/appcast.xml` that Sparkle can read safely before the first release.

### Task 2: Sparkle Update Integration

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AgeMac/Services/UpdateService.swift`
- Modify: `Sources/AgeMac/App/AgeMacApp.swift`
- Modify: `script/build_and_run.sh`
- Create: `scripts/sparkle/generate_keys.sh`
- Create: `scripts/sparkle/release_appcast.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Add Sparkle dependency**

Add `https://github.com/sparkle-project/Sparkle` from `2.9.1` to `Package.swift` and link the `Sparkle` product to the executable target.

- [ ] **Step 2: Create UpdateService**

Implement a small `ObservableObject` around `SPUStandardUpdaterController`, exposing `checkForUpdates()` for UI/menu actions while leaving automatic update policy to Sparkle defaults.

- [ ] **Step 3: Wire app environment and menu command**

Create `@StateObject private var updateService = UpdateService()` in `AgeMacApp`, inject it into `ContentView`, and add an `Age > 检测更新` command.

- [ ] **Step 4: Bundle Sparkle metadata**

Update `script/build_and_run.sh` to generate `Info.plist` keys for `SUFeedURL`, `SUPublicEDKey`, and conservative automatic-check defaults. Copy required SwiftPM-built Sparkle frameworks into the staged app if present.

- [ ] **Step 5: Generate Sparkle key pair safely**

Use Sparkle tooling when available. Commit the public EdDSA key only. Keep the private key under `private/sparkle/` and ensure that directory is ignored.

### Task 3: About And Open Source UI

**Files:**
- Create: `Sources/AgeMac/Views/AboutView.swift`
- Create: `Sources/AgeMac/Support/AppLinks.swift`
- Modify: `Sources/AgeMac/App/AgeMacApp.swift`

- [ ] **Step 1: Add AppLinks constants**

Create stable URL constants for repository, privacy policy, license, and releases.

- [ ] **Step 2: Add About window**

Create a native SwiftUI About window with app icon, version, author `vikiea <vikiea@users.noreply.github.com>`, repository/privacy/license links, open-source component list, and a “检测更新” button wired to `UpdateService`.

- [ ] **Step 3: Add About command**

Add an app menu command that opens the About window using SwiftUI `openWindow`.

### Task 4: Copyright Headers

**Files:**
- Modify Swift files under `Sources/AgeMac/`
- Modify Go files under `Engine/`
- Modify shell scripts under `script/` and `scripts/`
- Modify `Package.swift`
- Modify workflow/config files where comments are valid

- [ ] **Step 1: Add language-appropriate copyright headers**

Use block comments for Swift and Go files:

```swift
/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */
```

Use `#` comments for shell/YAML/TOML and HTML comments for Markdown. Do not edit binary assets or generated lock/checksum files that do not safely accept comments.

### Task 5: GitHub Pages And Automation

**Files:**
- Create: `.github/workflows/pages.yml`
- Create: `.github/workflows/verify.yml`

- [ ] **Step 1: Add Pages workflow**

Publish the `pages/` directory as a static GitHub Pages site via Actions.

- [ ] **Step 2: Add verification workflow**

Run `swift build`, `(cd Engine && env -u GOROOT go test ./...)`, and `git diff --check` on pull requests and pushes.

### Task 6: Verify, Commit, And Push

**Files:**
- All changed files.

- [ ] **Step 1: Run local verification**

Run:

```bash
swift build
(cd Engine && env -u GOROOT go test ./...)
./script/build_and_run.sh --verify
git diff --check
codesign --verify --deep --strict --verbose=2 dist/AgeMac.app
```

- [ ] **Step 2: Commit**

Create a commit such as:

```bash
git add .
git commit -m "Prepare open source release and updates"
```

- [ ] **Step 3: Push to GitHub**

Set the remote to `https://github.com/vikiea/age_mac.git` if missing, push `main`, and report the Pages URLs.

---

## Self-Review

- Spec coverage: documentation, license, privacy, copyright headers, GitHub Pages, About screen, and Sparkle update checking are each covered by a task.
- Placeholder scan: no placeholder tasks remain; the only intentionally placeholder runtime artifact is `pages/appcast.xml`, which is a valid pre-release feed.
- Type consistency: `UpdateService`, `AppLinks`, and `AboutView` are named consistently across tasks.
