import Foundation

final class CameraMonitor {
    enum Event {
        case streamStarted
        case streamStopped
    }

    static func classify(_ line: String) -> Event? {
        if line.contains("Start Stream") { return .streamStarted }
        if line.contains("Stop Stream") { return .streamStopped }
        return nil
    }

    private var process: Process?
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--predicate",
            #"subsystem == "com.apple.UVCExtension" AND category == "device""#,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        self.process = process

        DispatchQueue.global(qos: .background).async { [weak self] in
            do {
                try process.run()
            } catch {
                print("[KeyGlow] Failed to start log stream: \(error)")
                return
            }

            let handle = pipe.fileHandleForReading
            while process.isRunning {
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { continue }

                for line in output.components(separatedBy: "\n") {
                    switch CameraMonitor.classify(line) {
                    case .streamStarted:
                        DispatchQueue.main.async { self?.onChange(true) }
                    case .streamStopped:
                        DispatchQueue.main.async { self?.onChange(false) }
                    case .none:
                        break
                    }
                }
            }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
