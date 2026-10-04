import SwiftUI

/// Places an architecture on the canvas. Each group is a box, and boxes sit in columns chosen so
/// connections stay short. Inside a box, components stack in the order their connections flow.
/// Connections that skip columns run through the gaps between boxes, never across them.
struct DiagramLayout {
  struct Box {
    var id: String
    var name: String
    var frame: CGRect
    var colorIndex: Int
  }

  struct Segment {
    var start: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var end: CGPoint

    func point(at t: CGFloat) -> CGPoint {
      let u = 1 - t
      let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
      return CGPoint(
        x: a * start.x + b * control1.x + c * control2.x + d * end.x,
        y: a * start.y + b * control1.y + c * control2.y + d * end.y
      )
    }

    /// A curve that leaves and arrives horizontally.
    static func curve(_ p: CGPoint, _ q: CGPoint, minimum: CGFloat = 40) -> Segment {
      let dx = q.x - p.x
      let bend = (dx >= 0 ? 1 : -1) * max(abs(dx) * 0.5, minimum)
      return Segment(start: p, control1: CGPoint(x: p.x + bend, y: p.y), control2: CGPoint(x: q.x - bend, y: q.y), end: q)
    }

    static func line(_ p: CGPoint, _ q: CGPoint) -> Segment {
      Segment(
        start: p,
        control1: CGPoint(x: p.x + (q.x - p.x) / 3, y: p.y + (q.y - p.y) / 3),
        control2: CGPoint(x: p.x + 2 * (q.x - p.x) / 3, y: p.y + 2 * (q.y - p.y) / 3),
        end: q
      )
    }
  }

  struct Route: Identifiable {
    var id: String
    var from: String
    var to: String
    var segments: [Segment]
    /// Where the label fits without covering a card or another label, if anywhere.
    var labelSpot: CGPoint?

    /// Changes when the number of segments does, so SwiftUI fades between shapes it can't morph.
    var shapeID: String { "\(id)#\(segments.count)" }

    var path: Path {
      Path { path in
        guard let first = segments.first else { return }
        path.move(to: first.start)
        for segment in segments {
          path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }
      }
    }

    /// Where the label goes: its free spot, or the middle of the first curve while highlighted.
    var labelPoint: CGPoint { labelSpot ?? segments.first?.point(at: 0.5) ?? .zero }

    /// The direction the curve arrives in, for the arrowhead.
    var arrival: CGVector {
      guard let last = segments.last else { return CGVector(dx: 1, dy: 0) }
      var dx = last.end.x - last.control2.x, dy = last.end.y - last.control2.y
      if abs(dx) + abs(dy) < 0.01 { dx = last.end.x - last.start.x; dy = last.end.y - last.start.y }
      let length = max(sqrt(dx * dx + dy * dy), 0.001)
      return CGVector(dx: dx / length, dy: dy / length)
    }
  }

  static let nodeSize = CGSize(width: 228, height: 68)
  static let maxRows = 8
  static let rowGap: CGFloat = 18
  static let subColumnGap: CGFloat = 40
  static let columnGap: CGFloat = 150
  static let boxGap: CGFloat = 56
  static let padding = (x: CGFloat(20), top: CGFloat(44), bottom: CGFloat(20))
  static let margin: CGFloat = 80

  var nodes: [String: CGRect] = [:]
  var boxes: [Box] = []
  var routes: [Route] = []
  var bounds: CGRect = .zero

  private struct Cluster {
    var id: String
    var group: Architecture.Group?
    var colorIndex: Int
    var columns: [[String]] = []
    var size: CGSize = .zero
    var origin: CGPoint = .zero

    var isBox: Bool { group != nil }
    var frame: CGRect { CGRect(origin: origin, size: size) }
  }

  init(_ architecture: Architecture) {
    let size = Self.nodeSize
    let groupIDs = Set(architecture.groups.map(\.id))

    // Every group with components becomes a cluster, and so does every component without a group.
    var clusters: [Cluster] = []
    var clusterOf: [String: Int] = [:]
    for (index, group) in architecture.groups.enumerated() {
      let members = architecture.nodes.filter { $0.group == group.id }.map(\.id)
      guard !members.isEmpty else { continue }
      for member in members { clusterOf[member] = clusters.count }
      var cluster = Cluster(id: group.id, group: group, colorIndex: index)
      cluster.columns = [members]
      clusters.append(cluster)
    }
    for node in architecture.nodes where node.group.map(groupIDs.contains) != true {
      clusterOf[node.id] = clusters.count
      var cluster = Cluster(id: "node:\(node.id)", group: nil, colorIndex: 0)
      cluster.columns = [[node.id]]
      clusters.append(cluster)
    }
    guard !clusters.isEmpty else { return }

    let edges = architecture.edges.filter { clusterOf[$0.from] != nil && clusterOf[$0.to] != nil && $0.from != $0.to }
    var neighbors: [String: [String]] = [:]
    for edge in edges {
      neighbors[edge.from, default: []].append(edge.to)
      neighbors[edge.to, default: []].append(edge.from)
    }

    // Columns of clusters, placed where connections are shortest.
    var weights: [Int: [Int: Int]] = [:]
    for edge in edges {
      let a = clusterOf[edge.from]!, b = clusterOf[edge.to]!
      if a != b { weights[a, default: [:]][b, default: 0] += 1 }
    }
    let clusterEdges = weights.flatMap { a, targets in targets.map { (a, $0.key, $0.value) } }
    var clusterRanks = Self.rank(count: clusters.count, edges: clusterEdges.map { ($0.0, $0.1) })
    Self.shorten(&clusterRanks, edges: clusterEdges)
    clusterRanks = Self.compact(clusterRanks)
    var columns: [[Int]] = Array(repeating: [], count: (clusterRanks.max() ?? 0) + 1)
    for index in clusters.indices { columns[clusterRanks[index]].append(index) }

    // Inside a box, components stack in the order their connections flow, wrapping past maxRows.
    var innerRank: [String: Int] = [:]
    for index in clusters.indices where clusters[index].isBox {
      let members = clusters[index].columns[0]
      let position = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($1, $0) })
      let inside = edges.compactMap { edge -> (Int, Int)? in
        guard let a = position[edge.from], let b = position[edge.to] else { return nil }
        return (a, b)
      }
      let ranks = Self.rank(count: members.count, edges: inside)
      for (offset, member) in members.enumerated() { innerRank[member] = ranks[offset] }
      let ordered = members.enumerated().sorted { (ranks[$0.offset], $0.offset) < (ranks[$1.offset], $1.offset) }.map(\.element)
      let count = Int((Double(ordered.count) / Double(Self.maxRows)).rounded(.up))
      let rows = Int((Double(ordered.count) / Double(count)).rounded(.up))
      clusters[index].columns = stride(from: 0, to: ordered.count, by: rows).map { Array(ordered[$0..<min($0 + rows, ordered.count)]) }
    }

    for index in clusters.indices {
      let cluster = clusters[index]
      let rows = CGFloat(cluster.columns.map(\.count).max() ?? 1)
      let cols = CGFloat(cluster.columns.count)
      let inner = CGSize(
        width: cols * size.width + (cols - 1) * Self.subColumnGap,
        height: rows * size.height + (rows - 1) * Self.rowGap
      )
      clusters[index].size = cluster.isBox
        ? CGSize(width: inner.width + 2 * Self.padding.x, height: inner.height + Self.padding.top + Self.padding.bottom)
        : inner
    }

    func localCenter(_ id: String, in cluster: Cluster) -> CGPoint {
      let rows = cluster.columns.map(\.count).max() ?? 1
      for (col, column) in cluster.columns.enumerated() {
        guard let row = column.firstIndex(of: id) else { continue }
        let inset = cluster.isBox ? CGPoint(x: Self.padding.x, y: Self.padding.top) : .zero
        let shift = CGFloat(rows - column.count) * (size.height + Self.rowGap) / 2
        return CGPoint(
          x: inset.x + CGFloat(col) * (size.width + Self.subColumnGap) + size.width / 2,
          y: inset.y + shift + CGFloat(row) * (size.height + Self.rowGap) + size.height / 2
        )
      }
      return .zero
    }

    func center(_ id: String) -> CGPoint {
      guard let index = clusterOf[id] else { return .zero }
      let local = localCenter(id, in: clusters[index])
      return CGPoint(x: clusters[index].origin.x + local.x, y: clusters[index].origin.y + local.y)
    }

    // Column x positions, then a first vertical stack.
    var columnSpans: [ClosedRange<CGFloat>] = []
    var x: CGFloat = 0
    for column in columns {
      let width = column.map { clusters[$0].size.width }.max() ?? 0
      var y: CGFloat = -(column.map { clusters[$0].size.height }.reduce(0, +) + CGFloat(max(column.count - 1, 0)) * Self.boxGap) / 2
      for index in column {
        clusters[index].origin = CGPoint(x: x + (width - clusters[index].size.width) / 2, y: y)
        y += clusters[index].size.height + Self.boxGap
      }
      columnSpans.append(x...(x + width))
      x += width + Self.columnGap
    }

    // Sweep back and forth, moving components and boxes toward what they connect to.
    // Inside a box, a component never moves above one its connections flow from.
    for iteration in 0..<8 {
      let order = iteration % 2 == 0 ? Array(columns.indices) : columns.indices.reversed()
      for col in order {
        for index in columns[col] {
          for sub in clusters[index].columns.indices {
            let current = clusters[index].columns[sub]
            let keys = Dictionary(uniqueKeysWithValues: current.map { id -> (String, CGFloat) in
              let others = (neighbors[id] ?? []).filter { clusterOf[$0] != index }
              guard !others.isEmpty else { return (id, center(id).y) }
              return (id, others.map { center($0).y }.reduce(0, +) / CGFloat(others.count))
            })
            clusters[index].columns[sub] = current.enumerated()
              .sorted { (innerRank[$0.element] ?? 0, keys[$0.element]!, $0.offset) < (innerRank[$1.element] ?? 0, keys[$1.element]!, $1.offset) }
              .map(\.element)
          }
        }

        // Each box wants the top that lines its components up with their neighbors outside it.
        var desired: [Int: CGFloat] = [:]
        for index in columns[col] {
          var pulls: [CGFloat] = []
          for column in clusters[index].columns {
            for id in column {
              let local = localCenter(id, in: clusters[index]).y
              for other in neighbors[id] ?? [] where clusterOf[other] != index {
                pulls.append(center(other).y - local)
              }
            }
          }
          desired[index] = pulls.isEmpty ? clusters[index].origin.y : pulls.reduce(0, +) / CGFloat(pulls.count)
        }
        let sorted = columns[col].enumerated()
          .sorted { (desired[$0.element]!, $0.offset) < (desired[$1.element]!, $1.offset) }
          .map(\.element)
        columns[col] = sorted

        var tops: [CGFloat] = []
        for (position, index) in sorted.enumerated() {
          var top = desired[index]!
          if position > 0 {
            let previous = sorted[position - 1]
            top = max(top, tops[position - 1] + clusters[previous].size.height + Self.boxGap)
          }
          tops.append(top)
        }
        let drift = zip(sorted, tops).map { $1 - desired[$0]! }.reduce(0, +) / CGFloat(max(sorted.count, 1))
        for (position, index) in sorted.enumerated() {
          clusters[index].origin.y = tops[position] - drift
        }
      }
    }

    // Shift everything so the diagram starts at the margin.
    let raw = clusters.map(\.frame).reduce(clusters[0].frame) { $0.union($1) }
    let shift = CGPoint(x: Self.margin - raw.minX, y: Self.margin - raw.minY)
    for index in clusters.indices {
      clusters[index].origin.x += shift.x
      clusters[index].origin.y += shift.y
    }
    columnSpans = columnSpans.map { ($0.lowerBound + shift.x)...($0.upperBound + shift.x) }

    for cluster in clusters {
      for column in cluster.columns {
        for id in column {
          let c = center(id)
          nodes[id] = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
        }
      }
      if let group = cluster.group {
        boxes.append(Box(id: group.id, name: group.name, frame: cluster.frame, colorIndex: cluster.colorIndex))
      }
    }

    let router = Router(
      nodes: nodes,
      clusterOf: clusterOf,
      columnOf: Dictionary(uniqueKeysWithValues: clusters.indices.map { ($0, clusterRanks[$0]) }),
      clusterFrames: clusters.map(\.frame),
      columns: columns.enumerated().map { col, members in
        (span: columnSpans[col], obstacles: members.map { clusters[$0].frame }.sorted { $0.minY < $1.minY })
      }
    )
    routes = router.route(edges)
    bounds = raw.offsetBy(dx: shift.x, dy: shift.y).insetBy(dx: -Self.margin, dy: -Self.margin)
  }

  // MARK: Ranking

  /// Longest-path layers, after dropping the connections that close a cycle.
  static func rank(count: Int, edges: [(Int, Int)]) -> [Int] {
    guard count > 0 else { return [] }
    var out = Array(repeating: [Int](), count: count)
    for (a, b) in edges where !out[a].contains(b) { out[a].append(b) }

    var state = Array(repeating: 0, count: count)
    var dag = Array(repeating: [Int](), count: count)
    var finished: [Int] = []
    func visit(_ v: Int) {
      state[v] = 1
      for w in out[v] where state[w] != 1 {
        dag[v].append(w)
        if state[w] == 0 { visit(w) }
      }
      state[v] = 2
      finished.append(v)
    }
    for v in 0..<count where state[v] == 0 { visit(v) }

    var rank = Array(repeating: 0, count: count)
    for v in finished.reversed() {
      for w in dag[v] { rank[w] = max(rank[w], rank[v] + 1) }
    }
    return compact(rank)
  }

  /// Moves clusters between columns while that makes the connections shorter overall.
  /// A connection one column long costs nothing, a longer one costs a step per extra column,
  /// one inside a column costs a step and a half, and one pointing back costs the most.
  static func shorten(_ rank: inout [Int], edges: [(Int, Int, Int)]) {
    func cost(_ span: Int, _ weight: Int) -> Double {
      if span >= 1 { return Double((span - 1) * weight) }
      if span == 0 { return 1.5 * Double(weight) }
      return Double(weight) * (2.5 + Double(-span))
    }
    var incident = Array(repeating: [(other: Int, weight: Int, outgoing: Bool)](), count: rank.count)
    for (a, b, weight) in edges {
      incident[a].append((b, weight, true))
      incident[b].append((a, weight, false))
    }
    for _ in 0..<16 {
      var improved = false
      for cluster in rank.indices where !incident[cluster].isEmpty {
        func total(_ r: Int) -> Double {
          incident[cluster].reduce(0) { sum, link in
            sum + cost(link.outgoing ? rank[link.other] - r : r - rank[link.other], link.weight)
          }
        }
        var best = (rank: rank[cluster], cost: total(rank[cluster]))
        for r in 0...((rank.max() ?? 0) + 1) where r != rank[cluster] {
          let value = total(r)
          if value < best.cost - 0.01 { best = (r, value) }
        }
        if best.rank != rank[cluster] {
          rank[cluster] = best.rank
          improved = true
        }
      }
      if !improved { break }
    }
  }

  static func compact(_ rank: [Int]) -> [Int] {
    let used = Array(Set(rank)).sorted()
    let index = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($1, $0) })
    return rank.map { index[$0]! }
  }
}

// MARK: - Routing

private enum Side: Hashable { case left, right, top, bottom }

/// Turns connections into curves. Connections between neighboring columns are one curve.
/// Longer ones run straight through the gaps between the boxes of each column they cross,
/// bundled side by side, and curves in the space between columns join the runs.
private struct Router {
  let nodes: [String: CGRect]
  let clusterOf: [String: Int]
  let columnOf: [Int: Int]
  let clusterFrames: [CGRect]
  let columns: [(span: ClosedRange<CGFloat>, obstacles: [CGRect])]

  private struct Pass {
    var column: Int
    var lane: Int
    var y: CGFloat
    var offset: CGFloat = 0
  }

  private struct Plan {
    var edge: Architecture.Edge
    var startSide: Side
    var endSide: Side
    var passes: [Pass] = []
    var bulge: CGFloat = 0
    var start: CGPoint = .zero
    var end: CGPoint = .zero

    func side(_ isStart: Bool) -> Side { isStart ? startSide : endSide }
  }

  func route(_ edges: [Architecture.Edge]) -> [DiagramLayout.Route] {
    var plans = edges.map(plan)

    // Arcs within a column go on the side of it that fewer other connections use.
    var load: [String: Int] = [:]
    for plan in plans where plan.startSide != plan.endSide {
      for (node, side) in [(plan.edge.from, plan.startSide), (plan.edge.to, plan.endSide)] where side == .left || side == .right {
        load["\(columnOf[clusterOf[node]!]!)|\(side)", default: 0] += 1
      }
    }
    for index in plans.indices where plans[index].startSide == plans[index].endSide {
      let column = columnOf[clusterOf[plans[index].edge.from]!]!
      let left = load["\(column)|\(Side.left)"] ?? 0, right = load["\(column)|\(Side.right)"] ?? 0
      let side: Side = left < right || (left == right && column == 0) ? .left : .right
      plans[index].startSide = side
      plans[index].endSide = side
    }

    // Arcs on the same side of a column nest: short ones inside, long ones outside.
    var arcs: [String: [Int]] = [:]
    for (index, plan) in plans.enumerated() where plan.startSide == plan.endSide {
      let column = columnOf[clusterOf[plan.edge.from]!]!
      arcs["\(column)|\(plan.startSide)", default: []].append(index)
    }
    for list in arcs.values {
      let sorted = list.sorted { span(plans[$0]) < span(plans[$1]) }
      for (order, index) in sorted.enumerated() { plans[index].bulge = 30 + CGFloat(order) * 12 }
    }

    // Spread the connections that share a card edge, ordered by where they head, so they don't cross.
    var ends: [String: [(plan: Int, isStart: Bool, toward: CGPoint)]] = [:]
    for (index, plan) in plans.enumerated() {
      let source = nodes[plan.edge.from]!, target = nodes[plan.edge.to]!
      let firstStop = plan.passes.first.map { CGPoint(x: source.midX, y: $0.y) } ?? CGPoint(x: target.midX, y: target.midY)
      let lastStop = plan.passes.last.map { CGPoint(x: target.midX, y: $0.y) } ?? CGPoint(x: source.midX, y: source.midY)
      ends["\(plan.edge.from)|\(plan.startSide)", default: []].append((index, true, firstStop))
      ends["\(plan.edge.to)|\(plan.endSide)", default: []].append((index, false, lastStop))
    }
    for (key, list) in ends {
      let parts = key.split(separator: "|")
      let frame = nodes[String(parts[0])]!
      let side = plans[list[0].plan].side(list[0].isStart)
      let vertical = side == .left || side == .right
      let sorted = list.sorted { vertical ? $0.toward.y < $1.toward.y : $0.toward.x < $1.toward.x }
      let span = vertical ? frame.height - 24 : frame.width - 60
      let spacing = sorted.count > 1 ? min(vertical ? 12 : 24, span / CGFloat(sorted.count - 1)) : 0
      for (i, end) in sorted.enumerated() {
        let offset = (CGFloat(i) - CGFloat(sorted.count - 1) / 2) * spacing
        let point: CGPoint = switch side {
        case .left: CGPoint(x: frame.minX, y: frame.midY + offset)
        case .right: CGPoint(x: frame.maxX, y: frame.midY + offset)
        case .top: CGPoint(x: frame.midX + offset, y: frame.minY)
        case .bottom: CGPoint(x: frame.midX + offset, y: frame.maxY)
        }
        if end.isStart { plans[end.plan].start = point } else { plans[end.plan].end = point }
      }
    }

    // Connections through the same gap run side by side, in the order they arrive.
    var lanes: [String: [(plan: Int, pass: Int)]] = [:]
    for (index, plan) in plans.enumerated() {
      for (p, pass) in plan.passes.enumerated() { lanes["\(pass.column)|\(pass.lane)", default: []].append((index, p)) }
    }
    for list in lanes.values where list.count > 1 {
      let sorted = list.sorted { a, b in
        let ya = a.pass == 0 ? plans[a.plan].start.y : plans[a.plan].passes[a.pass - 1].y
        let yb = b.pass == 0 ? plans[b.plan].start.y : plans[b.plan].passes[b.pass - 1].y
        return ya < yb
      }
      let spacing = min(8, (DiagramLayout.boxGap - 16) / CGFloat(sorted.count - 1))
      for (i, item) in sorted.enumerated() {
        plans[item.plan].passes[item.pass].offset = (CGFloat(i) - CGFloat(sorted.count - 1) / 2) * spacing
      }
    }

    var routes = plans.map { plan in
      DiagramLayout.Route(id: plan.edge.id, from: plan.edge.from, to: plan.edge.to, segments: segments(plan))
    }
    placeLabels(&routes, edges: edges)
    return routes
  }

  /// Finds each label a spot along its connection that covers no card and no other label.
  /// A label that finds none only shows while its connection is highlighted.
  private func placeLabels(_ routes: inout [DiagramLayout.Route], edges: [Architecture.Edge]) {
    var taken = nodes.values.map { $0.insetBy(dx: -4, dy: -4) }
    for (index, edge) in edges.enumerated() {
      guard let label = edge.label, !label.isEmpty else { continue }
      let size = CGSize(width: CGFloat(label.count) * 5.9 + 18, height: 20)
      let spots = routes[index].segments.flatMap { segment in
        [0.5, 0.38, 0.62, 0.26, 0.74].map { segment.point(at: $0) }
      }
      for spot in spots {
        let rect = CGRect(x: spot.x - size.width / 2, y: spot.y - size.height / 2, width: size.width, height: size.height)
        if !taken.contains(where: { $0.intersects(rect) }) {
          routes[index].labelSpot = spot
          taken.append(rect.insetBy(dx: -3, dy: -2))
          break
        }
      }
    }
  }

  private func span(_ plan: Plan) -> CGFloat {
    abs(nodes[plan.edge.to]!.midY - nodes[plan.edge.from]!.midY)
  }

  private func plan(_ edge: Architecture.Edge) -> Plan {
    let s = nodes[edge.from]!, t = nodes[edge.to]!
    let sourceCluster = clusterOf[edge.from]!, targetCluster = clusterOf[edge.to]!
    let a = columnOf[sourceCluster]!, b = columnOf[targetCluster]!

    if a != b {
      let forward = a < b
      var plan = Plan(edge: edge, startSide: forward ? .right : .left, endSide: forward ? .left : .right)
      let crossed = forward ? Array((a + 1)..<b) : Array(((b + 1)..<a).reversed())
      for column in crossed {
        let middle = (columns[column].span.lowerBound + columns[column].span.upperBound) / 2
        let progress = (middle - s.midX) / (t.midX - s.midX)
        let wanted = s.midY + (t.midY - s.midY) * progress
        let lanes = laneCenters(column)
        let best = lanes.indices.min { abs(lanes[$0] - wanted) < abs(lanes[$1] - wanted) } ?? 0
        plan.passes.append(Pass(column: column, lane: best, y: lanes[best]))
      }
      return plan
    }

    // In the same column: straight down or up to a neighbor, or an arc past what's in between.
    if sourceCluster == targetCluster, t.minX >= s.maxX + 12 {
      return Plan(edge: edge, startSide: .right, endSide: .left)
    }
    if sourceCluster == targetCluster, t.maxX <= s.minX - 12 {
      return Plan(edge: edge, startSide: .left, endSide: .right)
    }
    let between = CGRect(x: min(s.minX, t.minX), y: min(s.maxY, t.maxY), width: max(s.maxX, t.maxX) - min(s.minX, t.minX), height: abs(t.midY - s.midY) - s.height)
    let blocked = between.height > 0 && (
      nodes.contains { id, frame in id != edge.from && id != edge.to && frame.intersects(between) }
        || clusterFrames.indices.contains { $0 != sourceCluster && $0 != targetCluster && clusterFrames[$0].intersects(between) }
    )
    if blocked || (sourceCluster != targetCluster && between.height <= 0) {
      return Plan(edge: edge, startSide: .right, endSide: .right)
    }
    return t.midY > s.midY ? Plan(edge: edge, startSide: .bottom, endSide: .top) : Plan(edge: edge, startSide: .top, endSide: .bottom)
  }

  /// The y of each way through a column: above its first box, between boxes, and below its last.
  private func laneCenters(_ column: Int) -> [CGFloat] {
    let obstacles = columns[column].obstacles
    guard let first = obstacles.first, let last = obstacles.last else { return [0] }
    var lanes = [first.minY - DiagramLayout.boxGap / 2]
    for (upper, lower) in zip(obstacles, obstacles.dropFirst()) { lanes.append((upper.maxY + lower.minY) / 2) }
    lanes.append(last.maxY + DiagramLayout.boxGap / 2)
    return lanes
  }

  private func segments(_ plan: Plan) -> [DiagramLayout.Segment] {
    let start = plan.start, end = plan.end
    if plan.startSide == plan.endSide {
      let direction: CGFloat = plan.startSide == .left ? -1 : 1
      let bulge = direction * (plan.bulge + abs(end.y - start.y) * 0.08)
      return [DiagramLayout.Segment(start: start, control1: CGPoint(x: start.x + bulge, y: start.y), control2: CGPoint(x: end.x + bulge, y: end.y), end: end)]
    }
    switch plan.startSide {
    case .bottom, .top:
      let direction: CGFloat = plan.startSide == .bottom ? 1 : -1
      let dy = direction * max(abs(end.y - start.y) * 0.5, 24)
      return [DiagramLayout.Segment(start: start, control1: CGPoint(x: start.x, y: start.y + dy), control2: CGPoint(x: end.x, y: end.y - dy), end: end)]
    case .left, .right:
      guard !plan.passes.isEmpty else { return [.curve(start, end, minimum: plan.startSide == .right ? 40 : 60)] }
      let forward = plan.startSide == .right
      var points: [(CGPoint, CGPoint)] = []
      for pass in plan.passes {
        let span = columns[pass.column].span
        let y = pass.y + pass.offset
        let entry = CGPoint(x: (forward ? span.lowerBound : span.upperBound) + (forward ? -18 : 18), y: y)
        let exit = CGPoint(x: (forward ? span.upperBound : span.lowerBound) + (forward ? 18 : -18), y: y)
        points.append((entry, exit))
      }
      var result: [DiagramLayout.Segment] = []
      var cursor = start
      for (entry, exit) in points {
        result.append(.curve(cursor, entry, minimum: 30))
        result.append(.line(entry, exit))
        cursor = exit
      }
      result.append(.curve(cursor, end, minimum: 30))
      return result
    }
  }
}

// MARK: - Right angles

extension DiagramLayout.Segment {
  /// The curve as straight runs that turn at right angles, keeping the way it leaves and the way it arrives.
  var elbow: [CGPoint] {
    let leavesSideways = abs(control1.x - start.x) >= abs(control1.y - start.y)
    let arrivesSideways = abs(end.x - control2.x) >= abs(end.y - control2.y)
    switch (leavesSideways, arrivesSideways) {
    case (true, true):
      let x = (control1.x + control2.x) / 2
      return [start, CGPoint(x: x, y: start.y), CGPoint(x: x, y: end.y), end]
    case (false, false):
      let y = (control1.y + control2.y) / 2
      return [start, CGPoint(x: start.x, y: y), CGPoint(x: end.x, y: y), end]
    case (true, false):
      return [start, CGPoint(x: end.x, y: start.y), end]
    case (false, true):
      return [start, CGPoint(x: start.x, y: end.y), end]
    }
  }
}

extension DiagramLayout.Route {
  /// Where a right-angle drawing of the route turns, from start to end.
  var corners: [CGPoint] {
    var points: [CGPoint] = []
    for segment in segments {
      for point in segment.elbow where points.last.map({ abs($0.x - point.x) + abs($0.y - point.y) > 0.5 }) ?? true {
        points.append(point)
      }
    }
    return points
  }

  /// The direction of the last straight run, for the arrowhead.
  var cornerArrival: CGVector {
    let points = corners
    guard points.count >= 2 else { return arrival }
    let a = points[points.count - 2], b = points[points.count - 1]
    let length = max(hypot(b.x - a.x, b.y - a.y), 0.001)
    return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
  }
}