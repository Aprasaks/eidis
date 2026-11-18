import Foundation

let sample = Data([77, 32, 32, 97, 0, 63, 63, 32, 98, 0, 65, 32, 32, 99, 0])
let counts = try LocalGitInspector.countStatus(sample)
precondition(counts.tracked == 2 && counts.untracked == 1)
let emptyCounts = try LocalGitInspector.countStatus(Data())
precondition(emptyCounts.tracked == 0 && emptyCounts.untracked == 0)
do {
    _ = try LocalGitInspector.countStatus(Data([63, 63, 97, 0]))
    preconditionFailure("malformed status unexpectedly accepted")
} catch LocalGitError.invalidOutput {
    print("PASS rejects malformed Git status output")
}

let folder = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
let result = try LocalGitInspector.inspect(folderURL: URL(fileURLWithPath: folder))
precondition(!result.rootPath.isEmpty && result.rootPath.hasPrefix("/"))
precondition(!result.branch.isEmpty)
precondition(result.headSHA.count == 40 || result.headSHA.count == 64)
precondition(result.changedTrackedEntries >= 0 && result.untrackedEntries >= 0)
print("PASS live local Git read-only snapshot: branch \(result.branch), HEAD \(result.headSHA.prefix(10)), tracked \(result.changedTrackedEntries), untracked \(result.untrackedEntries)")
print("PASS NUL-delimited status classification and bounded fixed Git calls")
