// Lays out random architectures, with cycles, self-connections, empty groups and nodes without a group,
// random flows, and random data with self-references and entities without a store, and checks that
// every card is placed and no cards or boxes overlap.
// scripts/fuzz-layout.sh compiles it with the layout and its types.

import Foundation

@main
enum FuzzLayout {
  static func main() {
    var failures = 0
    for seed in 0..<400 {
      let groupCount = Int.random(in: 0...6)
      let groups = (0..<groupCount).map { Architecture.Group(id: "g\($0)", name: "Group \($0)") }
      let nodeCount = Int.random(in: 1...45)
      let nodes = (0..<nodeCount).map { index in
        Architecture.Node(
          id: "n\(index)", name: "Node \(index)", kind: NodeKind.allCases.randomElement()!.rawValue,
          group: groupCount == 0 || Int.random(in: 0..<4) == 0 ? nil : "g\(Int.random(in: 0..<groupCount))",
          summary: nil, tech: [], paths: []
        )
      }
      let edges = (0..<Int.random(in: 0...(nodeCount * 2))).map { _ in
        Architecture.Edge(from: "n\(Int.random(in: 0..<nodeCount))", to: "n\(Int.random(in: 0..<nodeCount))", label: nil, kind: nil)
      }
      let diagram = Diagram(architecture: Architecture(name: "Fuzz \(seed)", summary: nil, groups: groups, nodes: nodes, edges: edges))

      let frames = Array(diagram.layout.nodes.values)
      if frames.count != diagram.architecture.nodes.count {
        print("seed \(seed): placed \(frames.count) of \(diagram.architecture.nodes.count) cards")
        failures += 1
      }
      for i in frames.indices {
        for j in frames.indices where j > i && frames[i].insetBy(dx: 1, dy: 1).intersects(frames[j].insetBy(dx: 1, dy: 1)) {
          print("seed \(seed): two cards overlap")
          failures += 1
        }
      }
      for box in diagram.layout.boxes {
        for other in diagram.layout.boxes where other.id > box.id && box.frame.insetBy(dx: 1, dy: 1).intersects(other.frame.insetBy(dx: 1, dy: 1)) {
          print("seed \(seed): boxes \(box.id) and \(other.id) overlap")
          failures += 1
        }
      }
    }
    for seed in 0..<300 {
      let lanes = ["You", "App", "Agent", "Server", ""].shuffled().prefix(Int.random(in: 1...4))
      let count = Int.random(in: 2...12)
      let steps = (0..<count).map { index in
        Architecture.FlowStep(
          id: "s\(index)", title: "Step \(index)", kind: StepKind.allCases.randomElement()!.rawValue,
          lane: lanes.randomElement()!.isEmpty ? nil : lanes.randomElement()!,
          next: Int.random(in: 0..<4) == 0 ? (0..<Int.random(in: 1...3)).map { _ in Architecture.FlowLink(to: "s\(Int.random(in: 0..<count))") } : []
        )
      }
      let layout = FlowDiagramLayout(Architecture.Flow(id: "f", title: "Flow \(seed)", steps: steps))
      let frames = Array(layout.steps.values)
      if frames.count != steps.count {
        print("flow \(seed): placed \(frames.count) of \(steps.count) steps")
        failures += 1
      }
      for i in frames.indices {
        for j in frames.indices where j > i && frames[i].insetBy(dx: 1, dy: 1).intersects(frames[j].insetBy(dx: 1, dy: 1)) {
          print("flow \(seed): two steps overlap")
          failures += 1
        }
      }
    }
    for seed in 0..<300 {
      let stores = (0..<Int.random(in: 1...4)).map { index in
        Architecture.Node(id: "store\(index)", name: "Store \(index)", kind: "database", group: nil, summary: nil, tech: [], paths: [])
      }
      let count = Int.random(in: 1...30)
      let entities = (0..<count).map { index in
        Architecture.Entity(
          id: "e\(index)", name: "Entity \(index)",
          store: Int.random(in: 0..<6) == 0 ? nil : stores.randomElement()!.id,
          fields: (0..<Int.random(in: 0...16)).map { field in
            Architecture.Field(name: "f\(field)", ref: Int.random(in: 0..<4) == 0 ? "e\(Int.random(in: 0..<count))" : nil)
          }
        )
      }
      let architecture = Architecture(name: "Data \(seed)", summary: nil, groups: [], nodes: stores, edges: [], entities: entities)
      let layout = Diagram(architecture: architecture).dataLayout
      if layout.cards.count != count {
        print("data \(seed): placed \(layout.cards.count) of \(count) entities")
        failures += 1
      }
      let frames = Array(layout.cards.values)
      for i in frames.indices {
        for j in frames.indices where j > i && frames[i].insetBy(dx: 1, dy: 1).intersects(frames[j].insetBy(dx: 1, dy: 1)) {
          print("data \(seed): two entities overlap")
          failures += 1
        }
      }
      for box in layout.boxes {
        for other in layout.boxes where other.id > box.id && box.frame.insetBy(dx: 1, dy: 1).intersects(other.frame.insetBy(dx: 1, dy: 1)) {
          print("data \(seed): boxes \(box.id) and \(other.id) overlap")
          failures += 1
        }
      }
      for entity in entities {
        guard let frame = layout.cards[entity.id], let box = layout.boxes.first(where: { $0.id == (entity.store ?? "") }) else { continue }
        if !box.frame.contains(frame) {
          print("data \(seed): \(entity.id) is outside its box")
          failures += 1
        }
      }
      if layout.routes.count != layout.references.count {
        print("data \(seed): \(layout.references.count) references but \(layout.routes.count) routes")
        failures += 1
      }
    }
    print(failures == 0 ? "layout ok" : "\(failures) problems")
    exit(failures == 0 ? 0 : 1)
  }
}
