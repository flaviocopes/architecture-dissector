import Foundation

/// How the code changed since an agent last saved the app's architecture.
struct AppStatus: Equatable, Sendable {
  var isRepo = false
  var hasManifest = false
  /// Changed, added and deleted files since the last save, minus docs and images.
  var changedFiles: [String] = []
  /// Components with a changed file in their paths.
  var touched: Set<String> = []
  /// Changed files outside every component's paths.
  var uncovered: [String] = []
  var commitsSince: Int?

  var isStale: Bool { !changedFiles.isEmpty }

  static func check(_ app: TrackedApp, current: Snapshot?, manifest saved: [String: String]?) -> AppStatus {
    var status = AppStatus()
    status.isRepo = Git.isRepo(app.url)
    guard status.isRepo, let current else { return status }
    if let commit = current.commit {
      status.commitsSince = Git.commits(since: commit, in: app.url)
    }
    guard let saved, let now = Git.manifest(app.url) else { return status }
    status.hasManifest = true

    let paths = Set(saved.keys).union(now.keys)
    status.changedFiles = paths.filter { saved[$0] != now[$0] && isRelevant($0) }.sorted()
    let nodes = current.architecture.nodes
    for file in status.changedFiles {
      let owners = nodes.filter { $0.covers(file) }
      if owners.isEmpty {
        status.uncovered.append(file)
      } else {
        status.touched.formUnion(owners.map(\.id))
      }
    }
    return status
  }

  private static let ignoredExtensions: Set<String> = [
    "md", "markdown", "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "icns", "mp4", "mov", "pdf",
  ]

  /// Docs, images and licenses rarely change an architecture, so they don't make it stale.
  static func isRelevant(_ file: String) -> Bool {
    let name = (file as NSString).lastPathComponent
    if ignoredExtensions.contains((name as NSString).pathExtension.lowercased()) { return false }
    if name.hasPrefix("LICENSE") || name == ".gitignore" || name == ".DS_Store" { return false }
    if file.hasPrefix("docs/") || file.contains(".xcassets/") || file.contains(".icon/") { return false }
    return true
  }
}
