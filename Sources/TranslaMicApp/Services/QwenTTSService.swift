import Foundation

struct QwenVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String

    static let all: [QwenVoiceOption] = [
        .init(id: "vivian", name: "Vivian · 中文女声"),
        .init(id: "serena", name: "Serena · 中文女声"),
        .init(id: "uncle_fu", name: "Uncle Fu · 中文男声"),
        .init(id: "ryan", name: "Ryan · 英文男声"),
        .init(id: "aiden", name: "Aiden · 英文男声"),
        .init(id: "ono_anna", name: "Ono Anna · 日文女声"),
        .init(id: "sohee", name: "Sohee · 韩文女声"),
        .init(id: "eric", name: "Eric · 四川话男声"),
        .init(id: "dylan", name: "Dylan · 北京话男声"),
    ]
}

struct QwenAudioChunk: Sendable {
    let pcmData: Data
    let sampleRate: Double
}

struct QwenSynthesisMetrics: Sendable {
    let firstAudioLatency: Double?
    let totalLatency: Double?
    let audioDuration: Double?
    let chunkCount: Int?
}

@MainActor
final class QwenTTSService {
    enum State: Equatable {
        case notInstalled
        case installingRuntime
        case downloadingModel
        case loadingModel
        case ready
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .notInstalled {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    private struct WorkerEvent: Decodable {
        let event: String
        let id: String?
        let message: String?
        let sampleRate: Double?
        let pcmBase64: String?
        let firstAudioLatency: Double?
        let totalLatency: Double?
        let audioDuration: Double?
        let chunkCount: Int?
    }

    private struct SynthesisHandlers {
        let onChunk: (QwenAudioChunk) -> Void
        let completion: (Result<QwenSynthesisMetrics, Error>) -> Void
    }

    private var worker: Process?
    private var workerInput: FileHandle?
    private var outputBuffer = Data()
    private var synthesisHandlers: [String: SynthesisHandlers] = [:]

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TranslaMic/Qwen3TTS", isDirectory: true)
    }

    private var environmentDirectory: URL {
        supportDirectory.appendingPathComponent("environment", isDirectory: true)
    }

    private var modelDirectory: URL {
        supportDirectory.appendingPathComponent("model", isDirectory: true)
    }

    private var pythonURL: URL {
        environmentDirectory.appendingPathComponent("bin/python3")
    }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: pythonURL.path)
            && FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent(".translamic-ready").path)
    }

    func prepare() {
        guard worker == nil else { return }
        guard isInstalled else {
            install()
            return
        }
        startWorker()
    }

    func install() {
        guard state != .installingRuntime, state != .downloadingModel else { return }
        guard let resources = bundledResources() else {
            state = .failed("Qwen3-TTS 运行组件不完整，请重新安装 TranslaMic。")
            return
        }

        state = .installingRuntime
        let supportDirectory = supportDirectory
        let environmentDirectory = environmentDirectory
        let modelDirectory = modelDirectory
        Task { [weak self] in
            do {
                let environment = Self.processEnvironment(supportDirectory: supportDirectory)
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(
                        at: supportDirectory,
                        withIntermediateDirectories: true
                    )
                    if FileManager.default.isExecutableFile(
                        atPath: environmentDirectory.appendingPathComponent("bin/python3").path
                    ) == false {
                        try Self.run(
                            resources.uv,
                            arguments: [
                                "venv", "--python", "3.12", "--python-preference", "managed",
                                environmentDirectory.path,
                            ],
                            environment: environment
                        )
                        try Self.run(
                            resources.uv,
                            arguments: [
                                "pip", "install", "--python",
                                environmentDirectory.appendingPathComponent("bin/python3").path,
                                "mlx-audio==0.4.8",
                            ],
                            environment: environment
                        )
                    }
                }.value
                self?.state = .downloadingModel
                try await Task.detached(priority: .userInitiated) {
                    if FileManager.default.fileExists(
                        atPath: modelDirectory.appendingPathComponent(".translamic-ready").path
                    ) == false {
                        try Self.run(
                            environmentDirectory.appendingPathComponent("bin/python3"),
                            arguments: [
                                resources.worker.path, "--download", "--model-dir", modelDirectory.path,
                            ],
                            environment: environment
                        )
                    }
                }.value
                self?.startWorker()
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func synthesize(
        text: String,
        voice: String,
        languageID: String,
        onChunk: @escaping (QwenAudioChunk) -> Void,
        completion: @escaping (Result<QwenSynthesisMetrics, Error>) -> Void
    ) {
        guard state == .ready, let workerInput else {
            completion(.failure(QwenTTSError.notReady))
            prepare()
            return
        }

        let requestID = UUID().uuidString
        let payload: [String: String] = [
            "id": requestID,
            "text": text,
            "voice": voice,
            "language": Self.qwenLanguage(for: languageID),
        ]
        do {
            var data = try JSONSerialization.data(withJSONObject: payload)
            data.append(0x0A)
            synthesisHandlers[requestID] = SynthesisHandlers(onChunk: onChunk, completion: completion)
            try workerInput.write(contentsOf: data)
        } catch {
            synthesisHandlers.removeValue(forKey: requestID)
            completion(.failure(error))
        }
    }

    func stop() {
        workerInput?.closeFile()
        worker?.terminate()
        worker = nil
        workerInput = nil
        for handlers in synthesisHandlers.values {
            handlers.completion(.failure(QwenTTSError.workerStopped))
        }
        synthesisHandlers.removeAll()
    }

    private func startWorker() {
        guard worker == nil else { return }
        guard let resources = bundledResources(), isInstalled else {
            state = .notInstalled
            return
        }

        state = .loadingModel
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = pythonURL
        process.arguments = [resources.worker.path, "--model-dir", modelDirectory.path]
        process.environment = Self.processEnvironment(supportDirectory: supportDirectory)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] process in
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "Qwen3-TTS process stopped."
            Task { @MainActor [weak self] in
                guard let self, self.worker === process else { return }
                self.worker = nil
                self.workerInput = nil
                self.state = .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            Task { @MainActor [weak self] in self?.consumeWorkerOutput(data) }
        }
        do {
            try process.run()
            worker = process
            workerInput = inputPipe.fileHandleForWriting
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func consumeWorkerOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard let event = try? JSONDecoder().decode(WorkerEvent.self, from: line) else { continue }
            Task { @MainActor [weak self] in self?.handle(event) }
        }
    }

    private func handle(_ event: WorkerEvent) {
        switch event.event {
        case "ready":
            state = .ready
        case "audio":
            guard let id = event.id,
                  let sampleRate = event.sampleRate,
                  let encodedAudio = event.pcmBase64,
                  let pcmData = Data(base64Encoded: encodedAudio) else { return }
            synthesisHandlers[id]?.onChunk(QwenAudioChunk(pcmData: pcmData, sampleRate: sampleRate))
        case "completed":
            guard let id = event.id else { return }
            let metrics = QwenSynthesisMetrics(
                firstAudioLatency: event.firstAudioLatency,
                totalLatency: event.totalLatency,
                audioDuration: event.audioDuration,
                chunkCount: event.chunkCount
            )
            synthesisHandlers.removeValue(forKey: id)?.completion(.success(metrics))
        case "failed":
            guard let id = event.id else {
                state = .failed(event.message ?? "Qwen3-TTS failed.")
                return
            }
            synthesisHandlers.removeValue(forKey: id)?.completion(.failure(QwenTTSError.synthesisFailed(event.message ?? "Unknown error")))
        default:
            break
        }
    }

    private func bundledResources() -> (uv: URL, worker: URL)? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("QwenTTS", isDirectory: true),
        ].compactMap { $0 }
        for directory in candidates {
            let uv = directory.appendingPathComponent("uv")
            let worker = directory.appendingPathComponent("qwen_tts_worker.py")
            if FileManager.default.isExecutableFile(atPath: uv.path),
               FileManager.default.fileExists(atPath: worker.path) {
                return (uv, worker)
            }
        }
        return nil
    }

    nonisolated private static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]
    ) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = errorPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Process failed."
            throw QwenTTSError.setupFailed(message)
        }
    }

    nonisolated private static func processEnvironment(supportDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["UV_CACHE_DIR"] = supportDirectory.appendingPathComponent("uv-cache").path
        environment["UV_PYTHON_INSTALL_DIR"] = supportDirectory.appendingPathComponent("python").path
        environment["HF_HOME"] = supportDirectory.appendingPathComponent("huggingface-cache").path
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    nonisolated private static func qwenLanguage(for languageID: String) -> String {
        switch languageID {
        case "zh-Hans", "zh-Hant", "yue": return "chinese"
        case "en": return "english"
        case "de": return "german"
        case "it": return "italian"
        case "pt": return "portuguese"
        case "es": return "spanish"
        case "ja": return "japanese"
        case "ko": return "korean"
        case "fr": return "french"
        case "ru": return "russian"
        default: return "auto"
        }
    }
}

private enum QwenTTSError: LocalizedError {
    case notReady
    case workerStopped
    case setupFailed(String)
    case synthesisFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "Qwen3-TTS is not ready yet."
        case .workerStopped: return "Qwen3-TTS process stopped."
        case .setupFailed(let message): return "Qwen3-TTS setup failed: \(message)"
        case .synthesisFailed(let message): return "Qwen3-TTS synthesis failed: \(message)"
        }
    }
}
