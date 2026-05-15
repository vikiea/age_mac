# Age Mac Design

## Goal

Build a native macOS version of Age Android in `/Users/qinfuling/www/github/person/age_mac`, with equivalent local age encryption/decryption, key management, operation history, configurable output behavior, and a Liquid Glass-style desktop interface.

## Product Shape

The app is a SwiftUI macOS utility with a `NavigationSplitView` sidebar for Encrypt, Decrypt, Keys, History, and Settings. The detail pane uses system materials and macOS 26 `glassEffect` when available, with material fallbacks for older systems. Actions are available through visible controls and menu commands.

## Engine

The Android app uses a gomobile wrapper around `filippo.io/age`. The macOS app keeps that proven core as a local Go CLI engine instead of rewriting crypto in Swift. Swift launches the engine as a long-running `Process`, passes file lists and secrets through temporary files, and reads JSON Lines progress events from stdout.

## Data

Keys, history, and settings are stored as JSON under Application Support. Private keys remain local. Output defaults to `~/Documents/Age Mac Output`, with `encrypted` and `decrypted` subfolders matching Android behavior.

## Scope

This first macOS version implements real file encryption/decryption, key generation/import/deletion, history, duplicate handling, output directory selection, process cancellation, Codex Run button support, and build verification. It does not attempt App Store signing or notarization.
