import Foundation

enum WandaVersion {
    static let bundleIdentifier = "com.mechaharry.Wanda"

    static var semanticVersion: String {
        bundledString(for: "CFBundleShortVersionString")
            ?? versionFileSemanticVersion()
            ?? "0.0.0"
    }

    static let buildVersion = "1"

    static var aboutApplicationVersion: String {
        semanticVersion
    }

    private static func bundledString(for key: String) -> String? {
        guard Bundle.main.bundleIdentifier == bundleIdentifier else {
            return nil
        }

        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func versionFileSemanticVersion() -> String? {
        candidateVersionFileURLs()
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil }
    }

    private static func candidateVersionFileURLs() -> [URL] {
        var candidates: [URL] = []
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("VERSION"))

        var sourceURL = URL(fileURLWithPath: #filePath)
        while sourceURL.pathComponents.count > 1 {
            sourceURL.deleteLastPathComponent()
            candidates.append(sourceURL.appendingPathComponent("VERSION"))
        }

        return candidates
    }
}
