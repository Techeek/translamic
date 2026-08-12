import Foundation

enum SpeechSynthesisBackend: String, Codable, CaseIterable {
    case system
    case qwen3
}

struct AppSettings: Codable {
    var selectedSourceID: String?
    var selectedSourceIDs: [String]
    var sourceLanguageOverrides: [String: String]
    var sourceOutputLanguageOverrides: [String: String]
    var inputLanguageID: String
    var outputLanguageID: String
    var interfaceLanguageID: String?
    var overlayStyle: OverlayStyle
    var subtitleMode: SubtitleMode
    var subtitleDisplayMode: SubtitleDisplayMode
    var glossary: [String: String]
    var virtualMicrophoneEnabled: Bool
    var speechVoiceIdentifiers: [String: String]
    var speechSynthesisBackend: SpeechSynthesisBackend
    var qwenVoiceIdentifier: String

    static let `default` = AppSettings(
        selectedSourceID: nil,
        selectedSourceIDs: [],
        sourceLanguageOverrides: [:],
        sourceOutputLanguageOverrides: [:],
        inputLanguageID: "en",
        outputLanguageID: "zh-Hans",
        interfaceLanguageID: nil,
        overlayStyle: .default,
        subtitleMode: .balanced,
        subtitleDisplayMode: .both,
        glossary: [:],
        virtualMicrophoneEnabled: false,
        speechVoiceIdentifiers: [:],
        speechSynthesisBackend: .system,
        qwenVoiceIdentifier: "vivian"
    )

    // Custom decoder so existing settings files load cleanly as new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedSourceID = try? c.decodeIfPresent(String.self, forKey: .selectedSourceID)
        selectedSourceIDs = (try? c.decodeIfPresent([String].self, forKey: .selectedSourceIDs))
            ?? selectedSourceID.map { [$0] }
            ?? AppSettings.default.selectedSourceIDs
        sourceLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceLanguageOverrides))
            ?? AppSettings.default.sourceLanguageOverrides
        sourceOutputLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceOutputLanguageOverrides))
            ?? AppSettings.default.sourceOutputLanguageOverrides
        inputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .inputLanguageID))
            ?? AppSettings.default.inputLanguageID
        outputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .outputLanguageID))
            ?? AppSettings.default.outputLanguageID
        interfaceLanguageID = try? c.decodeIfPresent(String.self, forKey: .interfaceLanguageID)
        overlayStyle = (try? c.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle))
            ?? AppSettings.default.overlayStyle
        subtitleMode = (try? c.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode))
            ?? AppSettings.default.subtitleMode
        subtitleDisplayMode = (try? c.decodeIfPresent(SubtitleDisplayMode.self, forKey: .subtitleDisplayMode))
            ?? AppSettings.default.subtitleDisplayMode
        glossary = (try? c.decodeIfPresent([String: String].self, forKey: .glossary))
            ?? AppSettings.default.glossary
        virtualMicrophoneEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .virtualMicrophoneEnabled))
            ?? AppSettings.default.virtualMicrophoneEnabled
        speechVoiceIdentifiers = (try? c.decodeIfPresent([String: String].self, forKey: .speechVoiceIdentifiers))
            ?? AppSettings.default.speechVoiceIdentifiers
        speechSynthesisBackend = (try? c.decodeIfPresent(SpeechSynthesisBackend.self, forKey: .speechSynthesisBackend))
            ?? AppSettings.default.speechSynthesisBackend
        qwenVoiceIdentifier = (try? c.decodeIfPresent(String.self, forKey: .qwenVoiceIdentifier))
            ?? AppSettings.default.qwenVoiceIdentifier
    }

    init(
        selectedSourceID: String?,
        selectedSourceIDs: [String] = [],
        sourceLanguageOverrides: [String: String] = [:],
        sourceOutputLanguageOverrides: [String: String] = [:],
        inputLanguageID: String,
        outputLanguageID: String,
        interfaceLanguageID: String?,
        overlayStyle: OverlayStyle,
        subtitleMode: SubtitleMode,
        subtitleDisplayMode: SubtitleDisplayMode,
        glossary: [String: String],
        virtualMicrophoneEnabled: Bool = false,
        speechVoiceIdentifiers: [String: String] = [:],
        speechSynthesisBackend: SpeechSynthesisBackend = .system,
        qwenVoiceIdentifier: String = "vivian"
    ) {
        self.selectedSourceID = selectedSourceID
        self.selectedSourceIDs = selectedSourceIDs
        self.sourceLanguageOverrides = sourceLanguageOverrides
        self.sourceOutputLanguageOverrides = sourceOutputLanguageOverrides
        self.inputLanguageID  = inputLanguageID
        self.outputLanguageID = outputLanguageID
        self.interfaceLanguageID = interfaceLanguageID
        self.overlayStyle     = overlayStyle
        self.subtitleMode     = subtitleMode
        self.subtitleDisplayMode = subtitleDisplayMode
        self.glossary         = glossary
        self.virtualMicrophoneEnabled = virtualMicrophoneEnabled
        self.speechVoiceIdentifiers = speechVoiceIdentifiers
        self.speechSynthesisBackend = speechSynthesisBackend
        self.qwenVoiceIdentifier = qwenVoiceIdentifier
    }
}
