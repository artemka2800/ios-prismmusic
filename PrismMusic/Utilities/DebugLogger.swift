import Foundation

final class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()
    
    private let logPath: String
    
    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.logPath = dir.appendingPathComponent("debug_console.log").path
        
        // Truncate if too big (> 1MB)
        if let attr = try? FileManager.default.attributesOfItem(atPath: logPath),
           let size = attr[.size] as? UInt64, size > 1_000_000 {
            try? FileManager.default.removeItem(atPath: logPath)
        }
    }
    
    func start() {
        // Redirect stderr and stdout to our file so we capture print() and internal logs
        freopen(logPath, "a+", stderr)
        freopen(logPath, "a+", stdout)
        
        // Disable buffering so logs are written immediately, preventing loss on crash
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        
        print("--- Debug Logger Started ---")
    }
    
    func readLogs() -> String {
        (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "Log is empty or unreadable."
    }
    
    func clearLogs() {
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}
