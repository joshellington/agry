import Foundation

/// Runs a long-lived subprocess and delivers its stdout one line at a time on
/// the main queue, in order.
final class LineProcess: @unchecked Sendable {
    private let process = Process()
    private var buffer = Data()

    /// Called on the main queue for every complete stdout line.
    var onLine: (@MainActor (String) -> Void)?
    /// Called on the main queue when the process exits.
    var onExit: (@MainActor (Int32) -> Void)?

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
    }

    func start() throws {
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            self.consume(chunk)
        }
        process.terminationHandler = { [weak self] process in
            stdout.fileHandleForReading.readabilityHandler = nil
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onExit?(status) }
            }
        }
        try process.run()
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    // Only touched from the pipe's serial readability handler.
    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onLine?(line) }
            }
        }
    }
}
