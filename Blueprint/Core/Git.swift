import Foundation

/// Read-only git commands. Architecture Dissector never writes to a tracked repo, not even its refs.
enum Git {
  static func run(_ arguments: [String], in folder: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = folder
    process.environment = ProcessInfo.processInfo.environment.merging(["GIT_OPTIONAL_LOCKS": "0", "LC_ALL": "C"]) { $1 }
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  static func isRepo(_ folder: URL) -> Bool {
    run(["rev-parse", "--is-inside-work-tree"], in: folder)?.hasPrefix("true") == true
  }

  static func head(_ folder: URL) -> String? {
    run(["rev-parse", "--short", "HEAD"], in: folder)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func tagAtHead(_ folder: URL) -> String? {
    run(["describe", "--tags", "--exact-match", "HEAD"], in: folder)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func commits(since commit: String, in folder: URL) -> Int? {
    run(["rev-list", "--count", "\(commit)..HEAD"], in: folder).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
  }

  /// The content hash of every file in the folder that git doesn't ignore, by path relative to the folder.
  /// Comparing two manifests tells which files changed, whether or not they were committed.
  static func manifest(_ folder: URL) -> [String: String]? {
    guard let staged = run(["ls-files", "-s", "-z"], in: folder) else { return nil }
    var files: [String: String] = [:]
    for entry in staged.split(separator: "\0") {
      guard let tab = entry.firstIndex(of: "\t") else { continue }
      let fields = entry[..<tab].split(separator: " ")
      guard fields.count >= 2 else { continue }
      files[String(entry[entry.index(after: tab)...])] = String(fields[1])
    }

    let deleted = Set(list(["ls-files", "-d", "-z"], in: folder))
    for path in deleted { files[path] = nil }

    let dirty = list(["ls-files", "-m", "-z"], in: folder).filter { !deleted.contains($0) }
    let untracked = list(["ls-files", "-o", "--exclude-standard", "-z"], in: folder)
    let toHash = Array(Set(dirty + untracked)).sorted()
    for start in stride(from: 0, to: toHash.count, by: 400) {
      let chunk = Array(toHash[start..<min(start + 400, toHash.count)])
      guard let output = run(["hash-object", "--"] + chunk, in: folder) else { continue }
      let hashes = output.split(separator: "\n")
      for (path, hash) in zip(chunk, hashes) { files[path] = String(hash) }
    }
    return files
  }

  private static func list(_ arguments: [String], in folder: URL) -> [String] {
    (run(arguments, in: folder) ?? "").split(separator: "\0").map(String.init)
  }
}
