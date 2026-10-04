import Foundation

struct SuggestedProject: Identifiable, Sendable {
  var url: URL
  var name: String
  var updated: Date

  var id: String { url.path }
}

/// The git repositories you worked on most recently, in the usual projects folders,
/// so the welcome screen can track one with a click.
enum ProjectFinder {
  static let roots = ["dev", "Developer", "Projects", "code", "repos", "src", "GitHub", "Sites"]

  static func recent(excluding tracked: Set<String>, limit: Int = 6) -> (folder: String?, projects: [SuggestedProject]) {
    let fm = FileManager.default
    let home = ProcessInfo.processInfo.environment["BLUEPRINT_PROJECTS_HOME"].map { URL(fileURLWithPath: $0) } ?? fm.homeDirectoryForCurrentUser
    var seen = Set<String>()
    var found: [(url: URL, root: String, updated: Date)] = []

    for root in roots {
      let folder = home.appending(path: root)
      guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
      for child in children {
        let path = child.standardizedFileURL.resolvingSymlinksInPath().path
        let git = child.appending(path: ".git")
        guard fm.fileExists(atPath: git.path), !tracked.contains(path), seen.insert(path).inserted else { continue }
        // Git touches these on commits, checkouts and staging, so they tell when you last worked there.
        let dates = ["", "index", "HEAD", "logs/HEAD", "FETCH_HEAD"].compactMap { file in
          try? fm.attributesOfItem(atPath: git.appending(path: file).path)[.modificationDate] as? Date
        }
        guard let updated = dates.max() else { continue }
        found.append((URL(fileURLWithPath: path), root, updated))
      }
    }

    let recent = found.sorted { $0.updated > $1.updated }.prefix(limit)
    let roots = Set(recent.map(\.root))
    return (
      roots.count == 1 ? roots.first.map { "~/\($0)" } : nil,
      recent.map { SuggestedProject(url: $0.url, name: Library.displayName(of: $0.url), updated: $0.updated) }
    )
  }
}
