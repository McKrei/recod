//
//  Logger.swift
//  Recod
//
//  Created for OpenCode.
//

import Foundation
import AppKit

public enum LogLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case debug = "DEBUG"
}

/// A simple file-based logger actor for thread-safe writing.
public actor FileLogger {
    public static let shared = FileLogger()
    
    private let fileManager = FileManager.default
    private var logFileURL: URL?
    
    private init() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("Failed to find Application Support directory")
            return
        }
        
        let appDirectory = appSupportURL.appendingPathComponent("Recod")
        let logsDirectory = appDirectory.appendingPathComponent("Logs")
        
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let url = logsDirectory.appendingPathComponent("app.log")
            self.logFileURL = url
            
            // Create file if not exists
            if !FileManager.default.fileExists(atPath: url.path) {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
            
            print("Logging to: \(url.path)")
        } catch {
            print("Failed to setup log file: \(error)")
        }
    }
    
    public func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) -> \(message)\n"
        
        print(logMessage, terminator: "") // Also print to console
        
        guard let fileURL = logFileURL else { return }
        
        if let data = logMessage.data(using: .utf8) {
            do {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } catch {
                // If handle fails (maybe file deleted), try to recreate or write directly
                try? logMessage.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    public func getLogFileURL() -> URL? {
        return logFileURL
    }
    
    public func revealLogsInFinder() {
        guard let url = logFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// Global helper for easier access
public func Log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
    Task {
        await FileLogger.shared.log(message, level: level, file: file, function: function, line: line)
    }
}
