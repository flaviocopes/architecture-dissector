import Foundation

/// An app's architecture: components grouped by layer, and the connections between them.
/// Agents write it as JSON with `blueprint set`, and the app draws it.
struct Architecture: Codable, Equatable, Sendable {
  var name: String
  var summary: String?
  /// Steps that walk a newcomer through how the app works, each highlighting the components involved.
  var walkthrough: [Step] = []
  var groups: [Group]
  var nodes: [Node]
  var edges: [Edge]
  /// What people do with the app, step by step: one flow per need.
  var flows: [Flow] = []
  /// What the app stores: tables, collections, files and settings, field by field.
  var entities: [Entity] = []
  /// Short videos about parts of the app. Agents say what each scene shows, and Blueprint plays them in one style.
  var explainers: [Explainer] = []

  struct Explainer: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    /// What you learn from it, in one sentence.
    var summary: String?
    var scenes: [Scene]
  }

  /// One scene of an explainer. It shows components, steps of a flow, or entities, or none of them for a title card.
  struct Scene: Codable, Equatable, Sendable {
    var title: String
    var text: String
    var nodes: [String] = []
    var flow: String?
    var steps: [String] = []
    var entities: [String] = []
  }

  /// One kind of record the app stores, like a table, a collection or a JSON file.
  struct Entity: Codable, Equatable, Sendable, Identifiable {
    var id: String
    /// What the code calls it: the table, the file or the type.
    var name: String
    /// The component that holds it, usually a database or storage.
    var store: String?
    /// What one record is, in one sentence.
    var summary: String?
    var details: [String] = []
    var fields: [Field] = []
    var paths: [String] = []

    func field(_ name: String) -> Field? { fields.first { $0.name == name } }
  }

  struct Field: Codable, Equatable, Sendable {
    var name: String
    var type: String?
    /// Whether it identifies a record, like a primary key.
    var key: Bool?
    /// The entity it points to: a foreign key, or a record it holds.
    var ref: String?
    var note: String?

    var isKey: Bool { key == true }
  }

  struct Step: Codable, Equatable, Sendable {
    var title: String
    var text: String
    var nodes: [String]
  }

  struct Flow: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    /// The need behind it, in the words of whoever has it.
    var goal: String?
    /// Whose workflow it is: user, owner, agent or app.
    var actor: String?
    /// The part of the app it belongs to, like "Editor" or "Sync".
    var area: String?
    var steps: [FlowStep]

    var flowActor: FlowActor? { actor.flatMap(FlowActor.init(rawValue:)) }

    /// Where each step goes: its own links, or the step after it, unless it's where the flow ends.
    func next(_ step: FlowStep) -> [FlowLink] {
      if !step.next.isEmpty { return step.next }
      if step.stepKind == .done { return [] }
      guard let index = steps.firstIndex(where: { $0.id == step.id }), index + 1 < steps.count else { return [] }
      return [FlowLink(to: steps[index + 1].id)]
    }

    func step(_ id: String) -> FlowStep? { steps.first { $0.id == id } }

    /// Who acts in the flow, in the order they first show up.
    var lanes: [String] {
      var seen: [String] = []
      for step in steps where !seen.contains(step.lane ?? "") { seen.append(step.lane ?? "") }
      return seen
    }
  }

  struct FlowStep: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var text: String?
    var kind: String
    /// Who does it: "You", the app's name, "Agent".
    var lane: String?
    /// The components that make it happen.
    var nodes: [String] = []
    var next: [FlowLink] = []

    var stepKind: StepKind { StepKind(rawValue: kind) ?? .action }
  }

  struct FlowLink: Codable, Equatable, Sendable {
    var to: String
    var label: String?
  }

  struct Group: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var summary: String?
  }

  struct Node: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var group: String?
    /// The role it plays in the app, in one sentence.
    var summary: String?
    /// A few short points that make the role precise.
    var details: [String] = []
    var tech: [String]
    var paths: [String]

    var nodeKind: NodeKind { NodeKind(rawValue: kind) ?? .service }

    /// Whether `file`, relative to the app folder, is one of this component's paths or inside one.
    func covers(_ file: String) -> Bool {
      paths.contains { path in
        let path = Architecture.normalize(path)
        return path.isEmpty || file == path || file.hasPrefix(path + "/")
      }
    }
  }

  struct Edge: Codable, Equatable, Sendable, Identifiable {
    var from: String
    var to: String
    var label: String?
    var kind: String?

    var id: String { "\(from)->\(to)" }
    var edgeKind: EdgeKind { kind.flatMap(EdgeKind.init(rawValue:)) ?? .calls }
  }

  func node(_ id: String) -> Node? { nodes.first { $0.id == id } }
  func group(_ id: String) -> Group? { groups.first { $0.id == id } }
  func entity(_ id: String) -> Entity? { entities.first { $0.id == id } }
  func flow(_ id: String) -> Flow? { flows.first { $0.id == id } }

  static func normalize(_ path: String) -> String {
    var path = path.trimmingCharacters(in: .whitespaces)
    while path.hasPrefix("./") { path.removeFirst(2) }
    while path.hasSuffix("/") { path.removeLast() }
    return path == "." ? "" : path
  }
}

extension Architecture {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    walkthrough = try container.decodeIfPresent([Step].self, forKey: .walkthrough) ?? []
    groups = try container.decodeIfPresent([Group].self, forKey: .groups) ?? []
    nodes = try container.decodeIfPresent([Node].self, forKey: .nodes) ?? []
    edges = try container.decodeIfPresent([Edge].self, forKey: .edges) ?? []
    flows = try container.decodeIfPresent([Flow].self, forKey: .flows) ?? []
    entities = try container.decodeIfPresent([Entity].self, forKey: .entities) ?? []
    explainers = try container.decodeIfPresent([Explainer].self, forKey: .explainers) ?? []
  }
}

extension Architecture.Explainer {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    scenes = try container.decodeIfPresent([Architecture.Scene].self, forKey: .scenes) ?? []
  }
}

extension Architecture.Scene {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    nodes = try container.decodeIfPresent([String].self, forKey: .nodes) ?? []
    flow = try container.decodeIfPresent(String.self, forKey: .flow)
    steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
    entities = try container.decodeIfPresent([String].self, forKey: .entities) ?? []
  }
}

extension Architecture.Entity {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    store = try container.decodeIfPresent(String.self, forKey: .store)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    details = try container.decodeIfPresent([String].self, forKey: .details) ?? []
    fields = try container.decodeIfPresent([Architecture.Field].self, forKey: .fields) ?? []
    paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
  }
}

extension Architecture.Flow {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    goal = try container.decodeIfPresent(String.self, forKey: .goal)
    actor = try container.decodeIfPresent(String.self, forKey: .actor)
    area = try container.decodeIfPresent(String.self, forKey: .area)
    steps = try container.decodeIfPresent([Architecture.FlowStep].self, forKey: .steps) ?? []
  }
}

/// Whose workflow a flow is.
enum FlowActor: String, CaseIterable, Sendable {
  case user, owner, agent, app

  var label: String {
    switch self {
    case .user: "People using it"
    case .owner: "The owner"
    case .agent: "Agents"
    case .app: "The app on its own"
    }
  }

  var help: String {
    switch self {
    case .user: "Someone using the app does it: writes a note, sends a campaign, exports a report"
    case .owner: "Whoever runs or maintains the app does it: sets it up, deploys, ships a release, manages accounts, restores a backup"
    case .agent: "An AI agent does it through the app's CLI, API or MCP server"
    case .app: "The app does it on its own, on a schedule or when something happens: syncs, reminders, update checks, cleanups"
    }
  }
}

extension Architecture.FlowStep {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    text = try container.decodeIfPresent(String.self, forKey: .text)
    kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? StepKind.action.rawValue
    lane = try container.decodeIfPresent(String.self, forKey: .lane)
    nodes = try container.decodeIfPresent([String].self, forKey: .nodes) ?? []
    next = try container.decodeIfPresent([Architecture.FlowLink].self, forKey: .next) ?? []
  }
}

enum StepKind: String, CaseIterable, Sendable {
  case action, system, decision, done

  var label: String {
    switch self {
    case .action: "Action"
    case .system: "The app responds"
    case .decision: "Decision"
    case .done: "Done"
    }
  }

  var help: String {
    switch self {
    case .action: "Someone does something: opens a screen, types, clicks, runs a command (default)"
    case .system: "The app or a service does something in response: saves, fetches, shows a result"
    case .decision: "A choice that sends the flow different ways; give each of its next links a label"
    case .done: "The need is met, and the flow ends here"
    }
  }
}

extension Architecture.Node {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? NodeKind.service.rawValue
    group = try container.decodeIfPresent(String.self, forKey: .group)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    details = try container.decodeIfPresent([String].self, forKey: .details) ?? []
    tech = try container.decodeIfPresent([String].self, forKey: .tech) ?? []
    paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
  }
}

extension Architecture.Step {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    nodes = try container.decodeIfPresent([String].self, forKey: .nodes) ?? []
  }
}

enum NodeKind: String, CaseIterable, Sendable {
  case user, client, ui, service, api, worker, cli, database, storage, queue, external

  var label: String {
    switch self {
    case .user: "User"
    case .client: "Client"
    case .ui: "UI"
    case .service: "Service"
    case .api: "API"
    case .worker: "Worker"
    case .cli: "CLI"
    case .database: "Database"
    case .storage: "Storage"
    case .queue: "Queue"
    case .external: "External"
    }
  }

  var help: String {
    switch self {
    case .user: "A person or another system that starts things: the user, an admin, a webhook sender"
    case .client: "An app people open: a Mac app, a website, a mobile app, a browser extension"
    case .ui: "Screens, views or components inside a client"
    case .service: "Modules with the logic: stores, managers, parsers, engines"
    case .api: "An HTTP or RPC surface: routes, server functions, an MCP server"
    case .worker: "Code that runs on its own: Cloudflare Workers, cron jobs, background tasks, functions"
    case .cli: "A command-line tool"
    case .database: "Where structured data lives: SQLite, Postgres, D1, Convex tables, KV"
    case .storage: "Files and blobs: folders on disk, JSON files, R2, S3, caches"
    case .queue: "Queues, event streams, pub/sub"
    case .external: "A third-party service or tool: Stripe, GitHub, an AI model, another CLI"
    }
  }
}

enum EdgeKind: String, CaseIterable, Sendable {
  case calls, reads, writes, sends

  var help: String {
    switch self {
    case .calls: "Calls, imports or requests it and waits for the answer (default)"
    case .reads: "Reads data from it"
    case .writes: "Writes data to it"
    case .sends: "Sends it messages or events without waiting"
    }
  }
}

/// One saved state of an architecture: the current one, or a version like 1.2.0.
struct Snapshot: Codable, Equatable, Sendable {
  var version: String?
  var savedAt: Date
  var commit: String?
  var architecture: Architecture
}

/// A folder Blueprint tracks.
struct TrackedApp: Codable, Identifiable, Hashable, Sendable {
  var id: String
  var name: String
  var path: String
  var addedAt: Date

  var url: URL { URL(fileURLWithPath: path) }
}

struct BlueprintError: LocalizedError {
  var message: String
  var errorDescription: String? { message }

  init(_ message: String) { self.message = message }
}
