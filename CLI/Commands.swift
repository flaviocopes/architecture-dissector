import Foundation

enum Commands {
  static let bold = Terminal.bold
  static let dim = Terminal.dim

  // MARK: list

  static let missable = ["architecture", "walkthrough", "overview", "notes", "flows", "data", "explainers"]

  static func list(_ args: Arguments) throws {
    try args.check(allowed: ["json", "missing"])
    let wanted = args.option("missing")
    if let wanted, !missable.contains(wanted) {
      throw CLIError(message: "--missing takes one of: \(missable.joined(separator: ", ")).", usage: true)
    }
    let apps = Library.apps()
    let rows = apps.map { app in
      let current = Library.current(app.id)
      let status = AppStatus.check(app, current: current, manifest: Library.manifest(app.id))
      return AppRow(
        id: app.id,
        name: current?.architecture.name ?? app.name,
        path: app.path,
        components: current?.architecture.nodes.count,
        entities: current?.architecture.entities.count,
        versions: Library.versions(app.id).compactMap(\.version),
        savedAt: current?.savedAt,
        changedFiles: status.hasManifest ? status.changedFiles.count : nil,
        missing: current?.architecture.missing ?? ["architecture"]
      )
    }.filter { row in wanted.map { row.missing.contains($0) } ?? true }
    if args.json { return printJSON(rows) }

    guard !rows.isEmpty else {
      if let wanted {
        print("Every tracked app has its \(wanted).")
      } else {
        print("Blueprint doesn't track any apps yet. Add one with: blueprint add <folder>")
      }
      return
    }
    let idWidth = max(4, rows.map(\.id.count).max() ?? 0) + 2
    let nameWidth = max(6, rows.map(\.name.count).max() ?? 0) + 2
    let states: [String] = rows.map { row in
      if row.components == nil { return "not mapped yet" }
      if let changed = row.changedFiles { return changed == 0 ? "up to date" : "\(Terminal.plural(changed, "file")) changed" }
      return "saved \(row.savedAt.map(Terminal.ago) ?? "")"
    }
    let stateWidth = max(8, states.map { $0.count }.max() ?? 0) + 2
    let header = [("ID", idWidth), ("NAME", nameWidth), ("COMPONENTS", 12), ("DATA", 6), ("VERSIONS", 10), ("STATUS", stateWidth)]
    print(dim(header.map { Terminal.pad($0.0, $0.1) }.joined() + "MISSING"))
    for (row, state) in zip(rows, states) {
      let counts = [row.components, row.entities].map { count in count.map(String.init) ?? "–" }
      var line = Terminal.pad(row.id, idWidth) + Terminal.pad(row.name, nameWidth)
      line += Terminal.pad(counts[0], 12) + Terminal.pad(counts[1], 6) + Terminal.pad(String(row.versions.count), 10)
      let padded = Terminal.pad(state, stateWidth)
      line += state == "up to date" ? Terminal.green(padded) : state.hasPrefix("saved") ? dim(padded) : Terminal.yellow(padded)
      line += Terminal.yellow(row.missing.joined(separator: ", "))
      print(line)
    }
    if let wanted, wanted != "architecture" {
      print()
      print(Terminal.wrap("To add it, go to each app's folder, run blueprint show --json > /tmp/<app>.json, add the \(wanted) as blueprint guide describes, and save it with blueprint set --file /tmp/<app>.json."))
    }
  }

  struct AppRow: Encodable {
    var id: String
    var name: String
    var path: String
    var components: Int?
    var entities: Int?
    var versions: [String]
    var savedAt: Date?
    var changedFiles: Int?
    /// What an agent still has to add, from `Commands.missable`.
    var missing: [String]
  }

  // MARK: add and remove

  static func add(_ args: Arguments) throws {
    guard args.positional.count <= 1 else { throw CLIError(message: "Pass one folder at a time.", usage: true) }
    let folder = URL(fileURLWithPath: expand(args.positional.first ?? "."), relativeTo: cwd)
    let app = try Library.add(folder)
    print("Tracking \(app.name) as \(app.id), from \(app.path).")
    print("Next, map its architecture: run blueprint guide and follow it.")
  }

  static func remove(_ args: Arguments) throws {
    let app = try args.app()
    try Library.remove(app)
    print("Stopped tracking \(app.name). Its architecture and versions are in the Trash, and \(app.path) is untouched.")
  }

  // MARK: show

  static func show(_ args: Arguments) throws {
    let app = try args.app()
    let snapshot = try load(args.option("version") ?? "current", of: app)
    if args.flag("data") { return showData(snapshot, json: args.json) }
    if args.json { return printJSON(snapshot.architecture) }

    let architecture = snapshot.architecture
    print(bold(architecture.name) + (snapshot.version.map { " " + dim($0) } ?? ""))
    if let summary = architecture.summary { print(Terminal.wrap(summary)) }
    print(dim("Saved \(Terminal.ago(snapshot.savedAt))\(snapshot.commit.map { " at \($0)" } ?? "") · \(Terminal.plural(architecture.nodes.count, "component")) · \(Terminal.plural(architecture.edges.count, "connection"))"))

    if !architecture.walkthrough.isEmpty {
      print()
      print(bold("HOW IT WORKS"))
      for (index, step) in architecture.walkthrough.enumerated() {
        print("  \(index + 1). \(bold(step.title))")
        if !step.text.isEmpty { print(Terminal.wrap(step.text, indent: "     ")) }
        let names = step.nodes.map { architecture.node($0)?.name ?? $0 }
        if !names.isEmpty { print(dim(Terminal.wrap(names.joined(separator: ", "), indent: "     "))) }
      }
    }

    if !architecture.overview.isEmpty {
      print()
      print(bold("OVERVIEW"))
      let map = architecture.overviewMap
      for block in architecture.overview {
        print("  \(bold(block.name)) \(dim("(\(block.id))"))")
        if let summary = block.summary { print(Terminal.wrap(summary, indent: "    ")) }
        let names = block.nodes.map { architecture.node($0)?.name ?? $0 }
        if !names.isEmpty { print(dim(Terminal.wrap("Stands for " + names.joined(separator: ", "), indent: "    "))) }
        for link in map.edges where link.from == block.id {
          print("    → \(map.node(link.to)?.name ?? link.to)\(link.label.map { ": \($0)" } ?? "")")
        }
      }
    }

    for flow in architecture.flows {
      print()
      print(bold("FLOW: \(flow.title.uppercased())") + dim(" (\(flow.id)) · \(flow.actor ?? "no actor") · \(flow.area ?? "no area")"))
      if let goal = flow.goal { print(Terminal.wrap(goal, indent: "  ")) }
      for (index, step) in flow.steps.enumerated() {
        let lane = step.lane.map { dim(" · \($0)") } ?? ""
        print("  \(index + 1). \(step.title)\(dim(" [\(step.kind)]"))\(lane)")
        if let text = step.text { print(Terminal.wrap(text, indent: "     ")) }
        for link in step.next {
          let target = flow.step(link.to)?.title ?? link.to
          print(dim("     → \(target)\(link.label.map { " (\($0))" } ?? "")"))
        }
      }
    }

    let ungrouped = architecture.nodes.filter { node in node.group.flatMap(architecture.group) == nil }
    let sections = architecture.groups.map { group in (group.name, architecture.nodes.filter { $0.group == group.id }) } + [("No group", ungrouped)]
    for (title, nodes) in sections where !nodes.isEmpty {
      print()
      print(bold(title.uppercased()))
      for node in nodes {
        let tech = node.tech.isEmpty ? "" : " · " + node.tech.joined(separator: ", ")
        print("  \(bold(node.name)) \(dim("(\(node.id), \(node.kind))"))\(tech)")
        if let summary = node.summary { print(Terminal.wrap(summary, indent: "    ")) }
        for detail in node.details { print("    - " + Terminal.wrap(detail, indent: "      ").dropFirst(6)) }
        for edge in architecture.edges where edge.from == node.id {
          let target = architecture.node(edge.to)?.name ?? edge.to
          print("    → \(target)\(edge.label.map { ": \($0)" } ?? "")\(edge.kind.map { dim(" [\($0)]") } ?? "")")
          if let note = edge.note { print(dim(Terminal.wrap(note, indent: "      "))) }
        }
        if !node.paths.isEmpty { print(dim("    " + node.paths.joined(separator: ", "))) }
      }
    }
    printData(architecture)

    for explainer in architecture.explainers {
      print()
      print(bold("EXPLAINER: \(explainer.title.uppercased())") + dim(" (\(explainer.id))"))
      if let summary = explainer.summary { print(Terminal.wrap(summary, indent: "  ")) }
      for (index, scene) in explainer.scenes.enumerated() {
        print("  \(index + 1). \(bold(scene.title))")
        print(Terminal.wrap(scene.text, indent: "     "))
        var shown = scene.nodes.map { architecture.node($0)?.name ?? $0 }
        if let id = scene.flow {
          let flow = architecture.flow(id)
          let steps = scene.steps.map { flow?.step($0)?.title ?? $0 }
          shown.append("flow \(flow?.title ?? id)" + (steps.isEmpty ? "" : ": " + steps.joined(separator: ", ")))
        }
        shown += scene.entities.map { architecture.entity($0)?.name ?? $0 }
        print(dim("     " + (shown.isEmpty ? "title card" : shown.joined(separator: ", "))))
      }
    }
  }

  /// Only what the app stores, for agents that need the schema without the rest.
  private static func showData(_ snapshot: Snapshot, json: Bool) {
    let architecture = snapshot.architecture
    let stores = storeIDs(architecture).compactMap { $0.flatMap(architecture.node) }
    if json {
      return printJSON(DataOutput(name: architecture.name, version: snapshot.version ?? "current", stores: stores, entities: architecture.entities))
    }
    print(bold(architecture.name) + (snapshot.version.map { " " + dim($0) } ?? ""))
    guard !architecture.entities.isEmpty else {
      print("No data mapped yet. Run blueprint guide to see how to add what the app stores.")
      return
    }
    print(dim("\(entities(architecture.entities.count)) in \(Terminal.plural(stores.count, "store"))"))
    printData(architecture)
  }

  struct DataOutput: Encodable {
    var name: String
    var version: String
    /// The components that hold the entities.
    var stores: [Architecture.Node]
    var entities: [Architecture.Entity]
  }

  /// The stores entities name, in the order they first do.
  private static func storeIDs(_ architecture: Architecture) -> [String?] {
    architecture.entities.reduce(into: [String?]()) { stores, entity in
      if !stores.contains(entity.store) { stores.append(entity.store) }
    }
  }

  private static func entities(_ count: Int) -> String { "\(count) entit\(count == 1 ? "y" : "ies")" }

  private static func printData(_ architecture: Architecture) {
    for store in storeIDs(architecture) {
      let node = store.flatMap(architecture.node)
      print()
      print(bold("DATA IN \((node?.name ?? store ?? "no store").uppercased())") + (node.map { dim(" (\(([$0.kind] + $0.tech).joined(separator: ", ")))") } ?? ""))
      for entity in architecture.entities where entity.store == store {
        print("  \(bold(entity.name)) \(dim("(\(entity.id))"))")
        if let summary = entity.summary { print(Terminal.wrap(summary, indent: "    ")) }
        for detail in entity.details { print("    - " + Terminal.wrap(detail, indent: "      ").dropFirst(6)) }
        for field in entity.fields {
          var line = "    \(field.name)"
          if let type = field.type { line += dim(": \(type)") }
          if field.isKey { line += Terminal.yellow(" key") }
          if let ref = field.ref { line += " → \(architecture.entity(ref)?.name ?? ref)" }
          if let note = field.note { line += dim("  \(note)") }
          print(line)
        }
        if !entity.paths.isEmpty { print(dim("    " + entity.paths.joined(separator: ", "))) }
      }
    }
  }

  // MARK: set

  static func set(_ args: Arguments) throws {
    let app = try args.app()
    let data: Data
    if let file = args.option("file") {
      let url = URL(fileURLWithPath: expand(file), relativeTo: cwd)
      guard let contents = try? Data(contentsOf: url) else { throw BlueprintError("Can't read \(url.path).") }
      data = contents
    } else if isatty(STDIN_FILENO) == 0 {
      data = FileHandle.standardInput.readDataToEndOfFile()
    } else {
      throw CLIError(message: "Pass the JSON with --file <path>, or on standard input.", usage: true)
    }

    let architecture = try Architecture.decode(data).normalized()
    let report = architecture.validate(root: app.url)
    for warning in report.warnings { Terminal.note(Terminal.yellow("warning: ") + warning) }
    guard report.errors.isEmpty else {
      for error in report.errors { Terminal.note(Terminal.red("error: ") + error) }
      throw BlueprintError("Nothing saved, because of the \(report.errors.count == 1 ? "error" : "errors") above.")
    }
    var counts = "\(Terminal.plural(architecture.nodes.count, "component")) in \(Terminal.plural(architecture.groups.count, "group")), \(Terminal.plural(architecture.edges.count, "connection"))"
    if !architecture.overview.isEmpty { counts += ", \(Terminal.plural(architecture.overview.count, "overview block"))" }
    if !architecture.entities.isEmpty { counts += ", \(entities(architecture.entities.count))" }
    if !architecture.explainers.isEmpty { counts += ", \(Terminal.plural(architecture.explainers.count, "explainer"))" }
    if args.flag("dry-run") {
      print("The architecture is valid: \(counts). Nothing saved.")
      return
    }

    if args.flag("past") {
      guard let version = args.option("version") else {
        throw CLIError(message: "--past needs the version it describes, like --version 1.0.0.", usage: true)
      }
      let snapshot = try Library.savePastVersion(architecture, as: version, for: app)
      print("Saved \(architecture.name) \(snapshot.version ?? version)\(snapshot.commit.map { " (at \($0))" } ?? ""): \(counts). The current architecture is unchanged.")
      return
    }

    let previous = Library.current(app.id)
    try Library.save(architecture, for: app)
    print("Saved the architecture of \(architecture.name): \(counts).")
    if let previous { print(changesSince(previous.architecture, architecture)) }
    if let version = args.option("version") {
      let snapshot = try Library.saveVersion(version, for: app)
      print("Saved it as version \(snapshot.version ?? version) too.")
    }
  }

  /// What changed since the last save: the diff of components, connections and data, then the parts it doesn't cover.
  static func changesSince(_ old: Architecture, _ new: Architecture) -> String {
    let diff = ArchitectureDiff(from: old, to: new)
    var parts: [String] = []
    if old.name != new.name || old.summary != new.summary { parts.append("summary") }
    if old.walkthrough != new.walkthrough { parts.append("walkthrough") }
    if old.overview != new.overview { parts.append("overview") }
    if old.flows != new.flows { parts.append("flows") }
    if old.explainers != new.explainers { parts.append("explainers") }
    let rest = parts.count < 2 ? parts.joined() : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    switch (diff.isEmpty, parts.isEmpty) {
    case (true, true): return old == new ? "Nothing changed since the last save." : "Since the last save: only descriptions and details changed."
    case (true, false): return "Since the last save: the \(rest) changed."
    case (false, true): return "Since the last save: \(diff.summary)."
    case (false, false): return "Since the last save: \(diff.summary), and the \(rest) changed."
    }
  }

  // MARK: status

  static func status(_ args: Arguments) throws {
    let app = try args.app()
    let current = Library.current(app.id)
    let status = AppStatus.check(app, current: current, manifest: Library.manifest(app.id))
    if args.json {
      return printJSON(StatusOutput(
        app: app.id,
        mapped: current != nil,
        savedAt: current?.savedAt,
        commit: current?.commit,
        commitsSince: status.commitsSince,
        upToDate: status.hasManifest ? !status.isStale : nil,
        changedFiles: status.changedFiles,
        touchedComponents: current?.architecture.nodes.map(\.id).filter(status.touched.contains) ?? [],
        uncoveredFiles: status.uncovered
      ))
    }

    let name = current?.architecture.name ?? app.name
    guard let current else {
      print("\(name) has no architecture yet. Run blueprint guide to see how to map it.")
      return
    }
    var saved = "saved \(Terminal.ago(current.savedAt))"
    if let commit = current.commit {
      saved += " at \(commit)"
      if let commits = status.commitsSince, commits > 0 { saved += ", \(Terminal.plural(commits, "commit")) ago" }
    }
    guard status.isRepo else {
      print("\(name)'s architecture was \(saved). \(app.path) isn't a git repository, so Blueprint can't tell what changed since.")
      return
    }
    guard status.hasManifest else {
      print("\(name)'s architecture was \(saved). Save it again with blueprint set, so Blueprint can track what changes.")
      return
    }
    guard status.isStale else {
      print("\(name) is up to date: no code changed since its architecture was \(saved).")
      return
    }

    print("\(name): \(Terminal.plural(status.changedFiles.count, "file")) changed since the architecture was \(saved).")
    let touched = current.architecture.nodes.filter { status.touched.contains($0.id) }
    if !touched.isEmpty {
      print()
      print(bold("Components with changed files:"))
      for node in touched {
        print("  \(node.name) \(dim("(\(node.id))"))")
        for file in status.changedFiles where node.covers(file) { print(dim("    \(file)")) }
      }
    }
    if !status.uncovered.isEmpty {
      print()
      print(bold("Changed files outside every component:"))
      for file in status.uncovered.prefix(40) { print("  \(file)") }
      if status.uncovered.count > 40 { print(dim("  and \(status.uncovered.count - 40) more")) }
    }
    print()
    print(Terminal.wrap("If these changes affect the architecture, update it: blueprint show --json > /tmp/\(app.id).json, edit the file, then blueprint set --file /tmp/\(app.id).json. If they don't, save it again unchanged so Blueprint knows it's current."))
  }

  struct StatusOutput: Encodable {
    var app: String
    var mapped: Bool
    var savedAt: Date?
    var commit: String?
    var commitsSince: Int?
    var upToDate: Bool?
    var changedFiles: [String]
    var touchedComponents: [String]
    var uncoveredFiles: [String]
  }

  // MARK: versions

  static func snapshot(_ args: Arguments) throws {
    let app = try args.app()
    guard let name = args.option("version") ?? Git.tagAtHead(app.url) else {
      throw CLIError(message: "Pass the version, like --version 1.2.0. The current commit has no tag to use.", usage: true)
    }
    let version = Library.normalizeVersion(name)
    if args.flag("delete") {
      try Library.removeVersion(version, of: app)
      print("Moved version \(version) of \(app.name) to the Trash.")
      return
    }
    if Library.version(version, of: app.id) != nil, !args.flag("force") {
      throw BlueprintError("\(app.name) already has version \(version). Use --force to replace it.")
    }
    try Library.saveVersion(version, for: app)
    print("Saved the current architecture of \(app.name) as version \(version).")
    let status = AppStatus.check(app, current: Library.current(app.id), manifest: Library.manifest(app.id))
    if status.isStale {
      Terminal.note(Terminal.yellow("warning: ") + "\(Terminal.plural(status.changedFiles.count, "file")) changed since the architecture was saved. If they change the architecture, update it and run this again with --force.")
    }
  }

  static func versions(_ args: Arguments) throws {
    let app = try args.app()
    let snapshots = Library.versions(app.id) + [Library.current(app.id)].compactMap { $0 }
    if args.json {
      return printJSON(snapshots.map { VersionRow(version: $0.version ?? "current", savedAt: $0.savedAt, commit: $0.commit, components: $0.architecture.nodes.count) })
    }
    guard !snapshots.isEmpty else {
      print("\(app.name) has no architecture yet. Run blueprint guide to see how to map it.")
      return
    }
    let width = max(9, snapshots.map { ($0.version ?? "current").count }.max() ?? 0) + 2
    for snapshot in snapshots {
      let details = "saved \(Terminal.ago(snapshot.savedAt))\(snapshot.commit.map { " at \($0)" } ?? ""), \(Terminal.plural(snapshot.architecture.nodes.count, "component"))"
      print(Terminal.pad(snapshot.version ?? "current", width) + dim(details))
    }
    if snapshots.count == 1 {
      print()
      print("Save a version with: blueprint snapshot --version 1.0.0")
    }
  }

  struct VersionRow: Encodable {
    var version: String
    var savedAt: Date
    var commit: String?
    var components: Int
  }

  static func diff(_ args: Arguments) throws {
    let app = try args.app()
    guard let fromName = args.option("from") ?? Library.versions(app.id).last?.version else {
      throw BlueprintError("\(app.name) has no saved versions to compare with. Save one with: blueprint snapshot --version 1.0.0")
    }
    let toName = args.option("to") ?? "current"
    let from = try load(fromName, of: app)
    let to = try load(toName, of: app)
    let diff = ArchitectureDiff(from: from.architecture, to: to.architecture)
    let merged = diff.merged
    func name(_ id: String) -> String { merged.node(id)?.name ?? id }

    if args.json {
      return printJSON(DiffOutput(
        from: from.version ?? "current",
        to: to.version ?? "current",
        added: diff.ids(.added),
        removed: diff.ids(.removed),
        changed: diff.ids(.changed).map { .init(id: $0, details: diff.nodeDetails[$0] ?? []) },
        connections: .init(
          added: diff.edgeIDs(.added),
          removed: diff.edgeIDs(.removed),
          changed: diff.edgeIDs(.changed).map { .init(id: $0, details: diff.edgeDetails[$0] ?? []) }
        ),
        entities: .init(
          added: diff.entityIDs(.added),
          removed: diff.entityIDs(.removed),
          changed: diff.entityIDs(.changed).map { .init(id: $0, details: diff.entityDetails[$0] ?? []) }
        )
      ))
    }

    print(bold("\(to.architecture.name): \(from.version ?? "current") → \(to.version ?? "current")"))
    guard !diff.isEmpty else {
      print("No changes.")
      return
    }
    print(diff.summary)
    for change in [Change.added, .removed, .changed] {
      for id in diff.ids(change) {
        guard let node = merged.node(id) else { continue }
        let line = "\(mark(change)) \(node.name) \(dim("(\(node.id), \(node.kind))"))"
        print(line)
        if change == .added, let summary = node.summary { print(dim(Terminal.wrap(summary, indent: "    "))) }
        for detail in diff.nodeDetails[id] ?? [] { print("    \(detail)") }
      }
    }
    let edges = [Change.added, .removed, .changed].flatMap { change in diff.edgeIDs(change).map { (change, $0) } }
    if !edges.isEmpty {
      print()
      print(bold("Connections"))
      for (change, id) in edges {
        guard let edge = merged.edges.first(where: { $0.id == id }) else { continue }
        print("\(mark(change)) \(name(edge.from)) → \(name(edge.to))\(edge.label.map { dim("  \($0)") } ?? "")")
        for detail in diff.edgeDetails[id] ?? [] { print("    \(detail)") }
      }
    }
    for (id, change) in diff.groups.sorted(by: { $0.key < $1.key }) where change == .added || change == .removed {
      print("\(mark(change)) group \(merged.group(id)?.name ?? id)")
    }
    let entities = [Change.added, .removed, .changed].flatMap { change in diff.entityIDs(change).map { (change, $0) } }
    if !entities.isEmpty {
      print()
      print(bold("Data"))
      for (change, id) in entities {
        guard let entity = merged.entity(id) else { continue }
        print("\(mark(change)) \(entity.name) \(dim("(\(entity.id))"))")
        if change == .added, let summary = entity.summary { print(dim(Terminal.wrap(summary, indent: "    "))) }
        for detail in diff.entityDetails[id] ?? [] { print("    \(detail)") }
      }
    }
  }

  struct DiffOutput: Encodable {
    struct Changed: Encodable {
      var id: String
      var details: [String]
    }
    struct Changes: Encodable {
      var added: [String]
      var removed: [String]
      var changed: [Changed]
    }
    var from: String
    var to: String
    var added: [String]
    var removed: [String]
    var changed: [Changed]
    var connections: Changes
    var entities: Changes
  }

  private static func mark(_ change: Change) -> String {
    switch change {
    case .added: Terminal.green("+")
    case .removed: Terminal.red("-")
    case .changed: Terminal.yellow("~")
    case .unchanged: " "
    }
  }

  // MARK: open

  static func open(_ args: Arguments) throws {
    let app = try args.app()
    var components = URLComponents()
    components.scheme = "blueprint"
    components.host = "open"
    components.queryItems = [URLQueryItem(name: "app", value: app.id)]
      + [("version", args.option("version")), ("compare", args.option("compare"))].compactMap { name, value in
        value.map { URLQueryItem(name: name, value: Library.normalizeVersion($0)) }
      }
    guard let url = components.url else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      throw BlueprintError("Couldn't open the Blueprint app. Open it once from the Finder, then try again.")
    }
  }

  // MARK: Helpers

  static var cwd: URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath) }

  static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

  static func load(_ name: String, of app: TrackedApp) throws -> Snapshot {
    if name.lowercased() == "current" {
      guard let current = Library.current(app.id) else {
        throw BlueprintError("\(app.name) has no architecture yet. Run blueprint guide to see how to map it.")
      }
      return current
    }
    guard let snapshot = Library.version(name, of: app.id) else {
      let names = Library.versions(app.id).compactMap(\.version)
      throw BlueprintError("\(app.name) has no version \(name).\(names.isEmpty ? "" : " Its versions: \(names.joined(separator: ", ")).")")
    }
    return snapshot
  }

  static func printJSON<T: Encodable>(_ value: T) {
    guard let data = try? Library.encoder.encode(value) else { return }
    print(String(decoding: data, as: UTF8.self))
  }
}
