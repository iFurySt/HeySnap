import Foundation
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        refreshState()
        observeUpdaterState()
    }

    func start() {
        updaterController.startUpdater()
        refreshState()
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = isEnabled
        refreshState()
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = isEnabled
        refreshState()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func observeUpdaterState() {
        observations = [
            updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            },
            updaterController.updater.observe(\.allowsAutomaticUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            },
            updaterController.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            },
            updaterController.updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshState()
                }
            }
        ]
    }

    private func refreshState() {
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        allowsAutomaticUpdates = updaterController.updater.allowsAutomaticUpdates
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updaterController.updater.automaticallyDownloadsUpdates
    }
}
