import Foundation

/// Only disposable compiler artifacts and Finder metadata are eligible.
enum JarvisKnowledgeRunMaintenance {
    struct Removed: Codable {
        let files: Int
        let bytes: Int
    }

    static func clean(runDirectory: URL, runsRoot: URL) throws -> Removed {
        let fm = FileManager.default
        let root = runsRoot.standardizedFileURL.resolvingSymlinksInPath()
        let run = runDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard run.path == runDirectory.standardizedFileURL.path,
              run.deletingLastPathComponent().path == root.path,
              run.lastPathComponent.range(of: #"^K[0-9]{2}-[0-9]{2}-[0-9a-fA-F-]{36}$"#, options: .regularExpression) != nil
        else { throw CocoaError(.fileWriteInvalidFileName) }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var targets: [URL] = []
        var count = 0
        var bytes = 0
        let children = try fm.contentsOfDirectory(at: run, includingPropertiesForKeys: Array(keys))
        for target in children where [".swift-module-cache", ".DS_Store"].contains(target.lastPathComponent) {
            let info = try target.resourceValues(forKeys: keys)
            guard info.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
            if target.lastPathComponent == ".DS_Store" {
                guard info.isRegularFile == true else { throw CocoaError(.fileReadCorruptFile) }
                count += 1
                bytes += info.fileSize ?? 0
            } else {
                guard info.isDirectory == true else { throw CocoaError(.fileReadCorruptFile) }
                var enumerationError: Error?
                guard let entries = fm.enumerator(at: target, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, error in
                    enumerationError = error
                    return false
                }) else { throw CocoaError(.fileReadCorruptFile) }
                for case let entry as URL in entries {
                    let v = try entry.resourceValues(forKeys: keys)
                    guard v.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
                    if v.isDirectory == true { continue }
                    guard v.isRegularFile == true,
                          ["pcm", "swiftmodule", "timestamp"].contains(entry.pathExtension) || entry.lastPathComponent == ".DS_Store"
                    else { throw CocoaError(.fileReadCorruptFile) }
                    count += 1
                    bytes += v.fileSize ?? 0
                }
                if let enumerationError { throw enumerationError }
            }
            targets.append(target)
        }
        // Inspect all candidates before removing anything. Never traverse
        // reference, generated, source images, manuscripts or CMS receipts.
        for target in targets { try fm.removeItem(at: target) }
        return Removed(files: count, bytes: bytes)
    }
}
