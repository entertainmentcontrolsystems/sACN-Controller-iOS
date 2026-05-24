# sACN Controller (iOS)

Professional E1.31 sACN lighting controller for iOS/iPadOS.

## Quick Start

### Requirements
- **macOS 15.0+** with **Xcode 26+**
- iOS 18.0+ or iPadOS 18.0+ device (or macOS 15.0+ for Mac Catalyst)

### Build & Run
1. Clone: `git clone https://github.com/entertainmentcontrolsystems/sACN-Controller-iOS.git`
2. Open `sACNController.xcodeproj` in Xcode
3. Select your target device from the scheme menu
4. Press ⌘R to build and run

No external dependencies, no CocoaPods, no SPM packages needed.

### What It Does
- Patch fixtures across multiple sACN universes
- Manual DMX control with 8-bit and 16-bit support
- Save/recall Looks (DMX snapshots)
- Cue Lists with smoothstep crossfades, delays, and timed auto-advance
- D16xy converter for ETC EOS integration
- Blackout safety

## Architecture

```
sACNController/
├── Models/           # FixtureProfile, Look, CueList, etc.
├── Engine/           # CueListEngine crossfade engine
├── Views/            # SwiftUI screens
├── SACNSender.swift  # E1.31 sACN sender (Network framework)
├── SACNViewModel.swift
└── sACNControllerApp.swift
```

## License

Copyright © 2026 ECS Lighting. All rights reserved.
