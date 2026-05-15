import Foundation

enum KeyFileCodec {
    static func parse(_ text: String, fallbackName: String) throws -> KeyEntry {
        guard let key = parseMany(text, fallbackName: fallbackName).first else {
            throw KeyFileCodecError.missingPublicKey
        }
        return key
    }

    static func parseMany(_ text: String, fallbackName: String) -> [KeyEntry] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var entries: [KeyEntry] = []
        var name = fallbackName
        var publicKey = ""
        var privateKey: String?

        func appendCurrent() {
            guard !publicKey.isEmpty else { return }
            entries.append(KeyEntry(
                id: UUID(),
                name: name.isEmpty ? "Imported key" : name,
                publicKey: publicKey,
                privateKey: privateKey,
                createdAt: Date()
            ))
            let nextIndex = entries.count + 1
            name = fallbackName.isEmpty ? "Imported key \(nextIndex)" : "\(fallbackName) \(nextIndex)"
            publicKey = ""
            privateKey = nil
        }

        for line in lines {
            let uncommented = line.hasPrefix("#") ? line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) : line
            if uncommented.hasPrefix("public key:") {
                if !publicKey.isEmpty || privateKey != nil {
                    appendCurrent()
                }
                publicKey = uncommented.dropFirst("public key:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if uncommented.hasPrefix("age1") {
                if !publicKey.isEmpty || privateKey != nil {
                    appendCurrent()
                }
                publicKey = uncommented
            } else if uncommented.hasPrefix("AGE-SECRET-KEY-") {
                privateKey = uncommented
                if publicKey.isEmpty {
                    name = fallbackName.isEmpty ? "Imported private key" : fallbackName
                } else {
                    appendCurrent()
                }
            } else if uncommented.lowercased().hasPrefix("name:") {
                let value = uncommented.dropFirst("name:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    name = value
                }
            }
        }

        appendCurrent()
        return entries
    }

    static func exportText(for key: KeyEntry) -> String {
        var lines = [
            "# created: \(ISO8601DateFormatter().string(from: key.createdAt))",
            "# public key: \(key.publicKey)"
        ]
        if let privateKey = key.privateKey, !privateKey.isEmpty {
            lines.append(privateKey)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum KeyFileCodecError: LocalizedError {
    case missingPublicKey

    var errorDescription: String? {
        switch self {
        case .missingPublicKey: "密钥文件中没有找到 age 公钥"
        }
    }
}
