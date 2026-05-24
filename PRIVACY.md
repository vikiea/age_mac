<!--
Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
This code is released under the MIT License.
See LICENSE for details.
-->

# Age Mac Privacy Policy

Effective date: May 24, 2026

Age Mac is a local-first macOS encryption app. Its core features run on your Mac and are designed not to upload your files, keys, passphrases, or operation history.

## Data Processed Locally

Age Mac may process these items on your Mac:

- Files and folders you choose for encryption or decryption.
- Passphrases you type for encryption or decryption.
- age public keys and private keys you generate or import.
- Local settings such as output directory, duplicate-file behavior, task options, and theme.
- Local operation history such as file names, output paths, status, timestamps, compression settings, duplicate-file behavior, key names, truncated public-key previews, and private-key fingerprints.

This data is used only to provide the app's local functionality.

## Local Storage

Age Mac stores app state in the user's Application Support directory. Private keys remain local. Passphrases are used for the requested operation and are not written to operation history. Operation history may store key names, truncated public-key previews, and short private-key fingerprints so you can recognize which key was used without storing private key material.

The app may create temporary files while invoking the bundled engine. These files are used locally for process communication and should not be treated as cloud storage or remote backup.

## Network Access

Age Mac does not upload files, keys, passphrases, telemetry, analytics, or operation history.

The app uses Sparkle for update checks. When you check for updates, or when Sparkle performs an update check according to its settings, Sparkle fetches public update metadata from:

```text
https://vikiea.github.io/age_mac/appcast.xml
```

Your network provider, GitHub Pages, or related infrastructure may receive ordinary web request metadata such as IP address, user agent, and request time. Age Mac does not add your files, keys, passphrases, or operation history to those requests.

## Authentication

Viewing or exporting saved private keys requires local macOS authentication, such as device password or biometric authentication when available.

## Changes

Privacy-impacting changes should be documented here before release. If future versions add sync, telemetry, remote storage, or other network-backed features, this policy should be updated before those features ship.

## Contact

Author: vikiea <vikiea@users.noreply.github.com>

Repository: https://github.com/vikiea/age_mac
