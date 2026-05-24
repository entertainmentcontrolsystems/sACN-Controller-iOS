# sACN Controller (iOS)

Professional E1.31 sACN lighting controller for iOS/iPadOS.

## Features

- **Fixture patching** — Patch fixtures across multiple sACN universes
- **Manual DMX control** — Per-channel control with 8-bit and 16-bit support
- **Looks** — Save and recall complete DMX snapshots
- **Cue Lists** — Sequenced playback with smoothstep crossfades, delays, and timed auto-GO
- **D16xy converter** — Convert D16xy sACN input to fixture-specific DMX output
- **Blackout** — Instant kill switch

## Requirements

- iOS 18.0+ / iPadOS 18.0+ / macOS 15.0+
- Xcode 26+

## Build

1. Open `sACNController.xcodeproj` in Xcode
2. Select target device
3. Build → Run

## Architecture

```
sACNController/
├── Models/           # FixtureProfile, Look, CueList, etc.
├── Engine/           # CueListEngine crossfade engine
├── Views/            # SwiftUI screens
├── SACNSender.swift  # Shared sACN sender (symlinked from CineCalibrator-iOS)
├── SACNViewModel.swift
└── sACNControllerApp.swift
```

## License

Copyright © 2026 ECS Lighting. All rights reserved.
