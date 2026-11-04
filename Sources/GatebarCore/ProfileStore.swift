import Foundation

public struct ProfileStoreError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public final class ProfileStore {
    public let fileURL: URL

    public init(fileURL: URL = Paths.profiles) {
        self.fileURL = fileURL
    }

    public func load() throws -> [Profile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [] }
        do {
            return try JSONDecoder().decode([Profile].self, from: data)
        } catch {
            throw ProfileStoreError(message: L.t(
                "Could not read \(fileURL.path): \(Self.describe(error))",
                "No pude leer \(fileURL.path): \(Self.describe(error))"))
        }
    }

    public func save(_ profiles: [Profile]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(profiles)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func ensureFileExists() throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) { try save([]) }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "missing \"\(key.stringValue)\" at \(path(context))"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            return "\(context.debugDescription) at \(path(context))"
        case DecodingError.dataCorrupted(let context):
            return context.debugDescription
        default:
            return error.localizedDescription
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let parts = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
        return parts.isEmpty ? "root" : parts.joined(separator: ".")
    }
}
