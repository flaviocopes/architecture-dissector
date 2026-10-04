import SwiftUI

/// Places what an app stores as a schema. Each store is a box, side by side in the order their
/// references flow. Inside a box, entities sit in columns that follow their references, and each card
/// moves up or down toward what it points to. A reference runs from its field's row to the header of
/// the entity it points to, through the gaps between the cards of every column it crosses.
struct DataLayout {
  static let width: CGFloat = 264
  static let header: CGFloat = 54
  static let row: CGFloat = 22
  static let footer: CGFloat = 8
  static let cardGap: CGFloat = 30
  static let columnGap: CGFloat = 96
  static let boxGap: CGFloat = 110
  static let padding = (x: CGFloat(24), top: CGFloat(50), bottom: CGFloat(24))
  static let margin: CGFloat = 80
  static let maxColumnHeight: CGFloat = 1100

  /// A field that points to another entity.
  struct Reference {
    var id: String
    var from: String
    var field: Int
    var fieldName: String
    var to: String
  }

  var cards: [String: CGRect] = [:]
  var boxes: [DiagramLayout.Box] = []
  var references: [Reference] = []
  /// One per reference, in the same order.
  var routes: [DiagramLayout.Route] = []
  var bounds: CGRect = .zero

  static func height(_ entity: Architecture.Entity) -> CGFloat {
    header + CGFloat(entity.fields.count) * row + (entity.fields.isEmpty ? 0 : footer)
  }

  /// The middle of a field's row, where its reference leaves the card.
  static func rowY(_ field: Int, in frame: CGRect) -> CGFloat {
    frame.minY + header + (CGFloat(field) + 0.5) * row
  }

  init(_ architecture: Architecture) {
    let entities = architecture.entities
    guard !entities.isEmpty else { return }
    let index = Dictionary(entities.enumerated().map { ($1.id, $0) }) { first, _ in first }
    let heights = entities.map(Self.height)
    for entity in entities {
      for (position, field) in entity.fields.enumerated() {
        guard let ref = field.ref, index[ref] != nil else { continue }
        references.append(Reference(id: "\(entity.id)#\(position)", from: entity.id, field: position, fieldName: field.name, to: ref))
      }
    }
    let links = references.map { (from: index[$0.from]!, to: index[$0.to]!) }

    // One box per store, in the order entities first name it, then ordered by the references between
    // them, with the stores no reference reaches last.
    var stores: [String?] = []
    for entity in entities where !stores.contains(entity.store) { stores.append(entity.store) }
    let storeOf = entities.map { entity in stores.firstIndex(of: entity.store)! }
    var weights: [Int: [Int: Int]] = [:]
    for link in links where storeOf[link.from] != storeOf[link.to] {
      weights[storeOf[link.from], default: [:]][storeOf[link.to], default: 0] += 1
    }
    let storeEdges = weights.flatMap { a, targets in targets.map { (a, $0.key, $0.value) } }
    var storeRanks = DiagramLayout.rank(count: stores.count, edges: storeEdges.map { ($0.0, $0.1) })
    DiagramLayout.shorten(&storeRanks, edges: storeEdges)
    let linked = Set(storeEdges.flatMap { [$0.0, $0.1] })
    let order = stores.indices.sorted {
      (linked.contains($0) ? 0 : 1, storeRanks[$0], $0) < (linked.contains($1) ? 0 : 1, storeRanks[$1], $1)
    }

    // Inside a box, columns follow the references, and a column taller than maxColumnHeight wraps.
    var columns: [[Int]] = []
    var columnStore: [Int] = []
    for store in order {
      let members = entities.indices.filter { storeOf[$0] == store }
      let local = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($1, $0) })
      let inside = links.compactMap { link -> (Int, Int, Int)? in
        guard let a = local[link.from], let b = local[link.to], a != b else { return nil }
        return (a, b, 1)
      }
      var ranks = DiagramLayout.rank(count: members.count, edges: inside.map { ($0.0, $0.1) })
      DiagramLayout.shorten(&ranks, edges: inside)
      ranks = DiagramLayout.compact(ranks)
      for rank in 0...(ranks.max() ?? 0) {
        var column: [Int] = []
        var height: CGFloat = 0
        for (offset, member) in members.enumerated() where ranks[offset] == rank {
          if !column.isEmpty, height + heights[member] > Self.maxColumnHeight {
            columns.append(column)
            columnStore.append(store)
            column = []
            height = 0
          }
          column.append(member)
          height += heights[member] + Self.cardGap
        }
        if !column.isEmpty {
          columns.append(column)
          columnStore.append(store)
        }
      }
    }

    var columnX: [CGFloat] = []
    var x: CGFloat = 0
    for col in columns.indices {
      if col > 0 { x += Self.width + (columnStore[col] == columnStore[col - 1] ? Self.columnGap : 2 * Self.padding.x + Self.boxGap) }
      columnX.append(x)
    }
    var columnOf = Array(repeating: 0, count: entities.count)
    for (col, column) in columns.enumerated() {
      for member in column { columnOf[member] = col }
    }

    // Columns start centered on one line, then sweep back and forth: each card moves toward
    // what it points to and what points to it, and the column keeps them in order without overlaps.
    func stack(_ column: [Int]) -> CGFloat {
      column.map { heights[$0] }.reduce(0, +) + CGFloat(column.count - 1) * Self.cardGap
    }
    let tallest = columns.map(stack).max() ?? 0
    var tops = Array(repeating: CGFloat(0), count: entities.count)
    for column in columns {
      var y = (tallest - stack(column)) / 2
      for member in column {
        tops[member] = y
        y += heights[member] + Self.cardGap
      }
    }
    func rowOffset(_ field: Int) -> CGFloat { Self.header + (CGFloat(field) + 0.5) * Self.row }
    var pulls = Array(repeating: [(other: Int, offset: CGFloat)](), count: entities.count)
    for (reference, link) in zip(references, links) where columnOf[link.from] != columnOf[link.to] {
      // The holder wants its field's row level with the header it points to, and the other way around.
      pulls[link.from].append((link.to, Self.header / 2 - rowOffset(reference.field)))
      pulls[link.to].append((link.from, rowOffset(reference.field) - Self.header / 2))
    }
    for iteration in 0..<8 {
      let sweep = iteration % 2 == 0 ? Array(columns.indices) : columns.indices.reversed()
      for col in sweep {
        let wanted = Dictionary(uniqueKeysWithValues: columns[col].map { member in
          let list = pulls[member]
          return (member, list.isEmpty ? tops[member] : list.map { tops[$0.other] + $0.offset }.reduce(0, +) / CGFloat(list.count))
        })
        let sorted = columns[col].enumerated()
          .sorted { (wanted[$0.element]!, $0.offset) < (wanted[$1.element]!, $1.offset) }
          .map(\.element)
        columns[col] = sorted
        var placed: [CGFloat] = []
        for (position, member) in sorted.enumerated() {
          var top = wanted[member]!
          if position > 0 { top = max(top, placed[position - 1] + heights[sorted[position - 1]] + Self.cardGap) }
          placed.append(top)
        }
        let drift = zip(sorted, placed).map { $1 - wanted[$0]! }.reduce(0, +) / CGFloat(sorted.count)
        for (member, top) in zip(sorted, placed) { tops[member] = top - drift }
      }
    }

    var frames = entities.indices.map { CGRect(x: columnX[columnOf[$0]], y: tops[$0], width: Self.width, height: heights[$0]) }
    var boxFrames: [Int: CGRect] = [:]
    for store in order {
      let members = entities.indices.filter { storeOf[$0] == store }
      let area = members.map { frames[$0] }.reduce(frames[members[0]]) { $0.union($1) }
      boxFrames[store] = CGRect(
        x: area.minX - Self.padding.x, y: area.minY - Self.padding.top,
        width: area.width + 2 * Self.padding.x, height: area.height + Self.padding.top + Self.padding.bottom
      )
    }

    // Shift everything so the diagram starts at the margin.
    let raw = boxFrames.values.reduce(boxFrames[order[0]]!) { $0.union($1) }
    let shift = CGPoint(x: Self.margin - raw.minX, y: Self.margin - raw.minY)
    frames = frames.map { $0.offsetBy(dx: shift.x, dy: shift.y) }
    columnX = columnX.map { $0 + shift.x }
    for (position, entity) in entities.enumerated() { cards[entity.id] = frames[position] }
    for store in order {
      let id = stores[store] ?? ""
      let node = stores[store].flatMap(architecture.node)
      let name = node.map { node in ([node.name] + node.tech.prefix(1)).joined(separator: " · ") } ?? "No store"
      boxes.append(DiagramLayout.Box(id: id, name: name, frame: boxFrames[store]!.offsetBy(dx: shift.x, dy: shift.y), colorIndex: store))
    }
    bounds = raw.offsetBy(dx: shift.x, dy: shift.y).insetBy(dx: -Self.margin, dy: -Self.margin)
    routes = route(links: links, frames: frames, columnOf: columnOf, columns: columns.enumerated().map { col, members in
      (span: columnX[col]...(columnX[col] + Self.width), cards: members.map { frames[$0] }.sorted { $0.minY < $1.minY })
    })
  }

  // MARK: Routing

  private func route(
    links: [(from: Int, to: Int)], frames: [CGRect], columnOf: [Int],
    columns: [(span: ClosedRange<CGFloat>, cards: [CGRect])]
  ) -> [DiagramLayout.Route] {
    struct Pass {
      var column: Int
      var lane: Int
      var y: CGFloat
      var offset: CGFloat = 0
    }
    var starts: [CGPoint] = []
    var ends: [CGPoint] = []
    var passes: [[Pass]] = []
    var arrivals: [String: [(reference: Int, from: CGFloat)]] = [:]

    for (number, (reference, link)) in zip(references, links).enumerated() {
      let s = frames[link.from], t = frames[link.to]
      let a = columnOf[link.from], b = columnOf[link.to]
      let y = Self.rowY(reference.field, in: s)
      // Forward leaves the right edge and arrives on the left; back the other way; in one column, both on the right.
      let leavesRight = a <= b
      let arrivesLeft = a < b
      starts.append(CGPoint(x: leavesRight ? s.maxX : s.minX, y: y))
      ends.append(CGPoint(x: arrivesLeft ? t.minX : t.maxX, y: t.minY + Self.header / 2))
      arrivals["\(link.to)|\(arrivesLeft)", default: []].append((number, y))

      let crossed = a < b ? Array((a + 1)..<b) : a > b ? Array(((b + 1)..<a).reversed()) : []
      passes.append(crossed.map { column in
        let middle = (columns[column].span.lowerBound + columns[column].span.upperBound) / 2
        let progress = (middle - s.midX) / (t.midX - s.midX)
        let wanted = y + (t.minY + Self.header / 2 - y) * progress
        let ways = lanes(columns[column].cards)
        let best = ways.indices.min { abs(ways[$0] - wanted) < abs(ways[$1] - wanted) } ?? 0
        return Pass(column: column, lane: best, y: ways[best])
      })
    }

    // References that arrive at the same header spread out, in the order they come from.
    for list in arrivals.values where list.count > 1 {
      let sorted = list.sorted { $0.from < $1.from }
      let spacing = min(8, (Self.header - 22) / CGFloat(sorted.count - 1))
      for (i, item) in sorted.enumerated() {
        ends[item.reference].y += (CGFloat(i) - CGFloat(sorted.count - 1) / 2) * spacing
      }
    }

    // References through the same gap run side by side.
    var shared: [String: [(reference: Int, pass: Int)]] = [:]
    for (number, list) in passes.enumerated() {
      for (p, pass) in list.enumerated() { shared["\(pass.column)|\(pass.lane)", default: []].append((number, p)) }
    }
    for list in shared.values where list.count > 1 {
      let sorted = list.sorted { starts[$0.reference].y < starts[$1.reference].y }
      let spacing = min(6, (Self.cardGap - 10) / CGFloat(sorted.count - 1))
      for (i, item) in sorted.enumerated() {
        passes[item.reference][item.pass].offset = (CGFloat(i) - CGFloat(sorted.count - 1) / 2) * spacing
      }
    }

    // Arcs beside one column nest: short ones inside, long ones outside.
    var bulges = Array(repeating: CGFloat(0), count: references.count)
    var arcs: [Int: [Int]] = [:]
    for (number, link) in links.enumerated() where columnOf[link.from] == columnOf[link.to] {
      arcs[columnOf[link.from], default: []].append(number)
    }
    for list in arcs.values {
      let sorted = list.sorted { abs(ends[$0].y - starts[$0].y) < abs(ends[$1].y - starts[$1].y) }
      for (order, number) in sorted.enumerated() { bulges[number] = 26 + CGFloat(order) * 10 }
    }

    return references.indices.map { number in
      let reference = references[number]
      let start = starts[number], end = ends[number]
      var segments: [DiagramLayout.Segment]
      if columnOf[links[number].from] == columnOf[links[number].to] {
        let bulge = bulges[number]
        segments = [DiagramLayout.Segment(start: start, control1: CGPoint(x: start.x + bulge, y: start.y), control2: CGPoint(x: end.x + bulge, y: end.y), end: end)]
      } else {
        let forward = end.x > start.x
        segments = []
        var cursor = start
        for pass in passes[number] {
          let span = columns[pass.column].span
          let y = pass.y + pass.offset
          let entry = CGPoint(x: forward ? span.lowerBound - 18 : span.upperBound + 18, y: y)
          let exit = CGPoint(x: forward ? span.upperBound + 18 : span.lowerBound - 18, y: y)
          segments.append(.curve(cursor, entry, minimum: 30))
          segments.append(.line(entry, exit))
          cursor = exit
        }
        segments.append(.curve(cursor, end, minimum: 30))
      }
      return DiagramLayout.Route(id: reference.id, from: reference.from, to: reference.to, segments: segments)
    }
  }

  /// The y of each way through a column: above its first card, between cards, and below its last.
  private func lanes(_ cards: [CGRect]) -> [CGFloat] {
    guard let first = cards.first, let last = cards.last else { return [0] }
    var lanes = [first.minY - Self.cardGap / 2]
    for (upper, lower) in zip(cards, cards.dropFirst()) { lanes.append((upper.maxY + lower.minY) / 2) }
    lanes.append(last.maxY + Self.cardGap / 2)
    return lanes
  }
}

extension Architecture {
  /// The kind of the component that holds an entity, for its color and symbol.
  func storeKind(_ entity: Entity) -> NodeKind {
    entity.store.flatMap(node)?.nodeKind ?? .database
  }
}

struct DataCanvas: View {
  let diagram: Diagram
  @Binding var selection: String?
  var request: CanvasRequest?

  @State private var hovered: String?
  @Environment(\.diagramTheme) private var theme
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let layout = diagram.dataLayout
    let architecture = diagram.architecture
    let style = DiagramStyle(theme, scheme)
    let minimap = layout.boxes.map { MinimapItem(frame: $0.frame, color: style.tint(Theme.groupColor($0.colorIndex)), isArea: true) }
      + architecture.entities.compactMap { entity in
        layout.cards[entity.id].map { frame in
          let change = diagram.diff?.entities[entity.id].flatMap { $0 == .unchanged ? nil : $0.color }
          return MinimapItem(frame: frame, color: change ?? style.tint(architecture.storeKind(entity).color), isArea: false)
        }
      }
    ZoomableCanvas(
      bounds: layout.bounds,
      minimap: minimap,
      request: request,
      frames: { layout.cards[$0] },
      onBackgroundTap: { selection = nil },
      onFocus: { selection = $0 },
      onLeave: { hovered = nil }
    ) { canvas in
      DataWorld(
        diagram: diagram,
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

struct DataWorld: View {
  let diagram: Diagram
  var selection: String?
  var hovered: String?
  /// Entities an explainer points at: they and the references between them stand out.
  var spotlight: Set<String>? = nil
  var scale: CGFloat
  var onHover: (String, Bool) -> Void
  var onSelect: (String) -> Void
  var onFocus: (String) -> Void

  var body: some View {
    let layout = diagram.dataLayout
    let architecture = diagram.architecture
    let focus = selection ?? hovered
    let highlighted: Set<String> = if let spotlight, selection == nil {
      Set(layout.routes.filter { spotlight.contains($0.from) && spotlight.contains($0.to) }.map(\.id))
    } else {
      Set(layout.routes.filter { $0.from == focus || $0.to == focus }.map(\.id))
    }
    let neighbors = Set(layout.routes.filter { $0.from == selection || $0.to == selection }.flatMap { [$0.from, $0.to] })
    let fading = selection != nil || spotlight != nil

    ZStack(alignment: .topLeading) {
      ForEach(layout.boxes, id: \.id) { box in
        GroupBoxView(box: box, count: architecture.entities.filter { ($0.store ?? "") == box.id }.count, hidesTitle: false)
          .frame(width: box.frame.width, height: box.frame.height)
          .position(x: box.frame.midX, y: box.frame.midY)
          .allowsHitTesting(false)
      }

      ForEach(Array(layout.routes.enumerated()), id: \.element.id) { number, route in
        let reference = layout.references[number]
        EdgeView(
          route: route,
          kind: .calls,
          change: diagram.diff?.field(reference.fieldName, of: reference.from),
          color: architecture.entity(reference.from).map { architecture.storeKind($0).color } ?? .accentColor,
          isHighlighted: highlighted.contains(route.id),
          isDimmed: fading && !highlighted.contains(route.id),
          scale: scale
        )
      }

      ForEach(architecture.entities) { entity in
        if let frame = layout.cards[entity.id] {
          EntityCard(
            entity: entity,
            architecture: architecture,
            diff: diagram.diff,
            isSelected: selection == entity.id || (selection == nil && spotlight?.contains(entity.id) == true),
            isHovered: hovered == entity.id,
            isDimmed: selection != nil
              ? selection != entity.id && !neighbors.contains(entity.id)
              : spotlight.map { !$0.contains(entity.id) } ?? false
          )
          // Gestures go on the card itself: after .position they would cover the whole canvas.
          .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .onHover { onHover(entity.id, $0) }
          .onTapGesture { onSelect(entity.id) }
          .simultaneousGesture(TapGesture(count: 2).onEnded { onFocus(entity.id) })
          .position(x: frame.midX, y: frame.midY)
        }
      }
    }
    .frame(width: layout.bounds.maxX, height: layout.bounds.maxY, alignment: .topLeading)
  }
}

/// One entity as a table: its name and what one record is, then a row per field.
struct EntityCard: View {
  let entity: Architecture.Entity
  let architecture: Architecture
  var diff: ArchitectureDiff?
  var isSelected = false
  var isHovered = false
  var isDimmed = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  private var kind: NodeKind { architecture.storeKind(entity) }
  private var change: Change? { diff?.entities[entity.id] }
  private var style: DiagramStyle { DiagramStyle(theme, scheme) }

  private var accent: Color {
    guard let change, change != .unchanged else { return kind.color }
    return change.color
  }

  private var opacity: Double {
    var value = 1.0
    if change == .unchanged { value = 0.55 }
    if change == .removed { value = 0.7 }
    if isDimmed { value = min(value, 0.28) }
    return value
  }

  var body: some View {
    let blueprint = theme == .blueprint
    let shape = RoundedRectangle(cornerRadius: style.cardRadius, style: .continuous)
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        if blueprint {
          KindTile(kind: kind, size: 30)
        } else if theme != .ascii {
          Image(systemName: kind.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(style.tint(kind.color))
            .frame(width: 22)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(entity.name)
            .font(blueprint ? .system(size: 13.5, weight: .semibold) : style.font(13, .semibold))
            .foregroundStyle(blueprint ? Color.primary : style.ink)
            .strikethrough(change == .removed, color: Theme.removed)
            .lineLimit(1)
          Text(entity.summary ?? "\(entity.fields.count) field\(entity.fields.count == 1 ? "" : "s")")
            .font(blueprint ? .system(size: 10.5) : style.font(10))
            .foregroundStyle(blueprint ? Color.secondary : style.secondaryInk)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(height: DataLayout.header)

      ForEach(Array(entity.fields.enumerated()), id: \.offset) { _, field in
        FieldRow(
          field: field,
          target: field.ref.flatMap(architecture.entity)?.name,
          color: style.tint(kind.color),
          change: change == .changed ? diff?.fields[entity.id]?[field.name] : nil
        )
        .frame(height: DataLayout.row)
      }
      Spacer(minLength: 0)
    }
    .frame(width: DataLayout.width, height: DataLayout.height(entity), alignment: .top)
    .background {
      if blueprint {
        shape.fill(LinearGradient(colors: [Theme.cardTop(scheme), Theme.card(scheme)], startPoint: .top, endPoint: .bottom))
      } else {
        shape.fill(style.paper)
      }
    }
    .overlay(alignment: .top) {
      if !entity.fields.isEmpty {
        Rectangle()
          .fill(blueprint ? (scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)) : style.border)
          .frame(height: theme == .ascii ? 1 : 0.5)
          .offset(y: DataLayout.header - 0.5)
      }
    }
    .clipShape(shape)
    .overlay(border(shape))
    .overlay(alignment: .topTrailing) { badge }
    .shadow(color: blueprint ? glow : style.glow(isSelected ? 0.55 : 0.14), radius: isSelected ? 16 : blueprint ? 10 : 6, y: isSelected || !blueprint ? 0 : 4)
    .opacity(opacity)
    .scaleEffect(isHovered && !isSelected ? 1.02 : 1)
    .animation(.snappy(duration: 0.18), value: isHovered)
    .animation(.smooth(duration: 0.25), value: isDimmed)
  }

  @ViewBuilder
  private func border(_ shape: RoundedRectangle) -> some View {
    let blueprint = theme == .blueprint
    if isSelected {
      shape.strokeBorder(blueprint ? accent : change.flatMap { $0 == .unchanged ? nil : $0.color } ?? style.ink, lineWidth: theme == .ascii ? 3 : 2)
    } else if change == .removed {
      shape.strokeBorder(Theme.removed.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    } else if let change, change != .unchanged {
      shape.strokeBorder(change.color, lineWidth: 1.5)
    } else if isHovered {
      shape.strokeBorder(blueprint ? kind.color.opacity(0.7) : style.ink.opacity(0.7), lineWidth: style.borderWidth)
    } else {
      shape.strokeBorder(style.border, lineWidth: style.borderWidth)
    }
  }

  private var glow: Color {
    if isSelected { return accent.opacity(0.55) }
    if let change, change == .added || change == .changed { return change.color.opacity(0.35) }
    return .black.opacity(scheme == .dark ? 0.35 : 0.08)
  }

  @ViewBuilder
  private var badge: some View {
    if let change, change != .unchanged {
      Text(change.badge)
        .font(style.font(8.5, .heavy))
        .tracking(0.8)
        .foregroundStyle(.black.opacity(0.78))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: theme == .blueprint ? 8 : style.cardRadius, style: .continuous).fill(change.color))
        .offset(x: -12, y: -8)
    }
  }
}

/// A field on an entity card: a key or a link before the name, and the type after it.
struct FieldRow: View {
  let field: Architecture.Field
  /// The name of the entity it points to.
  var target: String?
  var color: Color
  var change: Change?
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  var body: some View {
    let style = DiagramStyle(theme, scheme)
    let blueprint = theme == .blueprint
    HStack(spacing: 7) {
      Group {
        if field.isKey {
          Image(systemName: "key.fill").foregroundStyle(blueprint || theme == .minimal ? Color(hex: 0xF59E0B) : style.ink)
        } else if field.ref != nil {
          Image(systemName: "link").foregroundStyle(color)
        } else {
          Circle().fill(blueprint ? AnyShapeStyle(.tertiary) : AnyShapeStyle(style.ink.opacity(0.3))).frame(width: 3.5, height: 3.5)
        }
      }
      .font(.system(size: 8.5, weight: .bold))
      .frame(width: 12)
      Text(field.name)
        .font(.system(size: 11.5, weight: field.isKey ? .semibold : .regular, design: .monospaced))
        .foregroundStyle(blueprint ? Color.primary : style.ink)
        .strikethrough(change == .removed, color: Theme.removed)
        .lineLimit(1)
        .layoutPriority(1)
      Spacer(minLength: 8)
      Text(field.type ?? target ?? "")
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(blueprint ? Color.secondary : style.secondaryInk)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      if let change, change != .unchanged {
        HStack(spacing: 0) {
          Rectangle().fill(change.color).frame(width: 3)
          Rectangle().fill(change.color.opacity(0.16))
        }
      }
    }
    .opacity(change == .removed ? 0.75 : 1)
  }
}

/// A version with no data: what it shows, and the prompt that asks an agent for it.
struct DataEmpty: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp

  var body: some View {
    ZStack {
      WelcomeBackground()
      VStack(spacing: 16) {
        Image(systemName: "tablecells")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(Theme.brand)
        Text("No data yet")
          .font(.title2.weight(.bold))
        Text("The data shows what \(store.name(of: app)) stores, field by field: its tables, collections, files and settings, and how they point to each other.")
          .font(.system(size: 13.5))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.dataPrompt(for: app), prominent: true)
      }
      .frame(width: 480)
      .padding(40)
    }
  }
}
