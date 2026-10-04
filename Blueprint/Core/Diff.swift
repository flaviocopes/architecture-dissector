import Foundation

enum Change: String, Sendable {
  case added, removed, changed, unchanged
}

/// What changed between two architectures. Components match by id, connections by their two ends,
/// entities by id and their fields by name.
struct ArchitectureDiff: Sendable {
  var nodes: [String: Change] = [:]
  var nodeDetails: [String: [String]] = [:]
  var edges: [String: Change] = [:]
  var edgeDetails: [String: [String]] = [:]
  var groups: [String: Change] = [:]
  var entities: [String: Change] = [:]
  var entityDetails: [String: [String]] = [:]
  /// The fields that changed in each entity that's in both, by name.
  var fields: [String: [String: Change]] = [:]
  /// The target plus everything the target removed, so removed parts can still be drawn.
  var merged: Architecture

  init(from base: Architecture, to target: Architecture) {
    merged = target

    for group in target.groups {
      guard let old = base.group(group.id) else {
        groups[group.id] = .added
        continue
      }
      groups[group.id] = old.name == group.name ? .unchanged : .changed
    }
    for group in base.groups where target.group(group.id) == nil {
      groups[group.id] = .removed
      merged.groups.append(group)
    }

    for node in target.nodes {
      guard let old = base.node(node.id) else {
        nodes[node.id] = .added
        continue
      }
      let details = Self.describe(old, node, base: base, target: target)
      nodes[node.id] = details.isEmpty ? .unchanged : .changed
      if !details.isEmpty { nodeDetails[node.id] = details }
    }
    for node in base.nodes where target.node(node.id) == nil {
      nodes[node.id] = .removed
      merged.nodes.append(node)
    }

    let oldEdges = Dictionary(base.edges.map { ($0.id, $0) }) { first, _ in first }
    let newEdges = Set(target.edges.map(\.id))
    for edge in target.edges {
      guard let old = oldEdges[edge.id] else {
        edges[edge.id] = .added
        continue
      }
      var details: [String] = []
      if (old.label ?? "") != (edge.label ?? "") {
        details.append("Label: \(old.label.map { "“\($0)”" } ?? "none") → \(edge.label.map { "“\($0)”" } ?? "none")")
      }
      if old.edgeKind != edge.edgeKind {
        details.append("\(old.edgeKind.rawValue.capitalized) → \(edge.edgeKind.rawValue)")
      }
      edges[edge.id] = details.isEmpty ? .unchanged : .changed
      if !details.isEmpty { edgeDetails[edge.id] = details }
    }
    for edge in base.edges where !newEdges.contains(edge.id) {
      edges[edge.id] = .removed
      merged.edges.append(edge)
    }

    for (index, entity) in target.entities.enumerated() {
      guard let old = base.entity(entity.id) else {
        entities[entity.id] = .added
        continue
      }
      var changes: [String: Change] = [:]
      for field in entity.fields {
        guard let previous = old.field(field.name) else {
          changes[field.name] = .added
          continue
        }
        if previous.type != field.type || previous.isKey != field.isKey || previous.ref != field.ref { changes[field.name] = .changed }
      }
      // A removed field keeps its old place, so it's drawn where it was.
      for (position, field) in old.fields.enumerated() where entity.field(field.name) == nil {
        changes[field.name] = .removed
        merged.entities[index].fields.insert(field, at: min(position, merged.entities[index].fields.count))
      }
      let details = Self.describe(old, entity, changes, base: base, target: target)
      entities[entity.id] = details.isEmpty ? .unchanged : .changed
      if !details.isEmpty { entityDetails[entity.id] = details }
      if !changes.isEmpty { fields[entity.id] = changes }
    }
    for entity in base.entities where target.entity(entity.id) == nil {
      entities[entity.id] = .removed
      merged.entities.append(entity)
    }
  }

  func ids(_ change: Change) -> [String] {
    merged.nodes.map(\.id).filter { nodes[$0] == change }
  }

  func edgeIDs(_ change: Change) -> [String] {
    merged.edges.map(\.id).filter { edges[$0] == change }
  }

  func entityIDs(_ change: Change) -> [String] {
    merged.entities.map(\.id).filter { entities[$0] == change }
  }

  /// How a field compares, counting every field of a new or removed entity as new or removed too.
  func field(_ name: String, of entity: String) -> Change {
    switch entities[entity] {
    case .added: .added
    case .removed: .removed
    default: fields[entity]?[name] ?? .unchanged
    }
  }

  var isEmpty: Bool {
    !nodes.values.contains { $0 != .unchanged } && !edges.values.contains { $0 != .unchanged } && !groups.values.contains { $0 != .unchanged }
      && !entities.values.contains { $0 != .unchanged }
  }

  /// Like "3 added, 1 removed, 2 changed", with the data after it.
  var summary: String {
    func counts(_ changes: Dictionary<String, Change>.Values) -> [String] {
      [(Change.added, "added"), (.removed, "removed"), (.changed, "changed")].compactMap { change, word in
        let count = changes.filter { $0 == change }.count
        return count > 0 ? "\(count) \(word)" : nil
      }
    }
    var parts = counts(nodes.values)
    let connections = edges.values.filter { $0 == .added || $0 == .removed || $0 == .changed }.count
    if parts.isEmpty, connections > 0 { parts.append("\(connections) connection\(connections == 1 ? "" : "s") changed") }
    let data = counts(entities.values)
    if !data.isEmpty { parts.append("data: " + data.joined(separator: ", ")) }
    return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
  }

  private static func describe(_ old: Architecture.Node, _ new: Architecture.Node, base: Architecture, target: Architecture) -> [String] {
    var details: [String] = []
    if old.name != new.name { details.append("Renamed from \(old.name)") }
    if old.nodeKind != new.nodeKind { details.append("Kind: \(old.nodeKind.label) → \(new.nodeKind.label)") }
    if old.group != new.group {
      let from = old.group.map { base.group($0)?.name ?? $0 } ?? "no group"
      let to = new.group.map { target.group($0)?.name ?? $0 } ?? "no group"
      details.append("Moved from \(from) to \(to)")
    }
    // Writing a description for the first time documents a part; only rewriting one counts as a change.
    if let summary = old.summary, !summary.isEmpty, summary != (new.summary ?? "") { details.append("New description") }
    if !old.details.isEmpty, old.details != new.details { details.append("New details") }
    details += listChanges("tech", old.tech, new.tech)
    details += listChanges("files", old.paths.map(Architecture.normalize), new.paths.map(Architecture.normalize))
    return details
  }

  private static func describe(_ old: Architecture.Entity, _ new: Architecture.Entity, _ fields: [String: Change], base: Architecture, target: Architecture) -> [String] {
    var details: [String] = []
    if old.name != new.name { details.append("Renamed from \(old.name)") }
    if old.store != new.store {
      let from = old.store.map { base.node($0)?.name ?? $0 } ?? "no store"
      let to = new.store.map { target.node($0)?.name ?? $0 } ?? "no store"
      details.append("Moved from \(from) to \(to)")
    }
    if let summary = old.summary, !summary.isEmpty, summary != (new.summary ?? "") { details.append("New description") }
    if !old.details.isEmpty, old.details != new.details { details.append("New details") }
    let added = new.fields.map(\.name).filter { fields[$0] == .added }
    let removed = old.fields.map(\.name).filter { fields[$0] == .removed }
    if !added.isEmpty { details.append("Added \(added.count == 1 ? "field" : "fields") \(added.joined(separator: ", "))") }
    if !removed.isEmpty { details.append("Removed \(removed.count == 1 ? "field" : "fields") \(removed.joined(separator: ", "))") }
    for field in new.fields where fields[field.name] == .changed {
      guard let previous = old.field(field.name) else { continue }
      if previous.type != field.type { details.append("\(field.name): \(previous.type ?? "no type") → \(field.type ?? "no type")") }
      if previous.isKey != field.isKey { details.append(field.isKey ? "\(field.name) is now the key" : "\(field.name) is no longer the key") }
      if previous.ref != field.ref {
        let name = field.ref.map { target.entity($0)?.name ?? $0 }
        details.append(name.map { "\(field.name) now points to \($0)" } ?? "\(field.name) no longer points to another entity")
      }
    }
    details += listChanges("files", old.paths.map(Architecture.normalize), new.paths.map(Architecture.normalize))
    return details
  }

  private static func listChanges(_ what: String, _ old: [String], _ new: [String]) -> [String] {
    let added = new.filter { !old.contains($0) }
    let removed = old.filter { !new.contains($0) }
    var details: [String] = []
    if !added.isEmpty { details.append("Added \(what): \(added.joined(separator: ", "))") }
    if !removed.isEmpty { details.append("Removed \(what): \(removed.joined(separator: ", "))") }
    return details
  }
}
