import Foundation
import UIKit

/**
 * Enable it either by calling DebugNetworkLogger.setEnabled(true) or from the debug menu in the app
 * - Share or delete the log file from Application Logs debug menu
 * - Change the config from from Application Logs debug menu
*/
final class DebugNetworkLogger: URLProtocol {
    
    /// Defines the level of detail for console logging
    enum LogLevel: String {
        /// Only log request URLs and status codes
        case minimal
        /// Log full request and response details
        case verbose
        /// Only log at a file
        case onlyToLogFile
    }
    
    // MARK: - Properties
    
    static var isEnabled: Bool = false
    
    private static let logDirectoryPath = Directories.libraryDirectory() + "/logs/"
    private static let logDirectoryURL = URL(fileURLWithPath: logDirectoryPath)
    private static let logFileURL = logDirectoryURL.appendingPathComponent("network.log")
    
    private static var fileHandle: FileHandle?
    private static var hasCheckedSize: Bool = false
    private static var handledKey = "NetworkLoggerHandled"
    
    private let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.protocolClasses = nil
        return URLSession(configuration: config)
    }()
    
    // MARK: - URLProtocol
    override class func canInit(with request: URLRequest) -> Bool {
        if URLProtocol.property(forKey: Self.handledKey, in: request) != nil {
            return false
        }
        
        // Check if we should filter this endpoint
        if filteredEndpoints.count > 0, let url = request.url?.absoluteString {
            let shouldInclude = filteredEndpoints.contains { endpoint in
                url.contains(endpoint)
            }
            return isEnabled && shouldInclude
        }
        
        return isEnabled
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        let startTime = Date()
        
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        
        // Mark this request as being handled to avoid infinite loops
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        let task = sharedSession.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            if let error = error {
                self.logEvent("❌ NETWORK ERROR: \(request.url?.absoluteString ?? "Unknown URL") - \(error.localizedDescription)")
                self.logEvent("⏱️ TIME: \(String(format: "%.2f", elapsedTime))s")
                
                self.client?.urlProtocol(self, didFailWithError: error)
                
            } else if let response {
                self.logResponse(request: request, response: response, data: data, elapsedTime: elapsedTime)
                
                // Forward the response back to the original client
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
                
                if let data = data {
                    self.client?.urlProtocol(self, didLoad: data)
                }
                
                self.client?.urlProtocolDidFinishLoading(self)
            } else {
                let error = NSError(domain: "DebugNetworkLogger", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
        
        task.resume()
    }
    
    override func stopLoading() {}
}

// MARK: - File Logging

private extension DebugNetworkLogger {
    
    func logEvent(_ message: String, withDate: Bool = false) {
        Self.writeToLogFile(message, withDate: withDate)
        
        if Self.logLevel == .verbose {
            logToConsole(message)
        }
    }
    
    static func writeToLogFile(_ message: String, withDate: Bool = false) {
        guard let fileHandle = fileHandle, !logOnlyToConsole else { return }
        
        let timestamp = Date.fullDateFormatter.string(from: Date())
        let logMessage = withDate ? "[\(timestamp)] \(message)\n" : "\(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }
        
        Self.showSizeWarningIfNeeded()
    }
    
    static func showSizeWarningIfNeeded() {
        guard !Self.hasCheckedSize else { return }
        Self.hasCheckedSize = true
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 10.0) {
            let (stringSize, size) = Self.fileSize(at: logFileURL)
            if let stringSize, size >= 200 * 1024 * 1024 {
                print("[NetworkLogger] Network file size: \(stringSize) - consider deleting it")
            }
        }
    }
    
    func logToConsole(_ message: String, isError: Bool = false, statusCode: Int? = nil) {
        switch Self.logLevel {
        case .minimal:
            let icon = (isError || ((statusCode ?? 0) >= 400)) ? "🔴" : "🔵"
            print("[NetworkLogger] \(icon) \(message)")
        case .verbose:
            print("[NetworkLogger] \(message)")
        case .onlyToLogFile:
            return
        }
    }
    
    func logResponse(request: URLRequest, response: URLResponse, data: Data?, elapsedTime: TimeInterval) {
        let urlString = request.url?.absoluteString ?? "Unknown URL"
        let method = request.httpMethod ?? "Unknown Method"
        
        // Always log to file with full details
        logEvent("\n============ NETWORK REQUEST ============", withDate: true)
        logEvent("🌐 \(method) \(urlString)")
        
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            logEvent("📤 REQUEST HEADERS:")
            headers.forEach { logEvent("   \($0.key): \($0.value)") }
        }
        
        if let httpBody = request.httpBody, let bodyString = String(data: httpBody, encoding: .utf8) {
            logEvent("📤 REQUEST BODY:")
            logEvent(bodyString)
        } else if let httpBodyStream = request.httpBodyStream {
            logEvent("📤 REQUEST BODY:")
            logEvent(prettyPrintHTTPBodyStream(httpBodyStream))
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            let statusEmoji = statusCodeEmoji(for: httpResponse.statusCode)
            logEvent("\(statusEmoji) STATUS: \(httpResponse.statusCode)")
            
            if Self.logLevel == .minimal {
                logToConsole("[\(httpResponse.statusCode)] → \(method) \(urlString) - ⏱️ (\(String(format: "%.2f", elapsedTime))s)",
                             statusCode: httpResponse.statusCode)
            }
            
            if !httpResponse.allHeaderFields.isEmpty {
                logEvent("📥 RESPONSE HEADERS:")
                httpResponse.allHeaderFields.forEach { logEvent("   \($0.key): \($0.value)") }
            }
        }
        
        logEvent("⏱️ TIME: \(String(format: "%.2f", elapsedTime))s")
        
        if let data = data {
            if let jsonString = prettyPrintedJSON(data: data) {
                logEvent("📥 RESPONSE JSON:")
                logEvent(jsonString)
            } else if let stringData = String(data: data, encoding: .utf8) {
                logEvent("📥 RESPONSE DATA:")
                logEvent(stringData)
            } else {
                logEvent("📥 RESPONSE: [Binary data of \(data.count) bytes]")
            }
        } else {
            logEvent("📥 RESPONSE: [No data]")
        }
        
        logEvent("========================================\n")
    }
}

extension DebugNetworkLogger {
    
    static func setEnabled(_ enable: Bool = true) {
        guard Self.isEnabled != enable else { return }

        if !isEnabled {
            if deleteFileOnStartup {
                Self.deleteFile() { _ in
                    register()
                }
            } else {
                register()
            }
        } else {
            URLProtocol.unregisterClass(DebugNetworkLogger.self)
        }
        
        isEnabled = enable
        writeToLogFile("Network logging \(enable ? "enabled" : "disabled")")
    }
    
    static private func register() {
        setupLogFile()
        
        URLProtocol.registerClass(DebugNetworkLogger.self)
        
        let message = "[NetworkLogger] registered successfully"
        print(message)
        writeToLogFile(message)
        
        print("🔍 Network log file path: \(logFileURL.path)")
        print("🖥️ View real-time logs when running on a simulator with: tail -f \"\(logFileURL.path)\"")
        
        if filteredEndpoints.count > 0 {
            let filterMessage = "Filtering enabled for endpoints: \(filteredEndpoints)"
            print(filterMessage)
            writeToLogFile(filterMessage)
        }
    }
    
    static func setupLogFile() {
        do {
            try FileManager.default.createDirectory(atPath: logDirectoryPath, withIntermediateDirectories: true)
        } catch {
            print("[NetworkLogger] Error creating log directory: \(error)")
            return
        }
        
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        
        do {
            fileHandle = try FileHandle(forWritingTo: logFileURL)
            fileHandle?.seekToEndOfFile()
            
            let header = "📱 [NetworkLogger] Started at \(Date.fullDateFormatter.string(from: Date()))\n"
            fileHandle?.write(header.data(using: .utf8)!)
            
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                   object: nil, queue: nil) { _ in
                fileHandle?.synchronizeFile()
            }
        } catch {
            print("[NetworkLogger] Error opening log file: \(error)")
        }
    }
    
    public static func reloadSettings() {
        logLevel = {
            let level = userDefaults.string(forKey: logLevelKey) ?? "minimal"
            return LogLevel(rawValue: level) ?? .minimal
        }()
        logOnlyToConsole = userDefaults.bool(forKey: logOnlyToConsoleKey)
        filteredEndpoints = {
            let endpoints = userDefaults.string(forKey: filteredEndpointsKey)?.components(separatedBy: ",").filter{!$0.isEmpty}
            return endpoints ?? []
        }()
        deleteFileOnStartup = userDefaults.bool(forKey: deteleOnStartupKey)
    }
    
    static func closeLogFile() {
        fileHandle?.synchronizeFile()
        fileHandle?.closeFile()
    }
}

// MARK: - Helpers

extension DebugNetworkLogger {
        
    static func getLogFileAndSize() -> (URL?, String?) {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: Self.logDirectoryURL, includingPropertiesForKeys: nil)
            if let fileURL = fileURLs.filter({ $0.pathExtension == "log" }).first {
                return (fileURL, Self.fileSize(at: fileURL).0)
            }
            
        } catch {
            print("[NetworkLogger] Error listing log file: \(error)")
        }
        
        return (nil, nil)
    }
    
    static func fileSize(at url: URL) -> (String?, size: Int64) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return (Self.formatFileSize(fileSize), fileSize)
            }
        } catch {
            print("Error getting file size: \(error)")
        }
        return (nil, 0)
    }
    
    static func deleteFile(completion: @escaping (Bool) -> Void) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.logFileURL.path) {
            do {
                try fileManager.removeItem(at: Self.logFileURL)
                print("Network log file deleted successfully.")
                completion(true)
            } catch {
                print("Error deleting network log file: \(error)")
                completion(false)
            }
        } else {
            print("File does not exist.")
            completion(false)
        }
    }
    
    static func formatFileSize(_ size: Int64) -> String {
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB]
        byteFormatter.countStyle = .file
        return byteFormatter.string(fromByteCount: size)
    }
    
    func prettyPrintedJSON(data: Data) -> String? {
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    func statusCodeEmoji(for statusCode: Int) -> String {
        switch statusCode {
        case 200..<300:
            return "✅"
        case 300..<400:
            return "↪️"
        case 400..<500:
            return "⚠️"
        case 500..<600:
            return "❌"
        default:
            return "❓"
        }
    }
    
    func prettyPrintHTTPBodyStream(_ httpBodyStream: InputStream) -> String {
        httpBodyStream.open()
        defer { httpBodyStream.close() }
        
        let bufferSize = 1024
        var data = Data()
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        while httpBodyStream.hasBytesAvailable {
            let bytesRead = httpBodyStream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                return "Error reading HTTP Body Stream"
            }
            data.append(buffer, count: bytesRead)
        }
        
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyJsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let prettyPrintedString = String(data: prettyJsonData, encoding: .utf8) {
            return "\(prettyPrintedString)\n"
        } else if let bodyString = String(data: data, encoding: .utf8) {
            return "\(bodyString)\n"
        }
        
        return "HTTP Body Stream could not be decoded."
    }
}

// MARK: -  Config

extension DebugNetworkLogger {
    
    private static let userDefaults = UserDefaults.standard
    
    static let logLevelKey = "network_log_level"
    static let logOnlyToConsoleKey = "network_log_console_only"
    static let deteleOnStartupKey = "network_log_delete_on_startup"
    static let filteredEndpointsKey = "network_log_filtered_endpoints"
    
    private static var logLevel: LogLevel = {
        let level = userDefaults.string(forKey: logLevelKey) ?? "minimal"
        return LogLevel(rawValue: level) ?? .minimal
    }()
    
    private static var logOnlyToConsole: Bool = {
        userDefaults.bool(forKey: logOnlyToConsoleKey)
    }()
    
    private static var filteredEndpoints: [String] = {
        let endpoints = userDefaults.string(forKey: filteredEndpointsKey)?.components(separatedBy: ",").filter{!$0.isEmpty}
        return endpoints ?? []
    }()
    
    private static var deleteFileOnStartup: Bool = {
        userDefaults.bool(forKey: deteleOnStartupKey)
    }()
}
