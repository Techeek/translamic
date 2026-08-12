import AppKit
import Combine
import ServiceManagement
import os.log

@MainActor
final class LaunchAtLoginService: ObservableObject {
    private let appService = SMAppService.mainApp
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var launchesAtLogin = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var updateErrorMessage: String?

    init(notificationCenter: NotificationCenter = .default) {
        refreshStatus()
        notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatus() }
            .store(in: &cancellables)
    }

    func setLaunchesAtLogin(_ shouldLaunchAtLogin: Bool) {
        updateErrorMessage = nil
        do {
            if shouldLaunchAtLogin {
                try appService.register()
            } else {
                try appService.unregister()
            }
        } catch {
            Logger.launchAtLogin.error(
                "Failed to update launch-at-login setting: \(error.localizedDescription, privacy: .public)"
            )
            updateErrorMessage = error.localizedDescription
        }
        refreshStatus()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refreshStatus() {
        switch appService.status {
        case .enabled:
            launchesAtLogin = true
            requiresApproval = false
            updateErrorMessage = nil
        case .requiresApproval:
            launchesAtLogin = true
            requiresApproval = true
            updateErrorMessage = nil
        case .notRegistered, .notFound:
            launchesAtLogin = false
            requiresApproval = false
        @unknown default:
            launchesAtLogin = false
            requiresApproval = false
        }
    }
}

private extension Logger {
    static let launchAtLogin = Logger(
        subsystem: "io.github.Techeek.TranslaMic",
        category: "launchAtLogin"
    )
}
