<!-- Last session: 2026-06-26 03:37 -->
# HANDOFF

## Current Objective
Ship Pesty 1.0.0 — a free, open-source macOS clipboard manager (Paste clone). Native SwiftUI, zero deps, signed + notarized, on Homebrew.

## State
- App builds clean (Swift 6, `swift build`), universal arm64+x86_64.
- Functionally verified: clipboard capture, type detection (text/link/image/file/color/rich), dedup+bump, type-to-search filtering, keyboard selection, persistence with 0600 perms.
- 16 review findings (Codex + 4 adversarial agents) fixed: search/keyboard rework, paste-into-app wait-for-frontmost, modal-dialog guard, image-file orphan leaks, image dedup via SHA-256, Settings @Observable refactor, color-detection gating, removed over-privileged apple-events entitlement.
- Repos: github.com/momenbasel/pesty (app) + github.com/momenbasel/homebrew-pesty (tap).
- Release: Developer ID signed + Apple-notarized DMG (`packaging/Pesty-<version>.dmg`).

## Recently Modified Files
- Sources/Pesty/** (full app)
- scripts/ (build_app, sign_notarize, make_icon, release_build, IconGen.swift)
- packaging/ (Info.plist, Pesty.entitlements)
- .github/workflows/ (ci.yml, release.yml)

## Next Steps / Blockers
- Paste-into-app needs the user to grant Accessibility once (TCC boundary — cannot auto-approve).
- After release: PRs to awesome-mac / open-source-mac-os-apps.
- Release pipeline (sign+notarize) requires Developer ID cert + ASC API key (present locally; CI uses repo secrets).
