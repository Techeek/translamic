import Foundation

struct MossVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String

    static let all: [MossVoiceOption] = [
        .init(id: "Adam", name: "Adam · English Male"),
        .init(id: "Nathan", name: "Nathan · English Male"),
        .init(id: "Ava", name: "Ava · English Female"),
        .init(id: "Bella", name: "Bella · English Female"),
        .init(id: "Junhao", name: "Junhao · 中文男声"),
        .init(id: "Zhiming", name: "Zhiming · 中文男声"),
        .init(id: "Weiguo", name: "Weiguo · 中文男声"),
        .init(id: "Xiaoyu", name: "Xiaoyu · 中文女声"),
        .init(id: "Yuewen", name: "Yuewen · 中文女声"),
        .init(id: "Lingyu", name: "Lingyu · 中文女声"),
        .init(id: "Saki", name: "Saki · 日本語女性"),
        .init(id: "Soyo", name: "Soyo · 日本語女性"),
        .init(id: "Mortis", name: "Mortis · 日本語女性"),
        .init(id: "Umiri", name: "Umiri · 日本語女性"),
        .init(id: "Mei", name: "Mei · 日本語女性"),
        .init(id: "Anon", name: "Anon · 日本語女性"),
        .init(id: "Arisa", name: "Arisa · 日本語女性"),
    ]
}

struct MossAudioChunk: Sendable {
    let pcmData: Data
    let sampleRate: Double
}

struct MossSynthesisMetrics: Sendable {
    let firstAudioLatency: Double?
    let totalLatency: Double?
    let audioDuration: Double?
    let chunkCount: Int?
}

@MainActor
final class MossTTSService {
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
        let onChunk: (MossAudioChunk) -> Void
        let completion: (Result<MossSynthesisMetrics, Error>) -> Void
    }

    private var worker: Process?
    private var workerInput: FileHandle?
    private var outputBuffer = Data()
    private var synthesisHandlers: [String: SynthesisHandlers] = [:]

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TranslaMic/MossTTS", isDirectory: true)
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
            state = .failed("MOSS-TTS-Nano 运行组件不完整，请重新安装 TranslaMic。")
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
                        // The isolated environment is self-contained after installation.
                        // Reclaim downloaded wheels and source archives so first-time setup
                        // does not leave hundreds of megabytes of disposable cache behind.
                        try? Self.run(
                            resources.uv,
                            arguments: ["cache", "clean"],
                            environment: environment
                        )
                        try Self.run(
                            resources.uv,
                            arguments: [
                                "pip", "install", "--python",
                                environmentDirectory.appendingPathComponent("bin/python3").path,
                                "--no-deps",
                                "git+https://github.com/OpenMOSS/MOSS-TTS-Nano.git@cc7bdf19c7639c0870dab22045a33b442760f6be",
                            ],
                            environment: environment
                        )
                        try Self.run(
                            resources.uv,
                            arguments: [
                                "pip", "install", "--python",
                                environmentDirectory.appendingPathComponent("bin/python3").path,
                                "numpy>=1.24", "sentencepiece>=0.1.99",
                                "torch==2.7.0", "torchaudio==2.7.0",
                                "transformers==4.57.1", "soundfile",
                                "onnxruntime>=1.20.0", "huggingface_hub",
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
        onChunk: @escaping (MossAudioChunk) -> Void,
        completion: @escaping (Result<MossSynthesisMetrics, Error>) -> Void
    ) {
        guard state == .ready, let workerInput else {
            completion(.failure(MossTTSError.notReady))
            prepare()
            return
        }

        let requestID = UUID().uuidString
        let payload: [String: String] = [
            "id": requestID,
            "text": text,
            "voice": voice,
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
            handlers.completion(.failure(MossTTSError.workerStopped))
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
            let message = String(data: errorData, encoding: .utf8) ?? "MOSS-TTS-Nano process stopped."
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
            synthesisHandlers[id]?.onChunk(MossAudioChunk(pcmData: pcmData, sampleRate: sampleRate))
        case "completed":
            guard let id = event.id else { return }
            let metrics = MossSynthesisMetrics(
                firstAudioLatency: event.firstAudioLatency,
                totalLatency: event.totalLatency,
                audioDuration: event.audioDuration,
                chunkCount: event.chunkCount
            )
            synthesisHandlers.removeValue(forKey: id)?.completion(.success(metrics))
        case "failed":
            guard let id = event.id else {
                state = .failed(event.message ?? "MOSS-TTS-Nano failed.")
                return
            }
            synthesisHandlers.removeValue(forKey: id)?.completion(.failure(MossTTSError.synthesisFailed(event.message ?? "Unknown error")))
        default:
            break
        }
    }

    private func bundledResources() -> (uv: URL, worker: URL)? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("MossTTS", isDirectory: true),
        ].compactMap { $0 }
        for directory in candidates {
            let uv = directory.appendingPathComponent("uv")
            let worker = directory.appendingPathComponent("moss_tts_worker.py")
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
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("translamic-moss-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            throw MossTTSError.setupFailed("Unable to create the setup log.")
        }
        defer {
            try? logHandle.close()
            try? FileManager.default.removeItem(at: logURL)
        }
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // A file avoids blocking when model downloads emit more output than a
        // pipe can hold while this synchronous helper waits for completion.
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? logHandle.synchronize()
            let data = (try? Data(contentsOf: logURL)) ?? Data()
            let message = String(data: data, encoding: .utf8) ?? "Process failed."
            throw MossTTSError.setupFailed(message)
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

}

private enum MossTTSError: LocalizedError {
    case notReady
    case workerStopped
    case setupFailed(String)
    case synthesisFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "MOSS-TTS-Nano is not ready yet."
        case .workerStopped: return "MOSS-TTS-Nano process stopped."
        case .setupFailed(let message): return "MOSS-TTS-Nano setup failed: \(message)"
        case .synthesisFailed(let message): return "MOSS-TTS-Nano synthesis failed: \(message)"
        }
    }
}
