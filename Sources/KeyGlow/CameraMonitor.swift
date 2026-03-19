import Foundation

final class CameraMonitor {
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
                    if line.contains("Start Stream") {
                        DispatchQueue.main.async { self?.onChange(true) }
                    } else if line.contains("Stop Stream") {
                        DispatchQueue.main.async { self?.onChange(false) }
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
