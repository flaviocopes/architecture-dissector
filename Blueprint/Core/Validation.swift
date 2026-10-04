import Foundation

struct ValidationReport {
  var errors: [String] = []
  var warnings: [String] = []
}

extension Architecture {
  /// The parts an agent still has to add, by the same rules as the warnings of `validate`: "walkthrough",
  /// "overview", "notes" when most connections don't say what travels over them, "flows" when there are few
  /// of them or some don't say who does them or where, "data" when components store something but no entity
  /// says what, and "explainers".
  var missing: [String] {
    var parts: [String] = []
    if walkthrough.isEmpty, nodes.count > 1 { parts.append("walkthrough") }
    if overview.isEmpty, nodes.count > 1 { parts.append("overview") }
    if hasFewNotes { parts.append("notes") }
    if nodes.count > 1, flows.isEmpty || hasFewFlows || flows.contains(where: { $0.flowActor == nil || ($0.area ?? "").isEmpty }) {
      parts.append("flows")
    }
    if entities.isEmpty, nodes.contains(where: { $0.nodeKind == .database || $0.nodeKind == .storage }) { parts.append("data") }
    if explainers.isEmpty, nodes.count > 1 { parts.append("explainers") }
    return parts
  }

  /// An app with more than a handful of components goes through more than a handful of workflows.
  private var hasFewFlows: Bool { nodes.count > 5 && flows.count < 6 }

  /// The technical view writes each connection's note on the chart, so most connections need one.
  private var hasFewNotes: Bool {
    !edges.isEmpty && edges.filter { !($0.note ?? "").isEmpty }.count * 2 < edges.count
  }

  /// Decodes an architecture from JSON with error messages an agent can act on.
  static func decode(_ data: Data) throws -> Architecture {
    do {
      return try JSONDecoder().decode(Architecture.self, from: data)
    } catch let error as DecodingError {
      throw BlueprintError("The JSON doesn't match the format: \(describe(error)). Run blueprint guide to see the format.")
    } catch {
      throw BlueprintError("That isn't valid JSON: \(error.localizedDescription)")
    }
  }

  private static func describe(_ error: DecodingError) -> String {
    func path(_ keys: [CodingKey]) -> String {
      let path = keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
      return path.isEmpty ? "the top level" : String(path.drop { $0 == "." })
    }
    switch error {
    case .keyNotFound(let key, let context): return "\(path(context.codingPath + [key])) is missing"
    case .typeMismatch(_, let context), .valueNotFound(_, let context): return "\(path(context.codingPath)) has the wrong type"
    case .dataCorrupted(let context): return context.debugDescription
    @unknown default: return error.localizedDescription
    }
  }

  /// Trims names and ids, and tidies paths, so small slips don't become errors.
  func normalized() -> Architecture {
    var copy = self
    copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.walkthrough = walkthrough.map { step in
      var step = step
      step.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
      step.text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
      step.nodes = step.nodes.map { $0.trimmingCharacters(in: .whitespaces) }
      return step
    }
    copy.overview = overview.map { block in
      var block = block
      block.id = block.id.trimmingCharacters(in: .whitespaces)
      block.name = block.name.trimmingCharacters(in: .whitespacesAndNewlines)
      block.kind = block.kind.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.flatMap { $0.isEmpty ? nil : $0 }
      block.nodes = block.nodes.map { $0.trimmingCharacters(in: .whitespaces) }
      return block
    }
    copy.flows = flows.map { flow in
      var flow = flow
      flow.id = flow.id.trimmingCharacters(in: .whitespaces)
      flow.title = flow.title.trimmingCharacters(in: .whitespacesAndNewlines)
      flow.actor = flow.actor.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.flatMap { $0.isEmpty ? nil : $0 }
      flow.area = flow.area.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
      flow.steps = flow.steps.map { step in
        var step = step
        step.id = step.id.trimmingCharacters(in: .whitespaces)
        step.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
        step.kind = step.kind.trimmingCharacters(in: .whitespaces).lowercased()
        step.lane = step.lane.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        step.nodes = step.nodes.map { $0.trimmingCharacters(in: .whitespaces) }
        return step
      }
      return flow
    }
    copy.groups = groups.map { group in
      var group = group
      group.id = group.id.trimmingCharacters(in: .whitespaces)
      group.name = group.name.trimmingCharacters(in: .whitespaces)
      return group
    }
    copy.nodes = nodes.map { node in
      var node = node
      node.id = node.id.trimmingCharacters(in: .whitespaces)
      node.name = node.name.trimmingCharacters(in: .whitespaces)
      node.kind = node.kind.trimmingCharacters(in: .whitespaces).lowercased()
      node.group = node.group.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
      node.paths = node.paths.map(Architecture.normalize).filter { !$0.isEmpty }
      return node
    }
    copy.edges = edges.map { edge in
      var edge = edge
      edge.from = edge.from.trimmingCharacters(in: .whitespaces)
      edge.to = edge.to.trimmingCharacters(in: .whitespaces)
      edge.kind = edge.kind.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.flatMap { $0.isEmpty ? nil : $0 }
      edge.note = edge.note.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
      return edge
    }
    func trimmed(_ text: String?) -> String? {
      text.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    copy.entities = entities.map { entity in
      var entity = entity
      entity.id = entity.id.trimmingCharacters(in: .whitespaces)
      entity.name = entity.name.trimmingCharacters(in: .whitespaces)
      entity.store = trimmed(entity.store)
      entity.paths = entity.paths.map(Architecture.normalize).filter { !$0.isEmpty }
      entity.fields = entity.fields.map { field in
        var field = field
        field.name = field.name.trimmingCharacters(in: .whitespaces)
        field.type = trimmed(field.type)
        field.ref = trimmed(field.ref)
        field.key = field.key == true ? true : nil
        return field
      }
      return entity
    }
    copy.explainers = explainers.map { explainer in
      var explainer = explainer
      explainer.id = explainer.id.trimmingCharacters(in: .whitespaces)
      explainer.title = explainer.title.trimmingCharacters(in: .whitespacesAndNewlines)
      explainer.scenes = explainer.scenes.map { scene in
        var scene = scene
        scene.title = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        scene.text = scene.text.trimmingCharacters(in: .whitespacesAndNewlines)
        scene.nodes = scene.nodes.map { $0.trimmingCharacters(in: .whitespaces) }
        scene.flow = trimmed(scene.flow)
        scene.steps = scene.steps.map { $0.trimmingCharacters(in: .whitespaces) }
        scene.entities = scene.entities.map { $0.trimmingCharacters(in: .whitespaces) }
        return scene
      }
      return explainer
    }
    return copy
  }

  func validate(root: URL?) -> ValidationReport {
    var report = ValidationReport()
    let idPattern = #"^[a-z0-9][a-z0-9._-]*$"#
    func validID(_ id: String) -> Bool { id.range(of: idPattern, options: .regularExpression) != nil }

    if name.isEmpty { report.errors.append("Give the architecture a name.") }
    if nodes.isEmpty { report.errors.append("Add at least one component to nodes.") }

    var groupIDs = Set<String>()
    for group in groups {
      if !validID(group.id) { report.errors.append("Group id “\(group.id)” should be lowercase letters, numbers and dashes, like mac-app.") }
      if !groupIDs.insert(group.id).inserted { report.errors.append("Two groups have the id \(group.id).") }
      if group.name.isEmpty { report.errors.append("Group \(group.id) needs a name.") }
    }

    var nodeIDs = Set<String>()
    let kinds = NodeKind.allCases.map(\.rawValue).joined(separator: ", ")
    for node in nodes {
      if !validID(node.id) { report.errors.append("Component id “\(node.id)” should be lowercase letters, numbers and dashes, like app-store.") }
      if !nodeIDs.insert(node.id).inserted { report.errors.append("Two components have the id \(node.id).") }
      if node.name.isEmpty { report.errors.append("Component \(node.id) needs a name.") }
      if NodeKind(rawValue: node.kind) == nil { report.errors.append("Component \(node.id) has kind “\(node.kind)”. Use one of: \(kinds).") }
      if let group = node.group, !groupIDs.contains(group) { report.errors.append("Component \(node.id) is in group \(group), which isn't in groups.") }
      if (node.summary ?? "").isEmpty { report.warnings.append("Component \(node.id) has no summary, so clicking it won't say what it does.") }
      if node.details.count > 4 { report.warnings.append("Component \(node.id) has \(node.details.count) details. Keep it to 4 short ones.") }
      if let root {
        for path in node.paths where !FileManager.default.fileExists(atPath: root.appending(path: path).path) {
          report.warnings.append("Component \(node.id) lists \(path), which doesn't exist in \(root.path).")
        }
      }
    }

    var pairs = Set<String>()
    let edgeKinds = EdgeKind.allCases.map(\.rawValue).joined(separator: ", ")
    for edge in edges {
      if !nodeIDs.contains(edge.from) { report.errors.append("A connection starts at \(edge.from), which isn't a component.") }
      if !nodeIDs.contains(edge.to) { report.errors.append("A connection ends at \(edge.to), which isn't a component.") }
      if edge.from == edge.to { report.errors.append("Component \(edge.from) connects to itself. Leave that connection out.") }
      if !pairs.insert(edge.id).inserted {
        report.errors.append("There are two connections from \(edge.from) to \(edge.to). Merge them into one, with a label that covers both.")
      }
      if let kind = edge.kind, EdgeKind(rawValue: kind) == nil {
        report.errors.append("The connection from \(edge.from) to \(edge.to) has kind “\(kind)”. Use one of: \(edgeKinds).")
      }
    }
    if hasFewNotes {
      let without = edges.filter { ($0.note ?? "").isEmpty }.count
      report.warnings.append("\(without) of \(edges.count) connections have no note, so the technical view can't say what travels over them: run blueprint guide to see how.")
    }

    var blockIDs = Set<String>()
    var covered: [String: String] = [:]
    for block in overview {
      let name = block.name.isEmpty ? block.id : "“\(block.name)”"
      if !validID(block.id) { report.errors.append("Overview block id “\(block.id)” should be lowercase letters, numbers and dashes, like your-app.") }
      if !blockIDs.insert(block.id).inserted { report.errors.append("Two overview blocks have the id \(block.id).") }
      if block.name.isEmpty { report.errors.append("Overview block \(block.id) needs a name.") }
      if let kind = block.kind, NodeKind(rawValue: kind) == nil { report.errors.append("Overview block \(name) has kind “\(kind)”. Use one of: \(kinds).") }
      if block.nodes.isEmpty { report.errors.append("Overview block \(name) lists no components. Give it the components it stands for.") }
      for id in block.nodes {
        if !nodeIDs.contains(id) {
          report.errors.append("Overview block \(name) lists \(id), which isn't a component.")
        } else if let other = covered[id], other != block.id {
          report.errors.append("Component \(id) is in overview blocks \(other) and \(block.id). Put it in one.")
        } else {
          covered[id] = block.id
        }
      }
      if (block.summary ?? "").isEmpty { report.warnings.append("Overview block \(name) has no summary, so the overview can't say what it does.") }
    }
    if overview.isEmpty, nodes.count > 1 {
      report.warnings.append("There's no overview. Add 3 to 6 blocks that explain the app in plain words: run blueprint guide to see how.")
    } else if overview.count > 7 {
      report.warnings.append("The overview has \(overview.count) blocks. Keep it to 6 or fewer, so it stays simple.")
    }

    for (index, step) in walkthrough.enumerated() {
      if step.title.isEmpty { report.errors.append("Walkthrough step \(index + 1) needs a title.") }
      for id in step.nodes where !nodeIDs.contains(id) {
        report.errors.append("Walkthrough step \(index + 1) lists \(id), which isn't a component.")
      }
      if step.nodes.isEmpty { report.warnings.append("Walkthrough step \(index + 1) lists no components, so there's nothing to highlight.") }
    }
    if walkthrough.isEmpty, nodes.count > 1 {
      report.warnings.append("There's no walkthrough. Add 3 to 6 steps that show a newcomer how the app works: run blueprint guide to see how.")
    } else if walkthrough.count > 7 {
      report.warnings.append("The walkthrough has \(walkthrough.count) steps. Keep it to 6 or fewer, so it stays quick to follow.")
    }

    var flowIDs = Set<String>()
    let stepKinds = StepKind.allCases.map(\.rawValue).joined(separator: ", ")
    for flow in flows {
      let name = flow.title.isEmpty ? flow.id : "“\(flow.title)”"
      if !validID(flow.id) { report.errors.append("Flow id “\(flow.id)” should be lowercase letters, numbers and dashes, like write-a-note.") }
      if !flowIDs.insert(flow.id).inserted { report.errors.append("Two flows have the id \(flow.id).") }
      if flow.title.isEmpty { report.errors.append("Flow \(flow.id) needs a title.") }
      if flow.steps.count < 2 { report.errors.append("Flow \(name) needs at least 2 steps.") }
      if flow.steps.count > 12 { report.warnings.append("Flow \(name) has \(flow.steps.count) steps. Split it, or keep it to 12 or fewer.") }
      if (flow.goal ?? "").isEmpty { report.warnings.append("Flow \(name) has no goal, so people can't tell what need it covers.") }
      if let actor = flow.actor {
        if FlowActor(rawValue: actor) == nil {
          report.errors.append("Flow \(name) has actor “\(actor)”. Use one of: \(FlowActor.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
      } else {
        report.warnings.append("Flow \(name) has no actor. Say whose workflow it is: user, owner, agent or app.")
      }
      if flow.area == nil { report.warnings.append("Flow \(name) has no area, so it can't be grouped with the flows of the same part of the app.") }
      var stepIDs = Set<String>()
      for step in flow.steps {
        if step.id.isEmpty { report.errors.append("A step in flow \(name) has no id.") }
        if !stepIDs.insert(step.id).inserted { report.errors.append("Flow \(name) has two steps with the id \(step.id).") }
        if step.title.isEmpty { report.errors.append("Step \(step.id) in flow \(name) needs a title.") }
        if StepKind(rawValue: step.kind) == nil { report.errors.append("Step \(step.id) in flow \(name) has kind “\(step.kind)”. Use one of: \(stepKinds).") }
        for id in step.nodes where !nodeIDs.contains(id) {
          report.errors.append("Step \(step.id) in flow \(name) lists \(id), which isn't a component.")
        }
      }
      for step in flow.steps {
        for link in step.next where !stepIDs.contains(link.to) {
          report.errors.append("Step \(step.id) in flow \(name) goes to \(link.to), which isn't a step of that flow.")
        }
        if step.stepKind == .decision, step.next.count < 2 {
          report.warnings.append("Step \(step.id) in flow \(name) is a decision, so give it 2 or more next links, each with a label.")
        }
      }
      if flow.lanes.count > 4 { report.warnings.append("Flow \(name) has \(flow.lanes.count) lanes. Keep it to 4: who acts, not every part involved.") }
    }
    if flows.isEmpty, nodes.count > 1 {
      report.warnings.append("There are no flows. Map every workflow of the app, from users, the owner, agents and the app itself: run blueprint guide to see how.")
    } else if hasFewFlows {
      report.warnings.append("There are only \(flows.count) flows. Map every workflow, not only the main ones: what users, the owner and agents do, and what the app does on its own. Most apps have 8 or more.")
    }

    let entityIDs = Set(entities.map(\.id))
    var seenEntities = Set<String>()
    for entity in entities {
      if !validID(entity.id) { report.errors.append("Entity id “\(entity.id)” should be lowercase letters, numbers and dashes, like saved-note.") }
      if !seenEntities.insert(entity.id).inserted { report.errors.append("Two entities have the id \(entity.id).") }
      if entity.name.isEmpty { report.errors.append("Entity \(entity.id) needs a name.") }
      if let store = entity.store {
        if !nodeIDs.contains(store) { report.errors.append("Entity \(entity.id) is stored in \(store), which isn't a component.") }
      } else {
        report.warnings.append("Entity \(entity.id) has no store, so the app can't show where it lives.")
      }
      if (entity.summary ?? "").isEmpty { report.warnings.append("Entity \(entity.id) has no summary, so clicking it won't say what one record is.") }
      if entity.details.count > 4 { report.warnings.append("Entity \(entity.id) has \(entity.details.count) details. Keep it to 4 short ones.") }
      var fieldNames = Set<String>()
      for field in entity.fields {
        if field.name.isEmpty { report.errors.append("A field of entity \(entity.id) has no name.") }
        if !fieldNames.insert(field.name).inserted { report.errors.append("Entity \(entity.id) has two fields named \(field.name).") }
        if let ref = field.ref, !entityIDs.contains(ref) {
          report.errors.append("Field \(field.name) of entity \(entity.id) points to \(ref), which isn't an entity.")
        }
      }
      if let root {
        for path in entity.paths where !FileManager.default.fileExists(atPath: root.appending(path: path).path) {
          report.warnings.append("Entity \(entity.id) lists \(path), which doesn't exist in \(root.path).")
        }
      }
    }
    let stores = nodes.filter { $0.nodeKind == .database || $0.nodeKind == .storage }
    if entities.isEmpty, !stores.isEmpty {
      report.warnings.append("There's no data schema. Add the entities the app keeps in \(stores.map(\.name).joined(separator: ", ")): run blueprint guide to see how.")
    }

    var explainerIDs = Set<String>()
    for explainer in explainers {
      let name = explainer.title.isEmpty ? explainer.id : "“\(explainer.title)”"
      if !validID(explainer.id) { report.errors.append("Explainer id “\(explainer.id)” should be lowercase letters, numbers and dashes, like how-sync-works.") }
      if !explainerIDs.insert(explainer.id).inserted { report.errors.append("Two explainers have the id \(explainer.id).") }
      if explainer.title.isEmpty { report.errors.append("Explainer \(explainer.id) needs a title.") }
      if explainer.scenes.count < 2 { report.errors.append("Explainer \(name) needs at least 2 scenes.") }
      if explainer.scenes.count > 8 { report.warnings.append("Explainer \(name) has \(explainer.scenes.count) scenes. Keep it to 8, or split it in two.") }
      if (explainer.summary ?? "").isEmpty { report.warnings.append("Explainer \(name) has no summary, so people can't tell what it covers.") }
      for (index, scene) in explainer.scenes.enumerated() {
        let label = "Scene \(index + 1) of explainer \(name)"
        if scene.title.isEmpty { report.errors.append("\(label) needs a title.") }
        if scene.text.isEmpty { report.errors.append("\(label) needs a text.") }
        let words = scene.text.split(whereSeparator: \.isWhitespace).count
        if words > 30 { report.warnings.append("\(label) has \(words) words. Keep the text under 30, so it can be read before the next scene.") }
        let shows = [!scene.nodes.isEmpty, scene.flow != nil, !scene.entities.isEmpty].filter { $0 }.count
        if shows > 1 { report.errors.append("\(label) shows more than one thing. Give it components, a flow or entities, not several.") }
        for id in scene.nodes where !nodeIDs.contains(id) { report.errors.append("\(label) lists \(id), which isn't a component.") }
        for id in scene.entities where !entityIDs.contains(id) { report.errors.append("\(label) lists \(id), which isn't an entity.") }
        if let id = scene.flow {
          if let flow = flows.first(where: { $0.id == id }) {
            for step in scene.steps where flow.step(step) == nil { report.errors.append("\(label) lists step \(step), which isn't in flow \(id).") }
          } else {
            report.errors.append("\(label) shows flow \(id), which isn't a flow.")
          }
        } else if !scene.steps.isEmpty {
          report.errors.append("\(label) lists steps without a flow. Add the flow they belong to.")
        }
      }
    }
    if explainers.isEmpty, nodes.count > 1 {
      report.warnings.append("There are no explainers. Add 2 to 6 short videos about parts of the app: run blueprint guide to see how.")
    }

    let connected = Set(edges.flatMap { [$0.from, $0.to] })
    let lonely = nodes.map(\.id).filter { !connected.contains($0) }
    if nodes.count > 1, !lonely.isEmpty {
      report.warnings.append("\(lonely.joined(separator: ", ")) \(lonely.count == 1 ? "has" : "have") no connections.")
    }
    let used = Set(nodes.compactMap(\.group))
    for group in groups where !used.contains(group.id) {
      report.warnings.append("Group \(group.id) has no components.")
    }
    return report
  }
}
