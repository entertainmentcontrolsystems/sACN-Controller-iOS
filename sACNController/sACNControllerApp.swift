import SwiftUI
import Combine

/// sACN Controller — iOS version
///
/// Professional E1.31 sACN lighting controller.
/// Features: fixture patching, manual DMX control, looks, cue lists, D16xy converter.

@main
struct sACNControllerApp: App {
    @StateObject private var model = SACNViewModel()

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environmentObject(model)
        }
    }
}
