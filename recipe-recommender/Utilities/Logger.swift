import Foundation

class Logger {
    static let shared = Logger()
    
    private init() {}
    
    enum LogLevel: String {
        case info = "ℹ️ INFO"
        case debug = "🔍 DEBUG"
        case warning = "⚠️ WARNING"
        case error = "🔴 ERROR"
        case critical = "‼️ CRITICAL"
    }
    
    var fullLog: [String] = []
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line) \(function)] \(message)"
        
        print(logMessage)
        fullLog.append(logMessage)
    }
    
    func getFullLog() -> String {
        return fullLog.joined(separator: "\n")
    }
}