import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct SpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
final class SpeechOutputCoordinator: NSObject {
    nonisolated static let virtualDeviceUID = "io.github.Techeek.TranslaMic.VirtualAudio.device"

    enum State: Equatable {
        case disabled
        case deviceUnavailable
        case installingVoiceEngine
        case downloadingVoiceModel
        case loadingVoiceModel
        case ready
        case speaking
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?

    private struct Request {
        let text: String
        let languageID: String
        let voiceIdentifier: String?
        let backend: SpeechSynthesisBackend
        let mossVoiceIdentifier: String
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let previewSynthesizer = AVSpeechSynthesizer()
    private let audioRenderer = SpeechAudioRenderer(deviceUID: SpeechOutputCoordinator.virtualDeviceUID)
    private let previewAudioRenderer = SpeechAudioRenderer(deviceUID: nil)
    private let mossService = MossTTSService()
    private var requests: [Request] = []
    private var activeRequest: Request?
    private var voiceIdentifiersByLanguageID: [String: String] = [:]
    private var backend: SpeechSynthesisBackend = .system
    private var mossVoiceIdentifier = "Adam"
    private var isEnabled = false
    private lazy var installedVoices = AVSpeechSynthesisVoice.speechVoices()
    private var voiceOptionsCache: [String: [SpeechVoiceOption]] = [:]
    private(set) var state: State = .disabled {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    override init() {
        super.init()
        mossService.onStateChange = { [weak self] mossState in
            guard let self, self.backend == .mossNano else { return }
            switch mossState {
            case .notInstalled: self.state = .installingVoiceEngine
            case .installingRuntime: self.state = .installingVoiceEngine
            case .downloadingModel: self.state = .downloadingVoiceModel
            case .loadingModel: self.state = .loadingVoiceModel
            case .ready:
                if self.isEnabled {
                    self.refreshDeviceState()
                } else {
                    self.state = .disabled
                }
                self.startNextRequestIfNeeded()
            case .failed(let message): self.fail(message)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            refreshDeviceState()
        } else {
            stop()
            state = .disabled
        }
    }

    func refreshDeviceState() {
        guard activeRequest == nil else { return }
        state = virtualOutputDeviceID() == nil ? .deviceUnavailable : .ready
    }

    func enqueue(text: String, languageID: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else { return }

        requests.append(Request(
            text: normalizedText,
            languageID: languageID,
            voiceIdentifier: voiceIdentifiersByLanguageID[languageID],
            backend: backend,
            mossVoiceIdentifier: mossVoiceIdentifier
        ))
        startNextRequestIfNeeded()
    }

    func setVoiceIdentifiers(_ identifiers: [String: String]) {
        voiceIdentifiersByLanguageID = identifiers
    }

    func setSynthesisBackend(_ backend: SpeechSynthesisBackend, mossVoiceIdentifier: String) {
        self.backend = backend
        self.mossVoiceIdentifier = mossVoiceIdentifier
        if backend == .mossNano {
            mossService.prepare()
        } else if state != .disabled {
            refreshDeviceState()
        }
    }

    func installMossVoiceEngine() {
        mossService.install()
    }

    func availableVoices(for languageID: String) -> [SpeechVoiceOption] {
        if let cachedOptions = voiceOptionsCache[languageID] {
            return cachedOptions
        }

        let requestedLanguage = speechVoiceLanguage(for: languageID)
        let requestedLocale = Locale(identifier: requestedLanguage)
        let requestedLanguageCode = requestedLocale.language.languageCode?.identifier
        let requestedRegion = requestedLocale.region?.identifier

        var preferredVoiceByName: [String: AVSpeechSynthesisVoice] = [:]
        for voice in installedVoices {
            guard voice.voiceTraits.contains(.isNoveltyVoice) == false else {
                continue
            }
            let voiceLocale = Locale(identifier: voice.language)
            guard voiceLocale.language.languageCode?.identifier == requestedLanguageCode else {
                continue
            }
            if let requestedRegion,
               voiceLocale.region?.identifier != requestedRegion {
                continue
            }
            let key = voice.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: requestedLocale)
            if let existing = preferredVoiceByName[key], existing.quality.rawValue >= voice.quality.rawValue {
                continue
            }
            preferredVoiceByName[key] = voice
        }
        var options = preferredVoiceByName.values.map {
            SpeechVoiceOption(id: $0.identifier, name: $0.name)
        }
        options.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        voiceOptionsCache[languageID] = options
        return options
    }

    func speakPreview(text: String, languageID: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else { return }

        if backend == .mossNano {
            previewAudioRenderer.stop()
            let renderToken = previewAudioRenderer.begin { _ in }
            mossService.synthesize(
                text: normalizedText,
                voice: mossVoiceIdentifier,
                languageID: languageID,
                onChunk: { [weak self] chunk in
                    guard let buffer = SpeechAudioRenderer.buffer(from: chunk) else {
                        self?.previewAudioRenderer.stop()
                        return
                    }
                    self?.previewAudioRenderer.consume(buffer, token: renderToken)
                }
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let metrics):
                    self.log(metrics, context: "preview")
                    self.previewAudioRenderer.finish(token: renderToken)
                case .failure(let error):
                    self.previewAudioRenderer.stop()
                    if case .failed = self.mossService.state {
                        self.fail(error.localizedDescription)
                    }
                }
            }
        } else {
            previewSynthesizer.stopSpeaking(at: .immediate)
            previewSynthesizer.speak(configuredUtterance(text: normalizedText, languageID: languageID))
        }
    }

    func stop() {
        requests.removeAll()
        activeRequest = nil
        synthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.stopSpeaking(at: .immediate)
        audioRenderer.stop()
        previewAudioRenderer.stop()
    }

    private func startNextRequestIfNeeded() {
        guard activeRequest == nil, requests.isEmpty == false else { return }
        guard virtualOutputDeviceID() != nil else {
            requests.removeAll()
            state = .deviceUnavailable
            return
        }

        let request = requests.removeFirst()
        activeRequest = request
        state = .speaking

        if request.backend == .mossNano {
            guard mossService.state == .ready else {
                requests.insert(request, at: 0)
                activeRequest = nil
                mossService.prepare()
                return
            }
            let renderToken = audioRenderer.begin { [weak self] playbackResult in
                Task { @MainActor [weak self] in
                    switch playbackResult {
                    case .success: self?.finishActiveRequest()
                    case .failure(let error): self?.fail(error.localizedDescription)
                    }
                }
            }
            mossService.synthesize(
                text: request.text,
                voice: request.mossVoiceIdentifier,
                languageID: request.languageID,
                onChunk: { [weak self] chunk in
                    guard let buffer = SpeechAudioRenderer.buffer(from: chunk) else {
                        self?.fail(SpeechOutputError.couldNotCopySynthesizedAudio.localizedDescription)
                        return
                    }
                    self?.audioRenderer.consume(buffer, token: renderToken)
                }
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let metrics):
                    self.log(metrics, context: "virtual microphone")
                    self.audioRenderer.finish(token: renderToken)
                case .failure(let error): self.fail(error.localizedDescription)
                }
            }
            return
        }

        let utterance = configuredUtterance(
            text: request.text,
            languageID: request.languageID,
            voiceIdentifier: request.voiceIdentifier
        )

        let renderToken = audioRenderer.begin { [weak self] result in
            Task { @MainActor [weak self] in
                switch result {
                case .success:
                    self?.finishActiveRequest()
                case .failure(let error):
                    self?.fail(error.localizedDescription)
                }
            }
        }

        synthesizer.write(utterance) { [weak self] audioBuffer in
            guard let pcmBuffer = audioBuffer as? AVAudioPCMBuffer else { return }
            self?.audioRenderer.consume(pcmBuffer, token: renderToken)
        }
    }

    private func finishActiveRequest() {
        guard activeRequest != nil else { return }
        activeRequest = nil
        if requests.isEmpty {
            state = .ready
        } else {
            startNextRequestIfNeeded()
        }
    }

    private func configuredUtterance(
        text: String,
        languageID: String,
        voiceIdentifier: String? = nil
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let selectedVoiceIdentifier = voiceIdentifier ?? voiceIdentifiersByLanguageID[languageID]
        if let selectedVoiceIdentifier,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier),
           selectedVoice.voiceTraits.contains(.isNoveltyVoice) == false,
           voiceMatchesLanguage(selectedVoice, languageID: languageID) {
            utterance.voice = selectedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: speechVoiceLanguage(for: languageID))
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }

    private func voiceMatchesLanguage(
        _ voice: AVSpeechSynthesisVoice,
        languageID: String
    ) -> Bool {
        let requestedLocale = Locale(identifier: speechVoiceLanguage(for: languageID))
        let voiceLocale = Locale(identifier: voice.language)
        guard voiceLocale.language.languageCode == requestedLocale.language.languageCode else {
            return false
        }
        if let requestedRegion = requestedLocale.region {
            return voiceLocale.region == requestedRegion
        }
        return true
    }

    private func fail(_ message: String) {
        requests.removeAll()
        activeRequest = nil
        synthesizer.stopSpeaking(at: .immediate)
        audioRenderer.stop()
        previewAudioRenderer.stop()
        mossService.stop()
        state = .failed(message)
    }

    private func log(_ metrics: MossSynthesisMetrics, context: String) {
        let firstAudio = metrics.firstAudioLatency.map { String(format: "%.2f", $0) } ?? "n/a"
        let total = metrics.totalLatency.map { String(format: "%.2f", $0) } ?? "n/a"
        let duration = metrics.audioDuration.map { String(format: "%.2f", $0) } ?? "n/a"
        NSLog(
            "TranslaMic MOSS-TTS-Nano %@: first audio=%@s, generation=%@s, audio=%@s, chunks=%d",
            context,
            firstAudio,
            total,
            duration,
            metrics.chunkCount ?? 0
        )
    }

    private func virtualOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else {
            return nil
        }

        return devices.first { deviceUID($0) == Self.virtualDeviceUID }
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, pointer)
        }
        return status == noErr ? uid as String? : nil
    }

    private func speechVoiceLanguage(for languageID: String) -> String {
        switch languageID {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "yue": return "zh-HK"
        default: return languageID
        }
    }

}

final class SpeechAudioRenderer: @unchecked Sendable {
    typealias Completion = @Sendable (Result<Void, Error>) -> Void

    private let queue = DispatchQueue(
        label: "io.github.Techeek.TranslaMic.speech-audio-renderer",
        qos: .userInitiated
    )
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let deviceUID: String?
    private var activeFormat: AVAudioFormat?
    private var activeToken: UUID?
    private var completion: Completion?
    private var scheduledBufferCount = 0
    private var receivedEndOfUtterance = false

    init(deviceUID: String?) {
        self.deviceUID = deviceUID
        engine.attach(player)
    }

    func begin(completion: @escaping Completion) -> UUID {
        let token = UUID()
        queue.sync {
            activeToken = token
            self.completion = completion
            scheduledBufferCount = 0
            receivedEndOfUtterance = false
        }
        return token
    }

    func consume(_ source: AVAudioPCMBuffer, token: UUID) {
        if source.frameLength == 0 {
            queue.async { [weak self] in
                guard let self, self.activeToken == token else { return }
                self.receivedEndOfUtterance = true
                self.finishIfPossible()
            }
            return
        }

        guard let buffer = Self.copy(source) else {
            queue.async { [weak self] in
                self?.fail(SpeechOutputError.couldNotCopySynthesizedAudio, token: token)
            }
            return
        }

        queue.async { [weak self] in
            guard let self, self.activeToken == token else { return }
            do {
                try self.configureEngineIfNeeded(for: buffer.format)
            } catch {
                self.fail(error, token: token)
                return
            }

            self.scheduledBufferCount += 1
            self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.activeToken == token else { return }
                    self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                    self.finishIfPossible()
                }
            }

            if self.player.isPlaying == false {
                self.player.play()
            }
        }
    }

    func finish(token: UUID) {
        queue.async { [weak self] in
            guard let self, self.activeToken == token else { return }
            self.receivedEndOfUtterance = true
            self.finishIfPossible()
        }
    }

    func stop() {
        queue.sync {
            activeToken = nil
            completion = nil
            scheduledBufferCount = 0
            receivedEndOfUtterance = false
            player.stop()
            engine.stop()
            activeFormat = nil
        }
    }

    private func configureEngineIfNeeded(for format: AVAudioFormat) throws {
        guard activeFormat != format || engine.isRunning == false else { return }

        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)

        if let deviceUID {
            guard let deviceID = outputDeviceID(matching: deviceUID) else {
                throw SpeechOutputError.virtualDeviceUnavailable
            }

            var mutableDeviceID = deviceID
            guard let audioUnit = engine.outputNode.audioUnit else {
                throw SpeechOutputError.outputAudioUnitUnavailable
            }

            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw SpeechOutputError.couldNotSelectVirtualDevice(status)
            }
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        activeFormat = format
    }

    private func finishIfPossible() {
        guard receivedEndOfUtterance, scheduledBufferCount == 0 else { return }
        let completion = completion
        activeToken = nil
        self.completion = nil
        completion?(.success(()))
    }

    private func fail(_ error: Error, token: UUID) {
        guard activeToken == token else { return }
        let completion = completion
        activeToken = nil
        self.completion = nil
        scheduledBufferCount = 0
        receivedEndOfUtterance = false
        player.stop()
        engine.stop()
        activeFormat = nil
        completion?(.failure(error))
    }

    private func outputDeviceID(matching requestedUID: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else {
            return nil
        }

        return devices.first { deviceUID($0) == requestedUID }
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, pointer)
        }
        return status == noErr ? uid as String? : nil
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let destination = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else {
            return nil
        }

        destination.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        for index in sourceBuffers.indices {
            let sourceBuffer = sourceBuffers[index]
            let destinationBuffer = destinationBuffers[index]
            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffer.mData else {
                return nil
            }
            memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
            destinationBuffers[index].mDataByteSize = sourceBuffer.mDataByteSize
        }
        return destination
    }

    static func buffer(from chunk: MossAudioChunk) -> AVAudioPCMBuffer? {
        guard chunk.sampleRate > 0, chunk.pcmData.count >= 2 else { return nil }
        let frameCount = chunk.pcmData.count / MemoryLayout<Int16>.size
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: chunk.sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let samples = buffer.floatChannelData?[0] else {
            return nil
        }

        chunk.pcmData.withUnsafeBytes { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            for index in 0..<frameCount {
                let byteIndex = index * 2
                let bits = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                samples[index] = Float(Int16(bitPattern: bits)) / 32768.0
            }
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }
}

private enum SpeechOutputError: LocalizedError {
    case virtualDeviceUnavailable
    case outputAudioUnitUnavailable
    case couldNotSelectVirtualDevice(OSStatus)
    case couldNotCopySynthesizedAudio

    var errorDescription: String? {
        switch self {
        case .virtualDeviceUnavailable:
            return "TranslaMic Virtual Microphone is not installed."
        case .outputAudioUnitUnavailable:
            return "The macOS audio output unit is unavailable."
        case .couldNotSelectVirtualDevice(let status):
            return "Could not select TranslaMic Virtual Microphone (Core Audio status \(status))."
        case .couldNotCopySynthesizedAudio:
            return "Unable to copy synthesized audio."
        }
    }
}
