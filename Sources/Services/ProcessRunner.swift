import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunner {
    /// Resolve the user's login shell environment once at startup.
    /// This picks up GH_TOKEN, GITHUB_TOKEN, custom PATH entries, etc.
    /// that aren't available to GUI apps launched by launchd or Spotlight.
    private static let shellEnvironment: [String: String] = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "env"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        var env: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            guard let eqIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eqIndex])
            let value = String(line[line.index(after: eqIndex)...])
            if !key.isEmpty { env[key] = value }
        }
        return env.isEmpty ? ProcessInfo.processInfo.environment : env
    }()

    static func run(executable: String, arguments: [String], environment: [String: String]? = nil) async throws -> ProcessResult {
        let exec = executable
        let args = arguments
        let env = environment
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exec)
            process.arguments = args

            var processEnv = shellEnvironment
            if let env {
                processEnv.merge(env) { _, new in new }
            }
            let existingPath = processEnv["PATH"] ?? "/usr/bin:/bin"
            processEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            process.environment = processEnv

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        }.value
    }

    static func gh(_ arguments: String...) async throws -> ProcessResult {
        try await run(executable: "/usr/bin/env", arguments: ["gh"] + arguments)
    }

    static func ghJSON<T: Decodable & Sendable>(_ type: T.Type, _ arguments: String...) async throws -> T {
        let result = try await run(executable: "/usr/bin/env", arguments: ["gh"] + arguments)
        guard result.exitCode == 0 else {
            throw GHError.commandFailed(result.stderr)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(result.stdout.utf8))
    }
}

enum GHError: Error, Sendable {
    case commandFailed(String)
}
