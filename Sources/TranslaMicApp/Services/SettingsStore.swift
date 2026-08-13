import Foundation

@MainActor
final class SettingsStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = appSupportRoot.appendingPathComponent("TranslaMic", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("settings.json")
        }
    }

    func load() -> AppSettings {
        do {
            let data = try Data(contentsOf: fileURL)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            if let rawSettings = String(data: data, encoding: .utf8),
               rawSettings.contains("\"qwen3\"") || rawSettings.contains("\"qwenVoiceIdentifier\"") {
                // Keep the decoder compatible with previous releases, then
                // rewrite the file once so no obsolete Qwen setting remains.
                save(settings)
            }
            return settings
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileReadNoSuchFileError {
                fputs("Failed to load settings: \(error)\n", stderr)
            }
            return .default
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let data = try JSONEncoder.pretty.encode(settings)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            fputs("Failed to save settings: \(error)\n", stderr)
        }
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
