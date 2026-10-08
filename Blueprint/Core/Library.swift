import Foundation

/// Where Architecture Dissector keeps its data. `BLUEPRINT_HOME` points it somewhere else, for tests and screenshots.
///
///     apps/<id>/app.json          the tracked folder
///     apps/<id>/current.json      the current architecture
///     apps/<id>/manifest.json     file hashes when the current architecture was saved
///     apps/<id>/versions/*.json   saved versions, like 1.2.0.json
enum Paths {
  static var home: URL {
    if let custom = ProcessInfo.processInfo.environment["BLUEPRINT_HOME"], !custom.isEmpty {
      return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
    }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appending(path: "Blueprint")
  }

  static var apps: URL { home.appending(path: "apps") }
  static func folder(_ id: String) -> URL { apps.appending(path: id) }
}

enum Library {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  // MARK: Reading

  static func apps() -> [TrackedApp] {
    let folders = (try? FileManager.default.contentsOfDirectory(at: Paths.apps, includingPropertiesForKeys: nil)) ?? []
    return folders
      .compactMap { read(TrackedApp.self, from: $0.appending(path: "app.json")) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  static func current(_ id: String) -> Snapshot? {
    read(Snapshot.self, from: Paths.folder(id).appending(path: "current.json"))
  }

  static func manifest(_ id: String) -> [String: String]? {
    read([String: String].self, from: Paths.folder(id).appending(path: "manifest.json"))
  }

  /// Saved versions, oldest first.
  static func versions(_ id: String) -> [Snapshot] {
    let folder = Paths.folder(id).appending(path: "versions")
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return files
      .filter { $0.pathExtension == "json" }
      .compactMap { read(Snapshot.self, from: $0) }
      .sorted { compareVersions($0.version ?? "", $1.version ?? "") }
  }

  static func version(_ name: String, of id: String) -> Snapshot? {
    read(Snapshot.self, from: versionFile(normalizeVersion(name), of: id))
  }

  // MARK: Writing

  static func add(_ folder: URL) throws -> TrackedApp {
    let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw BlueprintError("\(folder.path) isn't a folder.")
    }
    let existing = apps()
    if let app = existing.first(where: { $0.path == folder.path }) {
      throw BlueprintError("\(app.name) is already tracked, as \(app.id).")
    }

    let base = slug(folder.lastPathComponent)
    var id = base
    var counter = 2
    while existing.contains(where: { $0.id == id }) || FileManager.default.fileExists(atPath: Paths.folder(id).path) {
      id = "\(base)-\(counter)"
      counter += 1
    }

    let app = TrackedApp(id: id, name: displayName(of: folder), path: folder.path, addedAt: .now)
    try write(app, to: Paths.folder(id).appending(path: "app.json"))
    return app
  }

  /// Moves the app's Architecture Dissector data, not the app, to the Trash.
  static func remove(_ app: TrackedApp) throws {
    try FileManager.default.trashItem(at: Paths.folder(app.id), resultingItemURL: nil)
  }

  /// Saves the current architecture, with the commit and file hashes it describes.
  @discardableResult
  static func save(_ architecture: Architecture, for app: TrackedApp) throws -> Snapshot {
    let snapshot = Snapshot(version: nil, savedAt: .now, commit: Git.head(app.url), architecture: architecture)
    let folder = Paths.folder(app.id)
    try write(snapshot, to: folder.appending(path: "current.json"))
    if let manifest = Git.manifest(app.url) {
      try write(manifest, to: folder.appending(path: "manifest.json"))
    }
    return snapshot
  }

  /// Saves a copy of the current architecture as a version.
  @discardableResult
  static func saveVersion(_ name: String, for app: TrackedApp) throws -> Snapshot {
    let name = try validVersion(name)
    guard var snapshot = current(app.id) else {
      throw BlueprintError("\(app.name) has no architecture yet, so there's nothing to save as \(name).")
    }
    snapshot.version = name
    try write(snapshot, to: versionFile(name, of: app.id))
    return snapshot
  }

  /// Saves an architecture as a version that already shipped, without touching the current one.
  /// The commit comes from the version's git tag, like v1.0.0 or 1.0.0, when there is one,
  /// or else from the version it replaces.
  @discardableResult
  static func savePastVersion(_ architecture: Architecture, as name: String, for app: TrackedApp) throws -> Snapshot {
    let name = try validVersion(name)
    let commit = ["v\(name)", name].lazy.compactMap { tag in
      Git.run(["rev-parse", "--short", "\(tag)^{commit}"], in: app.url)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.first ?? version(name, of: app.id)?.commit
    let snapshot = Snapshot(version: name, savedAt: .now, commit: commit, architecture: architecture)
    try write(snapshot, to: versionFile(name, of: app.id))
    return snapshot
  }

  static func validVersion(_ name: String) throws -> String {
    let name = normalizeVersion(name)
    guard name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
      throw BlueprintError("\(name) can't be a version name. Use letters, numbers, dots and dashes, like 1.2.0.")
    }
    return name
  }

  static func removeVersion(_ name: String, of app: TrackedApp) throws {
    let file = versionFile(normalizeVersion(name), of: app.id)
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw BlueprintError("\(app.name) has no version \(name).")
    }
    try FileManager.default.trashItem(at: file, resultingItemURL: nil)
  }

  // MARK: Finding apps

  /// Finds a tracked app by id, name or folder. Without a query, it's the app that contains `cwd`.
  static func resolve(_ query: String?, cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> TrackedApp {
    let apps = apps()
    guard let query else {
      if let app = containing(cwd.standardizedFileURL.resolvingSymlinksInPath(), in: apps) { return app }
      throw BlueprintError("This folder isn't inside an app Architecture Dissector tracks. Add it with: blueprint add .")
    }

    let lowered = query.lowercased()
    if let app = apps.first(where: { $0.id == lowered }) ?? apps.first(where: { $0.name.lowercased() == lowered }) {
      return app
    }
    let path = URL(fileURLWithPath: (query as NSString).expandingTildeInPath, relativeTo: cwd).standardizedFileURL.resolvingSymlinksInPath()
    if let app = containing(path, in: apps) { return app }
    throw BlueprintError("Architecture Dissector doesn't track \(query). Run blueprint list to see the apps it tracks.")
  }

  private static func containing(_ folder: URL, in apps: [TrackedApp]) -> TrackedApp? {
    apps
      .filter { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") }
      .max { $0.path.count < $1.path.count }
  }

  // MARK: Helpers

  static func normalizeVersion(_ name: String) -> String {
    let name = name.trimmingCharacters(in: .whitespaces)
    if name.count > 1, name.first == "v" || name.first == "V", name.dropFirst().first?.isNumber == true {
      return String(name.dropFirst())
    }
    return name
  }

  /// True when `a` comes before `b`, so 1.9.0 comes before 1.10.0.
  static func compareVersions(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
  }

  static func slug(_ text: String) -> String {
    let parts = text.lowercased().split { !$0.isLetter && !$0.isNumber }
    let slug = parts.joined(separator: "-")
    return slug.isEmpty ? "app" : slug
  }

  /// The app's name from project.yml or package.json, or the folder's name.
  static func displayName(of folder: URL) -> String {
    if let yml = try? String(contentsOf: folder.appending(path: "project.yml"), encoding: .utf8),
       let line = yml.split(separator: "\n").first(where: { $0.hasPrefix("name:") }) {
      let name = line.dropFirst(5).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'")))
      if !name.isEmpty { return name }
    }
    if let data = try? Data(contentsOf: folder.appending(path: "package.json")),
       let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let name = (package["productName"] ?? package["name"]) as? String, !name.isEmpty {
      return name
    }
    return folder.lastPathComponent
      .split { $0 == "-" || $0 == "_" }
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
  }

  private static func versionFile(_ name: String, of id: String) -> URL {
    Paths.folder(id).appending(path: "versions/\(name).json")
  }

  static func read<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
    guard let data = try? Data(contentsOf: file) else { return nil }
    return try? decoder.decode(type, from: data)
  }

  static func write<T: Encodable>(_ value: T, to file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(value).write(to: file, options: .atomic)
  }
}
