import Sparkle
import SwiftUI

/// Sparkle 2 controller. `start()` runs once, from `AppDelegate`, and the instance lives with the app.
@MainActor
@Observable
final class Updater {
    private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    private(set) var canCheckForUpdates = false

    /// Creates the standard updater and watches `canCheckForUpdates`. A second call does nothing.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let allowed = change.newValue ?? false
            Task { @MainActor in
                self?.canCheckForUpdates = allowed
            }
        }
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}

/// App-menu item. Disabled until Sparkle says a check is allowed.
struct CheckForUpdatesButton: View {
    var updater: Updater

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
