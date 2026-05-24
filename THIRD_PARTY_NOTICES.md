<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->

# Third-Party Notices

Age Mac includes or depends on the following open-source components.

## Sparkle

- Project: https://sparkle-project.org/
- Source: https://github.com/sparkle-project/Sparkle
- Purpose: macOS update checking and installation UI.
- License: MIT License.

## age

- Project: https://age-encryption.org/
- Source: https://filippo.io/age
- Purpose: age encryption primitives used by the local Go engine.
- License: BSD-style license. See the upstream project for complete terms.

## Go extended libraries

- Source: https://pkg.go.dev/filippo.io/hpke
- Source: https://pkg.go.dev/golang.org/x/crypto
- Source: https://pkg.go.dev/golang.org/x/sys
- Purpose: supporting crypto and platform APIs used through the Go age dependency graph.
- License: BSD-style licenses. See upstream modules for complete terms.

## Apple system frameworks

Age Mac uses macOS frameworks including SwiftUI, AppKit, Foundation, Combine, UniformTypeIdentifiers, and LocalAuthentication. These are provided by Apple as part of the macOS and Xcode SDKs.

## Notes

Keep this file updated when adding new dependencies, especially before commercial packaging or notarized distribution.
