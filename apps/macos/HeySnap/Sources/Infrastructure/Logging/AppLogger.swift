import Foundation

enum AppLogger {
    private static let subsystem = "HeySnap"

    static var logURL: URL {
        let logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(subsystem, isDirectory: true)
        return logsDirectory.appendingPathComponent("HeySnap.log")
    }

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
        do {
            let directory = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let line = "\(timestamp()) [\(level)] \(message)\n"
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            NSLog("HeySnap log write failed: \(error.localizedDescription)")
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
