import SwiftUI

/// Places a flow as a flowchart: steps go top to bottom in the order they happen,
/// in one column per actor, and the branches of a decision sit side by side in their column.
struct FlowDiagramLayout {
  struct Lane: Identifiable {
    var id: String { name }
    var name: String
    var frame: CGRect
    var colorIndex: Int
  }

  static let cardSize = CGSize(width: 228, height: 92)
  static let rowGap: CGFloat = 48
  static let branchGap: CGFloat = 20
  static let laneGap: CGFloat = 16
  static let lanePadding: CGFloat = 18
  static let header: CGFloat = 52
  static let margin: CGFloat = 60

  var steps: [String: CGRect] = [:]
  var lanes: [Lane] = []
  var routes: [DiagramLayout.Route] = []
  var bounds: CGRect = .zero

  init(_ flow: Architecture.Flow) {
    let size = Self.cardSize
    var seen = Set<String>()
    let steps = flow.steps.filter { seen.insert($0.id).inserted }
    guard !steps.isEmpty else { return }
    let index = Dictionary(uniqueKeysWithValues: steps.enumerated().map { ($1.id, $0) })

    var links: [(from: Int, to: Int, label: String?)] = []
    for (position, step) in steps.enumerated() {
      for link in flow.next(step) {
        guard let target = index[link.to], target != position else { continue }
        links.append((position, target, link.label))
      }
    }
    let ranks = DiagramLayout.rank(count: steps.count, edges: links.map { ($0.from, $0.to) })

    let laneNames = flow.lanes
    let laneOf = steps.map { laneNames.firstIndex(of: $0.lane ?? "") ?? 0 }
    var cells: [String: [Int]] = [:]
    for position in steps.indices { cells["\(ranks[position])|\(laneOf[position])", default: []].append(position) }
    let branches = laneNames.indices.map { lane in
      max(1, cells.filter { $0.key.hasSuffix("|\(lane)") }.map(\.value.count).max() ?? 1)
    }

    let rows = (ranks.max() ?? 0) + 1
    let height = Self.header + CGFloat(rows) * size.height + CGFloat(rows - 1) * Self.rowGap + Self.lanePadding
    var left: CGFloat = 0
    var laneLefts: [CGFloat] = []
    for (lane, name) in laneNames.enumerated() {
      let width = CGFloat(branches[lane]) * size.width + CGFloat(branches[lane] - 1) * Self.branchGap + 2 * Self.lanePadding
      laneLefts.append(left)
      lanes.append(Lane(name: name, frame: CGRect(x: left, y: 0, width: width, height: height), colorIndex: lane))
      left += width + Self.laneGap
    }

    for (key, members) in cells {
      let parts = key.split(separator: "|")
      let rank = Int(parts[0])!, lane = Int(parts[1])!
      let shift = CGFloat(branches[lane] - members.count) * (size.width + Self.branchGap) / 2
      for (column, position) in members.enumerated() {
        let x = laneLefts[lane] + Self.lanePadding + shift + CGFloat(column) * (size.width + Self.branchGap)
        let y = Self.header + CGFloat(rank) * (size.height + Self.rowGap)
        self.steps[steps[position].id] = CGRect(x: x, y: y, width: size.width, height: size.height)
      }
    }

    // Shift everything so it starts at the margin.
    let offset = Self.margin
    for (id, frame) in self.steps { self.steps[id] = frame.offsetBy(dx: offset, dy: offset) }
    lanes = lanes.map { lane in
      var lane = lane
      lane.frame = lane.frame.offsetBy(dx: offset, dy: offset)
      return lane
    }
    bounds = CGRect(x: 0, y: 0, width: max(left - Self.laneGap, 0) + 2 * offset, height: height + 2 * offset)
    routes = route(links.map { (steps[$0.from].id, steps[$0.to].id, $0.label) })
  }

  private enum Side { case left, right, top, bottom }

  private func route(_ links: [(from: String, to: String, label: String?)]) -> [DiagramLayout.Route] {
    // Links down go from bottom to top, or turn toward another column; links within a row go sideways;
    // links back up loop around a side.
    var plans: [(start: Side, end: Side)] = []
    var reaches: [Int: CGFloat] = [:]
    var ends: [String: [(link: Int, isStart: Bool, toward: CGPoint)]] = [:]
    for (index, link) in links.enumerated() {
      let s = steps[link.from]!, t = steps[link.to]!
      let plan: (Side, Side)
      if t.minY > s.maxY + 10 {
        plan = sweep(from: link.from, to: link.to)
      } else if abs(t.midY - s.midY) < 1 {
        plan = t.midX > s.midX ? (.right, .left) : (.left, .right)
      } else {
        let loop = loop(from: link.from, to: link.to)
        plan = loop.plan
        reaches[index] = loop.reach
      }
      plans.append(plan)
      ends["\(link.from)|\(plan.0)", default: []].append((index, true, CGPoint(x: t.midX, y: t.midY)))
      ends["\(link.to)|\(plan.1)", default: []].append((index, false, CGPoint(x: s.midX, y: s.midY)))
    }

    var anchors: [Int: (start: CGPoint, end: CGPoint)] = [:]
    for (key, list) in ends {
      let parts = key.split(separator: "|")
      let frame = steps[String(parts[0])]!
      let side: Side = switch parts[1] {
      case "left": .left
      case "right": .right
      case "top": .top
      default: .bottom
      }
      let vertical = side == .left || side == .right
      let sorted = list.sorted { vertical ? $0.toward.y < $1.toward.y : $0.toward.x < $1.toward.x }
      let spacing: CGFloat = vertical ? 16 : 40
      for (i, end) in sorted.enumerated() {
        let offset = (CGFloat(i) - CGFloat(sorted.count - 1) / 2) * spacing
        let point = anchor(frame, side, offset: offset)
        var pair = anchors[end.link] ?? (.zero, .zero)
        if end.isStart { pair.start = point } else { pair.end = point }
        anchors[end.link] = pair
      }
    }

    return links.enumerated().map { index, link in
      let (start, end) = anchors[index]!
      let segment = self.segment(plans[index], from: start, to: end, reach: reaches[index] ?? 56)
      var route = DiagramLayout.Route(id: "\(link.from)->\(link.to)", from: link.from, to: link.to, segments: [segment])
      if link.label != nil { route.labelSpot = segment.point(at: 0.5) }
      return route
    }
  }

  /// How a link reaches a step in a lower row. A step in another column gets a quarter turn that
  /// crosses no card, out the side and down into its top or down and into its side, because a
  /// bottom-to-top curve gets squeezed flat in the narrow gap between rows.
  private func sweep(from: String, to: String) -> (Side, Side) {
    let s = steps[from]!, t = steps[to]!
    let direction: CGFloat = t.midX > s.midX ? 1 : -1
    let others = steps.filter { $0.key != from && $0.key != to }.map(\.value)
    let turns: [(Side, Side)] = direction > 0 ? [(.right, .top), (.bottom, .left)] : [(.left, .top), (.bottom, .right)]
    return turns.first { plan in
      let start = anchor(s, plan.0), end = anchor(t, plan.1)
      guard (end.x - start.x) * direction >= 30 else { return false }
      let curve = segment(plan, from: start, to: end)
      return !(1..<24).contains { step in
        let point = curve.point(at: CGFloat(step) / 24)
        return others.contains { $0.insetBy(dx: -8, dy: -8).contains(point) }
      }
    } ?? (.bottom, .top)
  }

  /// How a link back up loops: out a side and into the same side of its target, on the right or the left,
  /// close to the cards or past everything beside them, whichever crosses the fewest cards.
  private func loop(from: String, to: String) -> (plan: (Side, Side), reach: CGFloat) {
    let s = steps[from]!, t = steps[to]!
    let others = steps.filter { $0.key != from && $0.key != to }.map(\.value)
    let low = min(s.minY, t.minY), high = max(s.maxY, t.maxY)
    let beside = others.filter { $0.maxY > low && $0.minY < high }
    let wideRight = max(56, (beside.map(\.maxX).max() ?? 0) - max(s.maxX, t.maxX) + 30)
    let wideLeft = max(56, min(s.minX, t.minX) - (beside.map(\.minX).min() ?? .infinity) + 30)
    let candidates: [(plan: (Side, Side), reach: CGFloat)] = [
      ((.right, .right), 56), ((.left, .left), 56), ((.right, .right), wideRight), ((.left, .left), wideLeft),
    ]
    func crossings(_ candidate: (plan: (Side, Side), reach: CGFloat)) -> Int {
      let curve = segment(candidate.plan, from: anchor(s, candidate.plan.0), to: anchor(t, candidate.plan.1), reach: candidate.reach)
      let hit = (1..<32).flatMap { step in
        let point = curve.point(at: CGFloat(step) / 32)
        return others.indices.filter { others[$0].insetBy(dx: -6, dy: -6).contains(point) }
      }
      return Set(hit).count
    }
    return candidates.min { crossings($0) < crossings($1) }!
  }

  private func anchor(_ frame: CGRect, _ side: Side, offset: CGFloat = 0) -> CGPoint {
    switch side {
    case .left: CGPoint(x: frame.minX, y: frame.midY + offset)
    case .right: CGPoint(x: frame.maxX, y: frame.midY + offset)
    case .top: CGPoint(x: frame.midX + offset, y: frame.minY)
    case .bottom: CGPoint(x: frame.midX + offset, y: frame.maxY)
    }
  }

  private func segment(_ plan: (start: Side, end: Side), from start: CGPoint, to end: CGPoint, reach: CGFloat = 56) -> DiagramLayout.Segment {
    let dx = end.x - start.x, dy = end.y - start.y
    switch plan {
    case (.bottom, .top):
      let bend = max(dy * 0.5, 30)
      return DiagramLayout.Segment(start: start, control1: CGPoint(x: start.x, y: start.y + bend), control2: CGPoint(x: end.x, y: end.y - bend), end: end)
    case (.right, .right):
      let side = max(start.x, end.x) + reach
      return DiagramLayout.Segment(start: start, control1: CGPoint(x: side, y: start.y), control2: CGPoint(x: side, y: end.y), end: end)
    case (.left, .left):
      let side = min(start.x, end.x) - reach
      return DiagramLayout.Segment(start: start, control1: CGPoint(x: side, y: start.y), control2: CGPoint(x: side, y: end.y), end: end)
    case (_, .top):
      return DiagramLayout.Segment(start: start, control1: CGPoint(x: start.x + dx * 0.55, y: start.y), control2: CGPoint(x: end.x, y: end.y - dy * 0.55), end: end)
    case (.bottom, _):
      return DiagramLayout.Segment(start: start, control1: CGPoint(x: start.x, y: start.y + dy * 0.55), control2: CGPoint(x: end.x - dx * 0.55, y: end.y), end: end)
    default:
      return .curve(start, end, minimum: 20)
    }
  }
}

struct FlowCanvas: View {
  let flow: Architecture.Flow
  let architecture: Architecture
  @Binding var selection: String?
  var request: CanvasRequest?

  @State private var hovered: String?
  @Environment(\.diagramTheme) private var theme
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let layout = FlowDiagramLayout(flow)
    let style = DiagramStyle(theme, scheme)
    let minimap = layout.lanes.map { MinimapItem(frame: $0.frame, color: style.tint(Theme.groupColor($0.colorIndex)), isArea: true) }
      + flow.steps.compactMap { step in layout.steps[step.id].map { MinimapItem(frame: $0, color: style.tint(step.stepKind.color), isArea: false) } }
    ZoomableCanvas(
      bounds: layout.bounds,
      minimap: minimap,
      request: request,
      frames: { layout.steps[$0] },
      onBackgroundTap: { selection = nil },
      onFocus: { selection = $0 },
      onLeave: { hovered = nil }
    ) { canvas in
      FlowWorld(
        flow: flow,
        architecture: architecture,
        layout: layout,
        selection: selection,
        hovered: hovered,
        scale: canvas.scale,
        onHover: { id, inside in
          if inside { hovered = id } else if hovered == id { hovered = nil }
        },
        onSelect: { selection = $0 },
        onFocus: canvas.focus
      )
    }
  }
}

struct FlowWorld: View {
  let flow: Architecture.Flow
  let architecture: Architecture
  let layout: FlowDiagramLayout
  var selection: String?
  var hovered: String?
  /// Steps an explainer points at: they and the links between them stand out.
  var spotlight: Set<String>? = nil
  var scale: CGFloat
  var onHover: (String, Bool) -> Void
  var onSelect: (String) -> Void
  var onFocus: (String) -> Void

  var body: some View {
    let focus = selection ?? hovered
    let highlighted: Set<String> = if let spotlight, selection == nil {
      Set(layout.routes.filter { spotlight.contains($0.from) && spotlight.contains($0.to) }.map(\.id))
    } else {
      Set(layout.routes.filter { $0.from == focus || $0.to == focus }.map(\.id))
    }
    let neighbors = Set(layout.routes.filter { $0.from == selection || $0.to == selection }.flatMap { [$0.from, $0.to] })
    let fading = selection != nil || spotlight != nil

    ZStack(alignment: .topLeading) {
      ForEach(layout.lanes) { lane in
        LaneBand(lane: lane, architecture: architecture, showsName: layout.lanes.count > 1 || !lane.name.isEmpty)
          .frame(width: lane.frame.width, height: lane.frame.height)
          .position(x: lane.frame.midX, y: lane.frame.midY)
          .allowsHitTesting(false)
      }

      ForEach(layout.routes) { route in
        EdgeView(
          route: route,
          kind: .calls,
          change: nil,
          color: flow.step(route.from)?.stepKind.color ?? .accentColor,
          isHighlighted: highlighted.contains(route.id),
          isDimmed: fading && !highlighted.contains(route.id),
          scale: scale
        )
      }

      ForEach(layout.routes) { route in
        if let label = flow.step(route.from)?.next.first(where: { $0.to == route.to })?.label, !label.isEmpty, let spot = route.labelSpot {
          EdgeLabel(text: label, isHighlighted: highlighted.contains(route.id))
            .position(spot)
            .allowsHitTesting(false)
        }
      }

      ForEach(Array(flow.steps.enumerated()), id: \.element.id) { position, step in
        if let frame = layout.steps[step.id] {
          FlowStepCard(
            step: step,
            number: position + 1,
            isStart: position == 0,
            architecture: architecture,
            isSelected: selection == step.id || (selection == nil && spotlight?.contains(step.id) == true),
            isHovered: hovered == step.id,
            isDimmed: selection != nil
              ? selection != step.id && !neighbors.contains(step.id)
              : spotlight.map { !$0.contains(step.id) } ?? false
          )
          // Gestures go on the card itself: after .position they would cover the whole canvas.
          .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .onHover { onHover(step.id, $0) }
          .onTapGesture { onSelect(step.id) }
          .simultaneousGesture(TapGesture(count: 2).onEnded { onFocus(step.id) })
          .position(x: frame.midX, y: frame.midY)
        }
      }
    }
    .frame(width: layout.bounds.maxX, height: layout.bounds.maxY, alignment: .topLeading)
  }
}

struct LaneBand: View {
  let lane: FlowDiagramLayout.Lane
  let architecture: Architecture
  let showsName: Bool
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  /// A person, the app itself, or one of its components, when the lane is named after one.
  private var symbol: String {
    let name = lane.name.lowercased()
    if let node = architecture.nodes.first(where: { $0.name.lowercased() == name }) { return node.nodeKind.symbol }
    if name == architecture.name.lowercased() { return "macwindow" }
    if ["you", "user", "visitor", "writer", "reader"].contains(name) { return "person.fill" }
    if name.contains("agent") { return "sparkles" }
    return "circle.fill"
  }

  var body: some View {
    if theme == .blueprint {
      blueprint
    } else {
      ThemedBox(name: showsName ? (lane.name.isEmpty ? "Other" : lane.name) : "")
    }
  }

  private var blueprint: some View {
    let color = Theme.groupColor(lane.colorIndex)
    let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    return ZStack(alignment: .top) {
      shape.fill(color.opacity(scheme == .dark ? 0.06 : 0.05))
      shape.strokeBorder(color.opacity(scheme == .dark ? 0.22 : 0.28), lineWidth: 1)
      if showsName {
        HStack(spacing: 8) {
          Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(Circle().fill(color.opacity(0.14)))
          Text(lane.name.isEmpty ? "Other" : lane.name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color.mix(with: scheme == .dark ? .white : .black, by: 0.2))
            .lineLimit(1)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
      }
    }
  }
}

struct StepKindTile: View {
  let kind: StepKind
  var size: CGFloat = 22

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
      .fill(LinearGradient(colors: [kind.color.mix(with: .white, by: 0.12), kind.color.mix(with: .black, by: 0.2)], startPoint: .top, endPoint: .bottom))
      .overlay(Image(systemName: kind.symbol).font(.system(size: size * 0.48, weight: .bold)).foregroundStyle(.white))
      .frame(width: size, height: size)
  }
}

struct FlowStepCard: View {
  let step: Architecture.FlowStep
  let number: Int
  let isStart: Bool
  let architecture: Architecture
  var isSelected = false
  var isHovered = false
  var isDimmed = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  var body: some View {
    if theme == .blueprint {
      blueprint
    } else {
      themed
    }
  }

  private var themed: some View {
    let style = DiagramStyle(theme, scheme)
    let kind = step.stepKind
    let shape = RoundedRectangle(cornerRadius: style.cardRadius, style: .continuous)
    return VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 7) {
        if theme != .ascii {
          Image(systemName: kind.symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(style.tint(kind.color))
        }
        Text(theme == .ascii ? "\(number)." : "\(number)")
          .font(style.font(11, .bold))
          .foregroundStyle(style.secondaryInk)
        if isStart {
          Text(theme == .minimal ? "Start" : "[START]")
            .font(style.font(9, .bold))
            .foregroundStyle(style.ink)
        }
        Spacer(minLength: 0)
      }
      Text(step.title)
        .font(style.font(13, .semibold))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      if let text = step.text, !text.isEmpty {
        Text(text)
          .font(style.font(10.5))
          .foregroundStyle(style.secondaryInk)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(style.ink)
    .padding(12)
    .frame(width: FlowDiagramLayout.cardSize.width, height: FlowDiagramLayout.cardSize.height, alignment: .topLeading)
    .background(shape.fill(style.paper))
    .overlay {
      if isSelected {
        shape.strokeBorder(style.ink, lineWidth: theme == .ascii ? 3 : 2)
      } else if kind == .decision {
        shape.strokeBorder(style.ink.opacity(0.8), style: StrokeStyle(lineWidth: style.borderWidth, dash: [6, 4]))
      } else if kind == .done {
        shape.strokeBorder(style.ink.opacity(0.85), lineWidth: style.borderWidth + 1)
      } else {
        shape.strokeBorder(isHovered ? style.ink.opacity(0.7) : style.border, lineWidth: style.borderWidth)
      }
    }
    .shadow(color: style.glow(isSelected ? 0.55 : 0.14), radius: isSelected ? 12 : 6)
    .opacity(isDimmed ? 0.3 : 1)
    .scaleEffect(isHovered && !isSelected ? 1.025 : 1)
    .animation(.snappy(duration: 0.18), value: isHovered)
    .animation(.smooth(duration: 0.25), value: isDimmed)
  }

  private var blueprint: some View {
    let kind = step.stepKind
    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    return VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 7) {
        StepKindTile(kind: kind)
        Text("\(number)")
          .font(.system(size: 11, weight: .bold).monospacedDigit())
          .foregroundStyle(.secondary)
        if isStart {
          Text("START")
            .font(.system(size: 8.5, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.brand))
        }
        Spacer(minLength: 0)
        HStack(spacing: 2) {
          ForEach(step.nodes.prefix(3), id: \.self) { id in
            if let node = architecture.node(id) { KindTile(kind: node.nodeKind, size: 14) }
          }
        }
      }
      Text(step.title)
        .font(.system(size: 13.5, weight: .semibold))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      if let text = step.text, !text.isEmpty {
        Text(text)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(width: FlowDiagramLayout.cardSize.width, height: FlowDiagramLayout.cardSize.height, alignment: .topLeading)
    .background(shape.fill(LinearGradient(colors: [Theme.cardTop(scheme), Theme.card(scheme)], startPoint: .top, endPoint: .bottom)))
    .overlay(border(shape, kind))
    .shadow(color: isSelected ? kind.color.opacity(0.5) : .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: isSelected ? 16 : 10, y: isSelected ? 0 : 4)
    .opacity(isDimmed ? 0.3 : 1)
    .scaleEffect(isHovered && !isSelected ? 1.025 : 1)
    .animation(.snappy(duration: 0.18), value: isHovered)
    .animation(.smooth(duration: 0.25), value: isDimmed)
  }

  @ViewBuilder
  private func border(_ shape: RoundedRectangle, _ kind: StepKind) -> some View {
    if isSelected {
      shape.strokeBorder(kind.color, lineWidth: 2)
    } else if kind == .decision {
      shape.strokeBorder(kind.color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    } else if kind == .done {
      shape.strokeBorder(kind.color.opacity(0.7), lineWidth: 1.5)
    } else if isHovered {
      shape.strokeBorder(kind.color.opacity(0.7), lineWidth: 1)
    } else {
      shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08), lineWidth: 1)
    }
  }
}

/// The flows or explainers of the app, to switch between them over the canvas.
struct ChipPicker: View {
  struct Item: Identifiable {
    var id: String
    var title: String
    /// The heading it goes under in the menu, when there are too many to show as chips.
    var section: String?
  }

  let items: [Item]
  let selected: String?
  let choose: (String) -> Void

  var body: some View {
    // Every item as a chip when they fit, or a menu with arrows when they don't.
    ViewThatFits(in: .horizontal) {
      chips
      compact
    }
    .padding(4)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    .animation(.snappy(duration: 0.2), value: selected)
  }

  private var chips: some View {
    HStack(spacing: 2) {
      ForEach(items) { item in
        let active = item.id == selected
        Button { choose(item.id) } label: {
          Text(item.title)
            .font(.system(size: 12, weight: active ? .semibold : .medium))
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(active ? .white : .primary)
            .background {
              if active { Capsule().fill(Color.accentColor) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var compact: some View {
    let index = items.firstIndex { $0.id == selected } ?? 0
    return HStack(spacing: 2) {
      arrow("chevron.left", to: index - 1)
      Menu {
        let sections = items.reduce(into: [String?]()) { sections, item in
          if !sections.contains(item.section) { sections.append(item.section) }
        }
        ForEach(sections, id: \.self) { section in
          let members = items.filter { $0.section == section }
          if let section {
            Section(section) {
              ForEach(members) { item in Button(item.title) { choose(item.id) } }
            }
          } else {
            ForEach(members) { item in Button(item.title) { choose(item.id) } }
          }
        }
      } label: {
        Text("\(items[index].title)  ·  \(index + 1) of \(items.count)")
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .padding(.horizontal, 8)
      arrow("chevron.right", to: index + 1)
    }
  }

  private func arrow(_ symbol: String, to index: Int) -> some View {
    Button { choose(items[index].id) } label: {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .bold))
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!items.indices.contains(index))
  }
}

/// A version with no flows: what they are, and the prompt that asks an agent for them.
struct FlowsEmpty: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp

  var body: some View {
    ZStack {
      WelcomeBackground()
      VStack(spacing: 16) {
        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(Theme.brand)
        Text("No flows yet")
          .font(.title2.weight(.bold))
        Text("Flows show every workflow of \(store.name(of: app)), step by step: what people using it do, what the owner does, what agents do, and what the app does on its own, with the components behind each step.")
          .font(.system(size: 13.5))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.flowsPrompt(for: app), prominent: true)
      }
      .frame(width: 480)
      .padding(40)
    }
  }
}
