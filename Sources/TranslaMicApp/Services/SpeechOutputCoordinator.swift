import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

@MainActor
final class SpeechOutputCoordinator: NSObject {
    static let virtualDeviceUID = "io.github.Techeek.TranslaMic.VirtualAudio.device"

    enum State: Equatable {
        case disabled
        case deviceUnavailable
        case ready
        case speaking
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?

    private struct Request {
        let text: String
        let languageID: String
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var requests: [Request] = []
    private var activeRequest: Request?
    private var activeFormat: AVAudioFormat?
    private var scheduledBufferCount = 0
    private var receivedEndOfUtterance = false
    private(set) var state: State = .disabled {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    override init() {
        super.init()
        engine.attach(player)
    }

    func setEnabled(_ enabled: Bool) {
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

        requests.append(Request(text: normalizedText, languageID: languageID))
        startNextRequestIfNeeded()
    }

    func speakTest(languageID: String) {
        let text = languageID.hasPrefix("zh")
            ? "TranslaMic 虚拟麦克风测试成功。"
            : "TranslaMic virtual microphone test successful."
        enqueue(text: text, languageID: languageID)
    }

    func stop() {
        requests.removeAll()
        activeRequest = nil
        receivedEndOfUtterance = false
        scheduledBufferCount = 0
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        engine.stop()
        activeFormat = nil
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
        receivedEndOfUtterance = false
        scheduledBufferCount = 0
        state = .speaking

        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = AVSpeechSynthesisVoice(language: speechVoiceLanguage(for: request.languageID))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        synthesizer.write(utterance) { [weak self] audioBuffer in
            guard let pcmBuffer = audioBuffer as? AVAudioPCMBuffer else { return }
            Task { @MainActor [weak self] in
                self?.handleSynthesizedBuffer(pcmBuffer)
            }
        }
    }

    private func handleSynthesizedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard activeRequest != nil else { return }

        guard buffer.frameLength > 0 else {
            receivedEndOfUtterance = true
            finishRequestIfPossible()
            return
        }

        do {
            try configureEngineIfNeeded(for: buffer.format)
        } catch {
            fail(error.localizedDescription)
            return
        }

        guard let copiedBuffer = copy(buffer) else {
            fail("Unable to copy synthesized audio.")
            return
        }

        scheduledBufferCount += 1
        player.scheduleBuffer(copiedBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                self.finishRequestIfPossible()
            }
        }

        if player.isPlaying == false {
            player.play()
        }
    }

    private func configureEngineIfNeeded(for format: AVAudioFormat) throws {
        if activeFormat != format || engine.isRunning == false {
            player.stop()
            engine.stop()
            engine.disconnectNodeOutput(player)

            guard let deviceID = virtualOutputDeviceID() else {
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

            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()
            activeFormat = format
        }
    }

    private func finishRequestIfPossible() {
        guard receivedEndOfUtterance, scheduledBufferCount == 0 else { return }
        activeRequest = nil
        if requests.isEmpty {
            state = .ready
        } else {
            startNextRequestIfNeeded()
        }
    }

    private func fail(_ message: String) {
        requests.removeAll()
        activeRequest = nil
        receivedEndOfUtterance = false
        scheduledBufferCount = 0
        player.stop()
        engine.stop()
        activeFormat = nil
        state = .failed(message)
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

    private func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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
}

private enum SpeechOutputError: LocalizedError {
    case virtualDeviceUnavailable
    case outputAudioUnitUnavailable
    case couldNotSelectVirtualDevice(OSStatus)

    var errorDescription: String? {
        switch self {
        case .virtualDeviceUnavailable:
            return "TranslaMic Virtual Microphone is not installed."
        case .outputAudioUnitUnavailable:
            return "The macOS audio output unit is unavailable."
        case .couldNotSelectVirtualDevice(let status):
            return "Could not select TranslaMic Virtual Microphone (Core Audio status \(status))."
        }
    }
}
