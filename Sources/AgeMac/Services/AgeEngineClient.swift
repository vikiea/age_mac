/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import Foundation

enum EngineCommand {
    case encryptBatch(outputName: String, compress: Bool)
    case encryptSeparate(compress: Bool)
    case decrypt

    var executableCommand: String {
        switch self {
        case .encryptBatch: "encrypt-batch"
        case .encryptSeparate: "encrypt-separate"
        case .decrypt: "decrypt"
        }
    }
}

struct EngineRequest {
    var command: EngineCommand
    var files: [SelectedFile]
    var outputDirectory: String
    var authArgument: String
    var secret: String
    var duplicateStrategy: DuplicateStrategy
    var concurrency: Int
    var language: AppLanguage
}

enum EngineClientError: LocalizedError {
    case engineMissing(URL)
    case processFailed(String, userMessage: String? = nil)
    case invalidKeygenOutput

    func errorDescription(in language: AppLanguage) -> String {
        switch self {
        case .engineMissing(let url):
            language == .english ? "Cannot find age engine: \(url.path)" : "找不到 age 引擎: \(url.path)"
        case .processFailed(let message, let userMessage): userMessage ?? message
        case .invalidKeygenOutput:
            language == .english ? "Key generation output is invalid" : "密钥生成输出无效"
        }
    }

    var errorDescription: String? {
        errorDescription(in: .english)
    }
}

enum EngineErrorPresenter {
    static func userMessage(for rawMessage: String, command: EngineCommand, language: AppLanguage) -> String {
        let lowercased = rawMessage.lowercased()

        if lowercased.contains("encrypted file is incomplete or corrupted") ||
            lowercased.contains("failed to decrypt and authenticate payload chunk") ||
            lowercased.contains("unexpected eof") ||
            lowercased.contains("trailing data after end of encrypted file") {
            return language == .english
                ? "Decrypt failed: the file is incomplete, corrupted, or the encrypted output was not fully written. Verify the original .age file and try again."
                : "解密失败：文件不完整、已损坏，或加密输出未完整写入。请确认原始 .age 文件完整后重试。"
        }

        if lowercased.contains("no identity matched any of the recipients") ||
            lowercased.contains("incorrect passphrase") ||
            lowercased.contains("bad header mac") {
            return language == .english
                ? "Decrypt failed: the passphrase or private key does not match this file."
                : "解密失败：密码或私钥不匹配，请确认选择的密钥、输入的密码以及文件是否对应。"
        }

        if lowercased.contains("malformed age file") ||
            lowercased.contains("not an age file") ||
            lowercased.contains("invalid armor") {
            return language == .english
                ? "Decrypt failed: this is not a valid age file, or the file content is corrupted."
                : "解密失败：文件不是有效的 age 加密文件，或文件内容已经损坏。"
        }

        if lowercased.contains("permission denied") {
            return language == .english
                ? "Operation failed: there is not enough permission to read input files or write to the output folder."
                : "操作失败：没有足够权限读取输入文件或写入输出目录，请检查文件权限。"
        }

        if lowercased.contains("no such file or directory") || lowercased.contains("file does not exist") {
            return language == .english
                ? "Operation failed: a file does not exist or has been moved. Choose the files again and retry."
                : "操作失败：有文件不存在或已被移动，请重新选择文件后再试。"
        }

        if lowercased.contains("no space left on device") {
            return language == .english
                ? "Operation failed: there is not enough disk space. Free space or choose another output folder."
                : "操作失败：磁盘空间不足，请清理空间或更换输出目录后再试。"
        }

        if lowercased.contains("unsafe archive path") {
            return language == .english
                ? "Decrypt failed: the archive contains an unsafe file path and was blocked."
                : "解密失败：归档中包含不安全的文件路径，已阻止写入。"
        }

        if lowercased.contains("all files failed to encrypt") {
            return language == .english
                ? "Encrypt failed: no files were processed successfully. Check the input files and output folder."
                : "加密失败：所有文件都没有成功处理，请检查输入文件和输出目录。"
        }

        if lowercased.contains("all files failed to decrypt") {
            return language == .english
                ? "Decrypt failed: no files were processed successfully. Check the passphrase, private key, or file format."
                : "解密失败：所有文件都没有成功处理，请检查密码、私钥或文件格式。"
        }

        switch command {
        case .encryptBatch, .encryptSeparate:
            return rawMessage
        case .decrypt:
            return rawMessage
        }
    }
}

final class AgeEngineClient {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var engineURL: URL {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("age-engine"),
           FileManager.default.isExecutableFile(atPath: resourceURL.path) {
            return resourceURL
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return cwd.appendingPathComponent("Engine/age-engine")
    }

    func generateKeyPair(type: AgeKeyType = .recommended, language: AppLanguage) throws -> KeyEntry {
        let engine = engineURL
        guard FileManager.default.isExecutableFile(atPath: engine.path) else {
            throw EngineClientError.engineMissing(engine)
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = engine
        process.arguments = ["keygen", "--type", type.engineValue]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "keygen failed"
            throw EngineClientError.processFailed(message, userMessage: EngineErrorPresenter.userMessage(for: message, command: .decrypt, language: language))
        }
        guard let event = try? decoder.decode(EngineEvent.self, from: data),
              let publicKey = event.publicKey,
              let privateKey = event.privateKey else {
            throw EngineClientError.invalidKeygenOutput
        }
        return KeyEntry(
            id: UUID(),
            name: "\(type.title(in: language)) key \(Date().formatted(date: .numeric, time: .shortened))",
            publicKey: publicKey,
            privateKey: privateKey,
            createdAt: Date()
        )
    }

    func run(
        request: EngineRequest,
        onProcess: @escaping (Process) -> Void,
        onEvent: @escaping (EngineEvent) -> Void
    ) async throws -> EngineResult {
        let engine = engineURL
        guard FileManager.default.isExecutableFile(atPath: engine.path) else {
            throw EngineClientError.engineMissing(engine)
        }

        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        let filesURL = tempDir.appendingPathComponent("files.json")
        let secretURL = tempDir.appendingPathComponent("secret.txt")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let specs = request.files.map { EngineFileSpec(path: $0.path, name: $0.name) }
        try encoder.encode(specs).write(to: filesURL, options: [.atomic])
        try request.secret.data(using: .utf8)?.write(to: secretURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretURL.path)

        var arguments = [
            request.command.executableCommand,
            "--files-json", filesURL.path,
            "--output-dir", request.outputDirectory,
            "--auth", request.authArgument,
            "--secret-file", secretURL.path,
            "--duplicate", request.duplicateStrategy.engineValue,
            "--concurrency", String(min(max(request.concurrency, 1), 12))
        ]
        switch request.command {
        case .encryptBatch(let outputName, let compress):
            arguments += ["--output-name", outputName, "--compress=\(compress ? "true" : "false")"]
        case .encryptSeparate(let compress):
            arguments += ["--compress=\(compress ? "true" : "false")"]
        case .decrypt:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let outputState = EngineOutputState()

            let parseLines: @Sendable (String) -> Void = { text in
                outputState.consume(text) { event in
                    onEvent(event)
                }
            }

            let resumeOnce: @Sendable (Result<EngineResult, Error>) -> Void = { outcome in
                guard outputState.markResumed() else {
                    return
                }

                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil

                switch outcome {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            process.executableURL = engine
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { finished in
                outputState.flush { event in
                    onEvent(event)
                }
                if finished.terminationStatus == 0 {
                    resumeOnce(.success(outputState.snapshot()))
                } else {
                    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stdoutError = outputState.errorSummary()
                    let message: String
                    if !stdoutError.isEmpty {
                        message = stdoutError
                    } else if !stderrText.isEmpty {
                        message = stderrText
                    } else {
                        message = "age engine exited with status \(finished.terminationStatus)"
                    }
                    resumeOnce(.failure(EngineClientError.processFailed(
                        message,
                        userMessage: EngineErrorPresenter.userMessage(for: message, command: request.command, language: request.language)
                    )))
                }
            }

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                parseLines(text)
            }

            do {
                try process.run()
                onProcess(process)
            } catch {
                resumeOnce(.failure(error))
            }
        }
    }
}

private final class EngineOutputState: @unchecked Sendable {
    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private var lineBuffer = ""
    private var outputs = [String]()
    private var errorMessages = [String]()
    private var result = EngineResult(success: 0, fail: 0, outputs: [])
    private var didResume = false

    func consume(_ text: String, onEvent: (EngineEvent) -> Void) {
        let lines: [String]
        lock.lock()
        lineBuffer += text
        let parts = lineBuffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lineBuffer = parts.last ?? ""
        lines = Array(parts.dropLast())
        lock.unlock()

        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(EngineEvent.self, from: data) else {
                continue
            }
            if let output = event.output {
                lock.lock()
                outputs.append(output)
                lock.unlock()
            }
            if event.event == "done" {
                lock.lock()
                result = EngineResult(success: event.success ?? 0, fail: event.fail ?? 0, outputs: event.outputs ?? outputs)
                lock.unlock()
            }
            if event.event == "error", let message = event.message, !message.isEmpty {
                lock.lock()
                errorMessages.append(message)
                lock.unlock()
            }
            onEvent(event)
        }
    }

    func flush(onEvent: (EngineEvent) -> Void) {
        lock.lock()
        let hasBuffer = !lineBuffer.isEmpty
        lock.unlock()
        if hasBuffer {
            consume("\n", onEvent: onEvent)
        }
    }

    func snapshot() -> EngineResult {
        lock.lock()
        defer { lock.unlock() }
        return result.outputs.isEmpty ? EngineResult(success: result.success, fail: result.fail, outputs: outputs) : result
    }

    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }

    func errorSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return errorMessages.joined(separator: "\n")
    }
}
