import AppKit
import SwiftUI

/// What the canvas draws: an architecture, or two merged when comparing versions.
struct Diagram {
  var architecture: Architecture
  var layout: DiagramLayout
  var dataLayout: DataLayout
  var diff: ArchitectureDiff?
  var touched: Set<String>
  var level: DiagramLevel

  init(architecture: Architecture, diff: ArchitectureDiff? = nil, touched: Set<String> = [], level: DiagramLevel = .inDepth) {
    var shown = diff?.merged ?? architecture
    // Files edited by hand can skip validation, so drop what the layout can't place.
    var ids = Set<String>()
    shown.nodes = shown.nodes.filter { ids.insert($0.id).inserted }
    var edges = Set<String>()
    shown.edges = shown.edges.filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to && edges.insert($0.id).inserted }
    var groups = Set<String>()
    shown.groups = shown.groups.filter { groups.insert($0.id).inserted }
    var entities = Set<String>()
    shown.entities = shown.entities.filter { entities.insert($0.id).inserted }
    shown.entities = shown.entities.map { entity in
      var entity = entity
      if let store = entity.store, !ids.contains(store) { entity.store = nil }
      entity.fields = entity.fields.map { field in
        var field = field
        if let ref = field.ref, !entities.contains(ref) { field.ref = nil }
        return field
      }
      return entity
    }
    self.architecture = shown
    self.layout = DiagramLayout(shown, metrics: level.metrics)
    self.dataLayout = DataLayout(shown)
    self.diff = diff
    self.touched = touched
    self.level = level
  }
}

struct CanvasRequest: Equatable {
  enum Action: Equatable {
    case fit, zoomIn, zoomOut, actualSize
    case focus(String)
    /// Frames these components.
    case frame([String], insets: FrameInsets)
  }

  enum FrameInsets: Equatable {
    case standard
    /// Leaves room at the top for the walkthrough card.
    case belowCard
  }
  var action: Action
  var serial: Int
}

struct Camera: Equatable {
  var scale: CGFloat = 1
  var offset: CGSize = .zero

  static let range: ClosedRange<CGFloat> = 0.12...3

  func world(_ point: CGPoint) -> CGPoint {
    CGPoint(x: (point.x - offset.width) / scale, y: (point.y - offset.height) / scale)
  }

  mutating func zoom(by factor: CGFloat, at point: CGPoint) {
    let anchor = world(point)
    scale = min(max(scale * factor, Self.range.lowerBound), Self.range.upperBound)
    offset = CGSize(width: point.x - anchor.x * scale, height: point.y - anchor.y * scale)
  }

  mutating func center(on point: CGPoint, in size: CGSize) {
    offset = CGSize(width: size.width / 2 - point.x * scale, height: size.height / 2 - point.y * scale)
  }

  mutating func fit(_ rect: CGRect, in size: CGSize, insets: EdgeInsets = EdgeInsets(top: 70, leading: 40, bottom: 110, trailing: 40), maximum: CGFloat = 1.15) {
    guard rect.width > 0, rect.height > 0, size.width > 0, size.height > 0 else { return }
    let available = CGSize(width: max(size.width - insets.leading - insets.trailing, 100), height: max(size.height - insets.top - insets.bottom, 100))
    scale = min(max(min(available.width / rect.width, available.height / rect.height), Self.range.lowerBound), maximum)
    offset = CGSize(
      width: insets.leading + (available.width - rect.width * scale) / 2 - rect.minX * scale,
      height: insets.top + (available.height - rect.height * scale) / 2 - rect.minY * scale
    )
  }
}

struct DiagramCanvas: View {
  let diagram: Diagram
  @Binding var selection: String?
  var spotlight: Set<String>?
  var showLabels: Bool
  var request: CanvasRequest?

  @State private var hovered: String?
  @Environment(\.diagramTheme) private var theme
  @Environment(\.colorScheme) private var scheme

  private var minimap: [MinimapItem] {
    let style = DiagramStyle(theme, scheme)
    return diagram.layout.boxes.map { MinimapItem(frame: $0.frame, color: style.tint(Theme.groupColor($0.colorIndex)), isArea: true) }
      + diagram.architecture.nodes.compactMap { node in
        guard let frame = diagram.layout.nodes[node.id] else { return nil }
        let color = diagram.diff?.nodes[node.id].flatMap { $0 == .unchanged ? nil : $0.color } ?? style.tint(node.nodeKind.color)
        return MinimapItem(frame: frame, color: color, isArea: false)
      }
  }

  var body: some View {
    ZoomableCanvas(
      bounds: diagram.layout.bounds,
      minimap: minimap,
      request: request,
      frames: { diagram.layout.nodes[$0] },
      onBackgroundTap: { selection = nil },
      onFocus: { selection = $0 },
      onLeave: { hovered = nil }
    ) { canvas in
      DiagramWorld(
        diagram: diagram,
        selection: selection,
        hovered: hovered,
        showLabels: showLabels,
        spotlight: spotlight,
        scale: canvas.scale,
        onHover: { id, inside in
          if inside { hovered = id } else if hovered == id { hovered = nil }
        },
        onSelect: { selection = $0 },
        onFocus: canvas.focus,
        onFrame: canvas.frame
      )
    }
  }
}

/// What a canvas tells the world it draws: the zoom, and how to zoom in on something.
struct CanvasContext {
  var scale: CGFloat
  var focus: (String) -> Void
  /// Zooms to fit these, like the cards of a group.
  var frame: ([String]) -> Void
}

/// A pannable, zoomable grid that draws a world in its own coordinates, with a minimap and zoom controls.
struct ZoomableCanvas<World: View>: View {
  let bounds: CGRect
  let minimap: [MinimapItem]
  var request: CanvasRequest?
  /// The frame of something in the world, for focus and frame requests.
  var frames: (String) -> CGRect?
  var onBackgroundTap: () -> Void
  var onFocus: (String) -> Void
  var onLeave: () -> Void
  @ViewBuilder var world: (CanvasContext) -> World

  @Environment(\.colorScheme) private var appScheme
  @Environment(\.diagramTheme) private var theme
  @State private var camera = Camera()
  @State private var pointer: CGPoint?
  @State private var dragStart: CGSize?
  @State private var size: CGSize = .zero
  @State private var monitor = EventMonitor()
  /// Until you pan or zoom, the world refits when the window changes size.
  @State private var interacted = false

  private var scheme: ColorScheme { theme.colorScheme ?? appScheme }

  var body: some View {
    GeometryReader { proxy in
      GridBackground(scale: camera.scale, offset: camera.offset, scheme: scheme, theme: theme)
        .contentShape(Rectangle())
        .onTapGesture { onBackgroundTap() }
        .overlay(alignment: .topLeading) {
          world(CanvasContext(scale: camera.scale, focus: { perform(.focus($0)) }, frame: { perform(.frame($0, insets: .standard)) }))
            .scaleEffect(camera.scale, anchor: .topLeading)
            .offset(camera.offset)
        }
        .clipped()
        .gesture(pan)
        .onContinuousHover { phase in
          switch phase {
          case .active(let location): pointer = location
          case .ended:
            pointer = nil
            onLeave()
          }
        }
        .overlay(alignment: .bottomLeading) {
          Minimap(bounds: bounds, items: minimap, camera: camera, canvas: size) { point in
            interacted = true
            camera.center(on: point, in: size)
          }
          .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
          ZoomControls(scale: camera.scale) { action in perform(action) }
            .padding(16)
        }
        .onAppear {
          size = proxy.size
          camera.fit(bounds, in: size)
          monitor.start { event in handle(event) }
        }
        .onDisappear { monitor.stop() }
        .onChange(of: proxy.size) { _, new in
          size = new
          if !interacted { camera.fit(bounds, in: new) }
        }
        .onChange(of: bounds) { _, new in
          if !interacted { withAnimation(.smooth(duration: 0.4)) { camera.fit(new, in: size) } }
        }
        .onChange(of: request) { _, new in
          if let new { perform(new.action) }
        }
    }
    .environment(\.colorScheme, scheme)
  }

  // MARK: Input

  private var pan: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        interacted = true
        onLeave()
        let start = dragStart ?? camera.offset
        dragStart = start
        camera.offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
        NSCursor.closedHand.set()
      }
      .onEnded { _ in
        dragStart = nil
        NSCursor.arrow.set()
      }
  }

  /// Trackpad scrolling pans, pinching zooms, and a mouse wheel or ?-scroll zooms around the pointer.
  private func handle(_ event: NSEvent) -> NSEvent? {
    guard let pointer else { return event }
    interacted = true
    switch event.type {
    case .magnify:
      camera.zoom(by: 1 + event.magnification, at: pointer)
    case .scrollWheel:
      let zooming = !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
      if zooming {
        // Natural scrolling flips the delta, so undo it: pushing the wheel or fingers away zooms in.
        let forward = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let step = event.hasPreciseScrollingDeltas ? forward * 0.01 : forward * 0.12
        camera.zoom(by: exp(step), at: pointer)
      } else {
        camera.offset.width += event.scrollingDeltaX
        camera.offset.height += event.scrollingDeltaY
      }
    default:
      return event
    }
    return nil
  }

  private func perform(_ action: CanvasRequest.Action) {
    interacted = action != .fit
    let middle = CGPoint(x: size.width / 2, y: size.height / 2)
    withAnimation(.smooth(duration: 0.4)) {
      switch action {
      case .fit: camera.fit(bounds, in: size)
      case .zoomIn: camera.zoom(by: 1.25, at: middle)
      case .zoomOut: camera.zoom(by: 0.8, at: middle)
      case .actualSize: camera.zoom(by: 1 / camera.scale, at: middle)
      case .focus(let id):
        guard let frame = frames(id) else { return }
        onFocus(id)
        camera.scale = max(camera.scale, 1)
        camera.center(on: CGPoint(x: frame.midX, y: frame.midY), in: size)
      case .frame(let ids, let insets):
        let found = ids.compactMap(frames)
        guard let first = found.first else { return }
        let area = found.reduce(first) { $0.union($1) }.insetBy(dx: -50, dy: -50)
        let top: CGFloat = insets == .belowCard ? 250 : 70
        camera.fit(area, in: size, insets: EdgeInsets(top: top, leading: 50, bottom: 110, trailing: 50), maximum: 1)
      }
    }
  }
}

// MARK: - Pieces

/// Groups, connections, labels and cards at their layout positions, in world coordinates.
/// The canvas scales and moves it with the camera; the welcome screen shows it as a demo.
struct DiagramWorld: View {
  let diagram: Diagram
  var selection: String?
  var hovered: String?
  var showLabels = true
  /// The components of a walkthrough step: they and the connections between them stand out.
  var spotlight: Set<String>?
  /// Animates every connection without dimming anything, for the demo.
  var highlightAll = false
  /// The zoom it's drawn at, so lines and labels stay readable.
  var scale: CGFloat = 1
  var onHover: (String, Bool) -> Void = { _, _ in }
  var onSelect: (String) -> Void = { _ in }
  var onFocus: (String) -> Void = { _ in }
  var onFrame: ([String]) -> Void = { _ in }

  private var layout: DiagramLayout { diagram.layout }
  /// So far out that cards turn into a pattern, which takes longer with bigger cards.
  private var farOut: Bool { scale * layout.metrics.node.width / DiagramLayout.Metrics.inDepth.node.width < 0.3 }
  /// Below this zoom the titles inside the boxes get too small to read, so they move to callouts.
  private var showsCallouts: Bool { scale < 0.55 && !layout.boxes.isEmpty }

  var body: some View {
    // Hovering a card lights up its connections; selecting one also fades everything it doesn't touch.
    // A walkthrough step lights up its components and the connections between them.
    let focus = selection ?? hovered
    let highlighted: Set<String> = if highlightAll {
      Set(layout.routes.map(\.id))
    } else if let spotlight, selection == nil {
      Set(layout.routes.filter { spotlight.contains($0.from) && spotlight.contains($0.to) || $0.from == hovered || $0.to == hovered }.map(\.id))
    } else {
      Set(layout.routes.filter { $0.from == focus || $0.to == focus }.map(\.id))
    }
    let neighbors = Set(layout.routes.filter { $0.from == selection || $0.to == selection }.flatMap { [$0.from, $0.to] })
    let fading = selection != nil || spotlight != nil

    ZStack(alignment: .topLeading) {
      ForEach(layout.boxes, id: \.id) { box in
        GroupBoxView(box: box, change: diagram.diff?.groups[box.id], count: diagram.architecture.nodes.filter { $0.group == box.id }.count, hidesTitle: showsCallouts)
          .frame(width: box.frame.width, height: box.frame.height)
          .position(x: box.frame.midX, y: box.frame.midY)
          .allowsHitTesting(false)
          .transition(.opacity)
      }

      ForEach(layout.routes, id: \.shapeID) { route in
        let edge = diagram.architecture.edges.first { $0.id == route.id }
        EdgeView(
          route: route,
          kind: edge?.edgeKind ?? .calls,
          change: diagram.diff?.edges[route.id],
          color: diagram.architecture.node(route.from)?.nodeKind.color ?? .accentColor,
          isHighlighted: highlighted.contains(route.id),
          isDimmed: fading && !highlighted.contains(route.id),
          scale: scale
        )
        .transition(.opacity)
      }

      ForEach(layout.routes) { route in
        if route.labelSpot != nil, highlighted.contains(route.id) || (showLabels && scale >= 0.6 && !fading) {
          label(route, highlighted: highlighted.contains(route.id))
        }
      }

      ForEach(diagram.architecture.nodes) { node in
        if let frame = layout.nodes[node.id] {
          NodeCard(
            node: node,
            level: diagram.level,
            change: diagram.diff?.nodes[node.id],
            isSelected: selection == node.id || (selection == nil && spotlight?.contains(node.id) == true),
            isHovered: hovered == node.id,
            isDimmed: isDimmed(node.id, neighbors: neighbors),
            isTouched: diagram.touched.contains(node.id)
          )
          // Gestures go on the card itself: after .position they would cover the whole canvas.
          .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .onHover { onHover(node.id, $0) }
          .onTapGesture { onSelect(node.id) }
          .simultaneousGesture(TapGesture(count: 2).onEnded { onFocus(node.id) })
          .position(x: frame.midX, y: frame.midY)
          .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
      }

      // A highlighted label with no free spot sits on its curve, over the cards it would hide behind.
      ForEach(layout.routes) { route in
        if route.labelSpot == nil, highlighted.contains(route.id) {
          label(route, highlighted: true)
        }
      }

      if showsCallouts {
        ForEach(Callout.place(layout.boxes, architecture: diagram.architecture, nodes: layout.nodes, scale: scale)) { callout in
          CalloutView(callout: callout, scale: scale) { onFrame(callout.nodes) }
        }
        .transition(.opacity)
      }
    }
    .frame(width: layout.bounds.maxX, height: layout.bounds.maxY, alignment: .topLeading)
    .animation(.smooth(duration: 0.45), value: layout.nodes)
    .animation(.smooth(duration: 0.25), value: showsCallouts)
  }

  /// A connection's label, with its note in the technical view.
  @ViewBuilder
  private func label(_ route: DiagramLayout.Route, highlighted: Bool) -> some View {
    let edge = diagram.architecture.edges.first { $0.id == route.id }
    let note = layout.metrics.notes ? edge?.note.flatMap { $0.isEmpty ? nil : $0 } : nil
    if let edge, !(edge.label ?? "").isEmpty || note != nil {
      EdgeLabel(text: edge.label ?? "", note: note, change: diagram.diff?.edges[route.id], isHighlighted: highlighted)
        .position(route.labelPoint)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
  }

  private func isDimmed(_ id: String, neighbors: Set<String>) -> Bool {
    if id == hovered { return false }
    if let selection { return id != selection && !neighbors.contains(id) }
    if let spotlight { return !spotlight.contains(id) }
    return farOut
  }
}

/// The grid behind a diagram, drawn in screen space so it stays sharp at every zoom: blueprint lines,
/// a dark screen with scanlines, a plain surface, or the character cells of a sheet of ASCII art.
struct GridBackground: View, Animatable {
  var scale: CGFloat
  var offset: CGSize
  var scheme: ColorScheme
  var theme: DiagramTheme = .blueprint

  /// SwiftUI reads this from its display link thread while a zoom animates, so it can't be main-actor isolated.
  nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
    get { AnimatablePair(scale, AnimatablePair(offset.width, offset.height)) }
    set {
      scale = newValue.first
      offset = CGSize(width: newValue.second.first, height: newValue.second.second)
    }
  }

  var body: some View {
    Canvas { context, size in
      let dark = scheme == .dark
      let (top, bottom): (Color, Color) = switch theme {
      case .blueprint: (Theme.backgroundTop(scheme), Theme.backgroundBottom(scheme))
      case .terminal: (Color(hex: 0x020806), Color(hex: 0x041009))
      case .minimal: dark ? (Color(hex: 0x141416), Color(hex: 0x141416)) : (Color(hex: 0xF7F7F8), Color(hex: 0xF7F7F8))
      case .ascii: (DiagramStyle(.ascii, scheme).paper, DiagramStyle(.ascii, scheme).paper)
      }
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
        Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
      ))

      // Spacing across and down, and how strong each set of lines is.
      let grids: [(CGSize, Double)] = switch theme {
      case .blueprint: [(CGSize(width: 24, height: 24), dark ? 0.055 : 0.045), (CGSize(width: 120, height: 120), dark ? 0.11 : 0.085)]
      case .terminal: [(CGSize(width: 24, height: 24), 0.07)]
      case .minimal: []
      case .ascii: [(CGSize(width: 9, height: 18), dark ? 0.09 : 0.08)]
      }
      let color: Color = switch theme {
      case .terminal: DiagramStyle.phosphor
      case .ascii: DiagramStyle(.ascii, scheme).ink
      default: Theme.grid(scheme)
      }
      for (step, alpha) in grids {
        let spacing = CGSize(width: step.width * scale, height: step.height * scale)
        let smallest = min(spacing.width, spacing.height)
        guard smallest >= 5 else { continue }
        let fade = min(1, (smallest - 5) / 10)
        var path = Path()
        var x = offset.width.truncatingRemainder(dividingBy: spacing.width)
        if x < 0 { x += spacing.width }
        while x < size.width {
          path.move(to: CGPoint(x: x, y: 0))
          path.addLine(to: CGPoint(x: x, y: size.height))
          x += spacing.width
        }
        var y = offset.height.truncatingRemainder(dividingBy: spacing.height)
        if y < 0 { y += spacing.height }
        while y < size.height {
          path.move(to: CGPoint(x: 0, y: y))
          path.addLine(to: CGPoint(x: size.width, y: y))
          y += spacing.height
        }
        context.stroke(path, with: .color(color.opacity(alpha * fade)), lineWidth: theme == .ascii ? 0.5 : 1)
      }

      if theme == .terminal {
        // Scanlines stay put on screen, like on a monitor, whatever the camera does.
        var lines = Path()
        var y: CGFloat = 0
        while y < size.height {
          lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
          y += 3
        }
        context.fill(lines, with: .color(.black.opacity(0.22)))
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
          Gradient(colors: [.clear, .black.opacity(0.45)]),
          center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: min(size.width, size.height) * 0.35,
          endRadius: max(size.width, size.height) * 0.75
        ))
      }
    }
  }
}

struct GroupBoxView: View {
  let box: DiagramLayout.Box
  var change: Change?
  var count: Int
  /// Zoomed out, the name moves to a callout outside the box.
  var hidesTitle: Bool
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  var body: some View {
    if theme == .blueprint {
      blueprint
    } else {
      ThemedBox(name: box.name, count: count, change: change, hidesTitle: hidesTitle)
    }
  }

  private var blueprint: some View {
    let color = Theme.groupColor(box.colorIndex)
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    return ZStack(alignment: .topLeading) {
      shape.fill(color.opacity(scheme == .dark ? 0.07 : 0.06))
      if let change, change == .added || change == .removed {
        shape.strokeBorder(change.color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
      } else {
        shape.strokeBorder(color.opacity(scheme == .dark ? 0.32 : 0.4), lineWidth: 1)
      }
      HStack(spacing: 7) {
        Circle().fill(color).frame(width: 6, height: 6)
        Text(box.name.uppercased())
          .font(.system(size: 11, weight: .bold))
          .tracking(1.3)
          .foregroundStyle(color.mix(with: scheme == .dark ? .white : .black, by: 0.15))
        Text("\(count)")
          .font(.system(size: 10, weight: .semibold).monospacedDigit())
          .foregroundStyle(.secondary)
        if let change, change == .added || change == .removed {
          Text(change.badge)
            .font(.system(size: 8.5, weight: .heavy))
            .foregroundStyle(change.color)
        }
      }
      .padding(.leading, 20)
      .padding(.top, 16)
      .opacity(hidesTitle ? 0 : 1)
    }
    .animation(.smooth(duration: 0.25), value: hidesTitle)
  }
}

/// A group, lane or store in a theme other than Blueprint.
struct ThemedBox: View {
  let name: String
  var count: Int?
  var change: Change?
  var hidesTitle = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  var body: some View {
    let style = DiagramStyle(theme, scheme)
    let shape = RoundedRectangle(cornerRadius: style.boxRadius, style: .continuous)
    let marked = change == .added || change == .removed
    ZStack(alignment: .top) {
      switch theme {
      case .terminal:
        shape.fill(DiagramStyle.phosphor.opacity(0.025))
        shape.strokeBorder(marked ? change!.color : DiagramStyle.phosphor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
      case .ascii:
        shape.strokeBorder(marked ? change!.color : style.ink, lineWidth: 1)
        shape.inset(by: 3.5).strokeBorder(marked ? change!.color : style.ink, lineWidth: 1)
      default:
        shape.fill(style.ink.opacity(scheme == .dark ? 0.035 : 0.025))
        shape.strokeBorder(marked ? change!.color : style.border, style: StrokeStyle(lineWidth: 1, dash: marked ? [6, 4] : []))
      }
      if !name.isEmpty {
        title(style)
          .opacity(hidesTitle ? 0 : 1)
      }
    }
    .animation(.smooth(duration: 0.25), value: hidesTitle)
  }

  @ViewBuilder
  private func title(_ style: DiagramStyle) -> some View {
    let badge = change.flatMap { $0 == .added || $0 == .removed ? $0 : nil }
    switch theme {
    case .ascii:
      // The name sits in the top border, like ??Mac app?? in a box drawn with characters.
      HStack(spacing: 6) {
        Text(name)
        if let badge { Text("[\(badge.badge)]").foregroundStyle(badge.color) }
      }
      .font(style.font(12, .medium))
      .foregroundStyle(style.ink)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(style.paper)
      .offset(y: -8)
    case .terminal:
      HStack(spacing: 8) {
        Text("[ \(name.uppercased()) ]")
        if let count { Text("\(count)").foregroundStyle(style.secondaryInk) }
        if let badge { Text(badge.badge).foregroundStyle(badge.color) }
      }
      .font(style.font(11, .bold))
      .foregroundStyle(style.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 16)
      .padding(.top, 14)
    default:
      HStack(spacing: 7) {
        Text(name.uppercased())
          .tracking(1.1)
          .foregroundStyle(style.secondaryInk)
        if let count { Text("\(count)").foregroundStyle(style.ink.opacity(0.3)) }
        if let badge { Text(badge.badge).foregroundStyle(badge.color) }
      }
      .font(style.font(10.5, .semibold))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 20)
      .padding(.top, 16)
    }
  }
}

/// A group's name outside its box, with a line that points at the box, for when the diagram is zoomed out.
struct Callout: Identifiable {
  var id: String
  var name: String
  var colorIndex: Int
  var nodes: [String]
  var label: CGRect
  var from: CGPoint
  var to: CGPoint

  /// Places one callout per box, in world coordinates, at a constant size on screen.
  /// Each tries above, below, left and right of its box, then the same farther out, then above or
  /// below its whole column, and takes the first spot that covers no box, card or callout, with an
  /// arrow that crosses no other callout. Near spots also keep the arrow clear of other boxes.
  static func place(_ boxes: [DiagramLayout.Box], architecture: Architecture, nodes: [String: CGRect], scale: CGFloat) -> [Callout] {
    let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    let gap = 24 / scale
    let pad = 6 / scale
    let grouped = Set(architecture.nodes.filter { $0.group != nil }.map(\.id))
    var taken = boxes.map(\.frame) + nodes.filter { !grouped.contains($0.key) }.map(\.value)
    var callouts: [Callout] = []

    func crosses(_ from: CGPoint, _ to: CGPoint, _ rects: [CGRect]) -> Bool {
      (1..<20).contains { step in
        let t = CGFloat(step) / 20
        let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        return rects.contains { $0.insetBy(dx: pad, dy: pad).contains(point) }
      }
    }

    for box in boxes {
      let text = (box.name as NSString).size(withAttributes: [.font: font]).width
      let size = CGSize(width: (text + 44) / scale, height: 28 / scale)
      let frame = box.frame
      let column = boxes.map(\.frame).filter { $0.maxX > frame.minX && $0.minX < frame.maxX }.reduce(frame) { $0.union($1) }
      let others = boxes.map(\.frame).filter { $0 != frame }
      let labels = callouts.map(\.label)

      func label(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: x - size.width / 2, y: y - size.height / 2, width: size.width, height: size.height)
      }
      func above(_ r: CGRect) -> (CGRect, CGPoint, CGPoint) { (r, CGPoint(x: r.midX, y: r.maxY), CGPoint(x: frame.midX, y: frame.minY)) }
      func below(_ r: CGRect) -> (CGRect, CGPoint, CGPoint) { (r, CGPoint(x: r.midX, y: r.minY), CGPoint(x: frame.midX, y: frame.maxY)) }

      var near: [(CGRect, CGPoint, CGPoint)] = []
      for distance in [1.0, 2.2, 3.6] {
        let g = gap * distance
        near.append(above(label(frame.midX, frame.minY - g - size.height / 2)))
        near.append(below(label(frame.midX, frame.maxY + g + size.height / 2)))
        let left = label(frame.minX - g - size.width / 2, frame.midY)
        near.append((left, CGPoint(x: left.maxX, y: left.midY), CGPoint(x: frame.minX, y: frame.midY)))
        let right = label(frame.maxX + g + size.width / 2, frame.midY)
        near.append((right, CGPoint(x: right.minX, y: right.midY), CGPoint(x: frame.maxX, y: frame.midY)))
      }
      var far: [(CGRect, CGPoint, CGPoint)] = []
      for shift in [0, -0.8, 0.8, -1.6, 1.6] {
        let x = frame.midX + size.width * shift
        far.append(above(label(x, column.minY - gap - size.height / 2)))
        far.append(below(label(x, column.maxY + gap + size.height / 2)))
      }

      func isFree(_ candidate: (CGRect, CGPoint, CGPoint)) -> Bool {
        let padded = candidate.0.insetBy(dx: -pad, dy: -pad)
        return !taken.contains { $0.intersects(padded) } && !crosses(candidate.1, candidate.2, labels)
      }
      let free = near.first { isFree($0) && !crosses($0.1, $0.2, others) } ?? far.first(where: isFree)
      var chosen = free ?? far[0]
      if free == nil {
        // Every spot is taken: stack above the column until it's clear of the other callouts.
        while callouts.contains(where: { $0.label.insetBy(dx: -pad, dy: -pad).intersects(chosen.0) }) {
          chosen.0 = chosen.0.offsetBy(dx: 0, dy: -(size.height + pad))
          chosen.1 = CGPoint(x: chosen.0.midX, y: chosen.0.maxY)
        }
      }
      taken.append(chosen.0)
      callouts.append(Callout(
        id: box.id,
        name: box.name,
        colorIndex: box.colorIndex,
        nodes: architecture.nodes.filter { $0.group == box.id }.map(\.id),
        label: chosen.0,
        from: chosen.1,
        to: chosen.2
      ))
    }
    return callouts
  }
}

struct LeaderShape: Shape {
  let from: CGPoint
  let to: CGPoint
  let arrow: CGFloat

  func path(in rect: CGRect) -> Path {
    let dx = to.x - from.x, dy = to.y - from.y
    let length = max(sqrt(dx * dx + dy * dy), 0.001)
    let direction = CGVector(dx: dx / length, dy: dy / length)
    let inset = ArrowHead.lineInset(arrow)
    var path = Path()
    path.move(to: from)
    path.addLine(to: CGPoint(x: to.x - direction.dx * inset, y: to.y - direction.dy * inset))
    path.addPath(ArrowHead.path(tip: to, direction: direction, length: arrow))
    return path
  }
}

struct CalloutView: View {
  let callout: Callout
  let scale: CGFloat
  let open: () -> Void
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  var body: some View {
    let style = DiagramStyle(theme, scheme)
    let blueprint = theme == .blueprint
    let color = blueprint ? Theme.groupColor(callout.colorIndex) : style.ink
    let rounded = blueprint || theme == .minimal
    let shape = RoundedRectangle(cornerRadius: rounded ? callout.label.height / 2 : style.cardRadius / scale, style: .continuous)
    ZStack(alignment: .topLeading) {
      let leader = LeaderShape(from: callout.from, to: callout.to, arrow: 11 / scale)
      leader
        .stroke(color.opacity(blueprint ? 1 : 0.7), style: StrokeStyle(lineWidth: (blueprint ? 1.6 : 1.1) / scale, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
      leader
        .fill(color.opacity(blueprint ? 1 : 0.7))
        .allowsHitTesting(false)

      HStack(spacing: 6 / scale) {
        if blueprint { Circle().fill(color).frame(width: 7 / scale, height: 7 / scale) }
        Text(theme == .terminal ? callout.name.uppercased() : callout.name)
          .font(blueprint ? .system(size: 13 / scale, weight: .semibold) : style.font(12.5 / scale, .semibold))
          .foregroundStyle(blueprint ? color.mix(with: scheme == .dark ? .white : .black, by: 0.25) : style.ink)
          .lineLimit(1)
          .fixedSize()
      }
      .frame(width: callout.label.width, height: callout.label.height)
      .background(shape.fill(blueprint ? Theme.backgroundTop(scheme).opacity(0.96) : style.paper))
      .overlay(shape.strokeBorder(blueprint ? color.opacity(0.7) : style.border, lineWidth: (blueprint ? 1.2 : style.borderWidth) / scale))
      .shadow(color: blueprint ? .black.opacity(scheme == .dark ? 0.4 : 0.12) : style.glow(0.25), radius: 6 / scale, y: blueprint ? 2 / scale : 0)
      // The tap goes on the label itself: after .position it would cover the whole canvas.
      .contentShape(shape)
      .onTapGesture(perform: open)
      .position(x: callout.label.midX, y: callout.label.midY)
    }
  }
}

/// Every point of a route as one list, so SwiftUI can animate a route from one layout to the next.
struct RoutePoints: VectorArithmetic {
  var values: [CGFloat]

  static var zero: RoutePoints { RoutePoints(values: []) }

  static func + (lhs: RoutePoints, rhs: RoutePoints) -> RoutePoints { combine(lhs, rhs, +) }
  static func - (lhs: RoutePoints, rhs: RoutePoints) -> RoutePoints { combine(lhs, rhs, -) }

  private static func combine(_ a: RoutePoints, _ b: RoutePoints, _ operation: (CGFloat, CGFloat) -> CGFloat) -> RoutePoints {
    let count = max(a.values.count, b.values.count)
    return RoutePoints(values: (0..<count).map { i in
      operation(i < a.values.count ? a.values[i] : 0, i < b.values.count ? b.values[i] : 0)
    })
  }

  mutating func scale(by rhs: Double) { values = values.map { $0 * CGFloat(rhs) } }
  var magnitudeSquared: Double { values.reduce(0) { $0 + Double($1 * $1) } }
}

extension DiagramLayout.Route {
  var points: RoutePoints {
    get {
      RoutePoints(values: segments.flatMap { [$0.start.x, $0.start.y, $0.control1.x, $0.control1.y, $0.control2.x, $0.control2.y, $0.end.x, $0.end.y] })
    }
    set {
      guard newValue.values.count == segments.count * 8 else { return }
      let v = newValue.values
      segments = segments.indices.map { i in
        let o = i * 8
        return DiagramLayout.Segment(
          start: CGPoint(x: v[o], y: v[o + 1]),
          control1: CGPoint(x: v[o + 2], y: v[o + 3]),
          control2: CGPoint(x: v[o + 4], y: v[o + 5]),
          end: CGPoint(x: v[o + 6], y: v[o + 7])
        )
      }
    }
  }
}

struct RouteShape: Shape {
  var route: DiagramLayout.Route
  /// How much shorter the line ends, so it stops inside the arrowhead.
  var endInset: CGFloat = 0
  /// Straight runs with right-angle turns instead of curves.
  var orthogonal = false

  var animatableData: RoutePoints {
    get { route.points }
    set { route.points = newValue }
  }

  func path(in rect: CGRect) -> Path {
    if orthogonal {
      var points = route.corners
      guard points.count >= 2 else { return Path() }
      let a = points[points.count - 2], b = points[points.count - 1]
      let run = hypot(b.x - a.x, b.y - a.y)
      if endInset > 0, run > 0 {
        let cut = min(endInset, run)
        points[points.count - 1] = CGPoint(x: b.x - (b.x - a.x) / run * cut, y: b.y - (b.y - a.y) / run * cut)
      }
      return Path { path in path.addLines(points) }
    }
    guard endInset > 0, var last = route.segments.last else { return route.path }
    let direction = route.arrival
    let shift = CGVector(dx: -direction.dx * endInset, dy: -direction.dy * endInset)
    last.end = CGPoint(x: last.end.x + shift.dx, y: last.end.y + shift.dy)
    last.control2 = CGPoint(x: last.control2.x + shift.dx, y: last.control2.y + shift.dy)
    var shortened = route
    shortened.segments[shortened.segments.count - 1] = last
    return shortened.path
  }
}

/// A slim arrowhead with a notched back. Lines stop inside the notch, so the head stays sharp.
enum ArrowHead {
  /// The gap between the tip and the card it points at.
  static let clearance: CGFloat = 2

  static func path(tip: CGPoint, direction: CGVector, length: CGFloat) -> Path {
    let half = length * 0.4
    let normal = CGVector(dx: -direction.dy, dy: direction.dx)
    let back = CGPoint(x: tip.x - direction.dx * length, y: tip.y - direction.dy * length)
    let notch = CGPoint(x: tip.x - direction.dx * length * 0.7, y: tip.y - direction.dy * length * 0.7)
    return Path { path in
      path.move(to: tip)
      path.addLine(to: CGPoint(x: back.x + normal.dx * half, y: back.y + normal.dy * half))
      path.addLine(to: notch)
      path.addLine(to: CGPoint(x: back.x - normal.dx * half, y: back.y - normal.dy * half))
      path.closeSubpath()
    }
  }

  /// How far before the tip a line should end to meet the head inside its notch.
  static func lineInset(_ length: CGFloat) -> CGFloat { length * 0.55 }
}

struct ArrowShape: Shape {
  var route: DiagramLayout.Route
  var length: CGFloat
  var orthogonal = false

  var animatableData: RoutePoints {
    get { route.points }
    set { route.points = newValue }
  }

  func path(in rect: CGRect) -> Path {
    guard let end = route.segments.last?.end else { return Path() }
    let direction = orthogonal ? route.cornerArrival : route.arrival
    let tip = CGPoint(x: end.x - direction.dx * ArrowHead.clearance, y: end.y - direction.dy * ArrowHead.clearance)
    return ArrowHead.path(tip: tip, direction: direction, length: length)
  }
}

struct EdgeView: View {
  let route: DiagramLayout.Route
  let kind: EdgeKind
  var change: Change?
  var color: Color
  var isHighlighted: Bool
  var isDimmed: Bool
  var scale: CGFloat
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme
  @State private var phase: CGFloat = 0

  private var stroke: Color {
    if let change, change != .unchanged { return change.color }
    switch theme {
    case .blueprint: return isHighlighted ? color.mix(with: .white, by: scheme == .dark ? 0.2 : 0) : Theme.edge(scheme)
    default: return DiagramStyle(theme, scheme).ink
    }
  }

  private var opacity: Double {
    if isDimmed { return 0.1 }
    if isHighlighted { return 1 }
    if let change { return change == .unchanged ? 0.22 : 0.95 }
    switch theme {
    case .blueprint: return scheme == .dark ? 0.4 : 0.42
    case .terminal: return 0.42
    case .minimal: return scheme == .dark ? 0.32 : 0.28
    case .ascii: return 0.72
    }
  }

  /// Blueprint and Terminal show data moving along a highlighted connection; the quieter themes don't.
  private var flows: Bool { theme == .blueprint || theme == .terminal }
  /// The pulses' length and spacing, in world points. They stay fixed as you zoom, so the looping phase never jumps.
  private static let pulse: CGFloat = 10
  private static let gap: CGFloat = 34

  var body: some View {
    let base: (normal: CGFloat, highlighted: CGFloat) = switch theme {
    case .blueprint: (1.3, 2.2)
    case .terminal: (1.1, 1.8)
    case .minimal: (1, 1.6)
    case .ascii: (1.1, 2)
    }
    let width = (isHighlighted ? base.highlighted : base.normal) / max(min(scale, 1), 0.5)
    let dash: [CGFloat] = change == .removed ? [6, 5] : kind == .sends ? [7, 5] : []
    let arrow = (theme == .minimal ? 7 : 9) + width * 2.4
    let inset = ArrowHead.clearance + ArrowHead.lineInset(arrow)
    let orthogonal = DiagramStyle(theme, scheme).isOrthogonal
    ZStack {
      if isHighlighted, theme == .blueprint {
        // A soft halo in the line's color, so a lit connection stands out without a costly shadow.
        RouteShape(route: route, endInset: inset, orthogonal: orthogonal)
          .stroke(stroke.opacity(scheme == .dark ? 0.26 : 0.18), style: StrokeStyle(lineWidth: width * 3.4, lineCap: .round, lineJoin: .round))
      }
      RouteShape(route: route, endInset: inset, orthogonal: orthogonal)
        .stroke(stroke, style: StrokeStyle(lineWidth: width, lineCap: orthogonal ? .square : .round, lineJoin: orthogonal ? .miter : .round, dash: dash))
      ArrowShape(route: route, length: arrow, orthogonal: orthogonal)
        .fill(stroke)
      ArrowShape(route: route, length: arrow, orthogonal: orthogonal)
        .stroke(stroke, style: StrokeStyle(lineWidth: width * 0.6, lineJoin: .round))
      if isHighlighted, flows {
        // Short pulses inside the line, narrower than it, so data seems to travel through it.
        RouteShape(route: route, endInset: inset + width, orthogonal: orthogonal)
          .stroke(.white.opacity(theme == .terminal ? 0.95 : 0.85), style: StrokeStyle(lineWidth: width * 0.45, lineCap: .round, dash: [Self.pulse, Self.gap], dashPhase: phase))
          .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -(Self.pulse + Self.gap) }
          }
      }
    }
    // One layer, so the line and the head don't darken where they meet.
    .compositingGroup()
    .modifier(Glow(isOn: isHighlighted && theme == .terminal))
    .opacity(opacity)
    .allowsHitTesting(false)
  }
}

/// The phosphor glow of a lit-up line on a terminal. Only applied where it shows, since shadows are costly.
private struct Glow: ViewModifier {
  let isOn: Bool

  func body(content: Content) -> some View {
    if isOn {
      content.shadow(color: DiagramStyle.phosphor.opacity(0.8), radius: 4)
    } else {
      content
    }
  }
}

struct EdgeLabel: View {
  let text: String
  /// What travels over the connection, under the label, in the technical view.
  var note: String?
  var change: Change?
  var isHighlighted: Bool
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  var body: some View {
    if let note {
      noted(note)
    } else {
      plain
    }
  }

  /// The label in bold over its note, in a box as wide as the layout planned for it.
  private func noted(_ note: String) -> some View {
    let style = DiagramStyle(theme, scheme)
    let blueprint = theme == .blueprint
    let color = change.flatMap { $0 == .unchanged ? nil : $0.color }
    let shape = RoundedRectangle(cornerRadius: blueprint ? 9 : style.cardRadius, style: .continuous)
    return VStack(alignment: .leading, spacing: 3) {
      if !text.isEmpty {
        Text(text)
          .font(blueprint ? .system(size: 10.5, weight: .semibold) : style.font(10.5, .semibold))
          .foregroundStyle(color ?? (blueprint ? Color.primary : style.ink))
          .lineLimit(1)
      }
      Text(note)
        .font(blueprint ? .system(size: 10.5) : style.font(10))
        .foregroundStyle(blueprint ? Color.secondary : style.secondaryInk)
        .lineLimit(5)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(width: DiagramLayout.noteWidth, alignment: .leading)
    .background(shape.fill(blueprint ? Theme.backgroundTop(scheme).opacity(0.95) : style.paper))
    .overlay(shape.strokeBorder(color ?? (blueprint ? (scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)) : style.border), lineWidth: isHighlighted ? 1.5 : (blueprint ? 0.5 : style.borderWidth)))
  }

  @ViewBuilder
  private var plain: some View {
    let style = DiagramStyle(theme, scheme)
    let color = change.map { $0 == .unchanged ? Color.secondary : $0.color }
    switch theme {
    case .blueprint:
      Text(text)
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(color ?? (isHighlighted ? .primary : .secondary))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.backgroundTop(scheme).opacity(0.92)))
        .overlay(Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 0.5))
        .fixedSize()
    default:
      // Plain text on the background, like a label written next to a line.
      Text(text)
        .font(style.font(10, .medium))
        .foregroundStyle(color ?? (isHighlighted ? style.ink : style.secondaryInk))
        .lineLimit(1)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(theme == .minimal ? (scheme == .dark ? Color(hex: 0x141416) : Color(hex: 0xF7F7F8)) : theme == .terminal ? Color(hex: 0x030A06) : style.paper)
        .fixedSize()
    }
  }
}

struct MinimapItem {
  var frame: CGRect
  var color: Color
  /// Groups and lanes draw as faint areas, cards as solid blocks.
  var isArea: Bool
}

struct Minimap: View {
  let bounds: CGRect
  let items: [MinimapItem]
  let camera: Camera
  let canvas: CGSize
  let move: (CGPoint) -> Void

  private let size = CGSize(width: 180, height: 116)

  private var transform: (scale: CGFloat, origin: CGPoint) {
    let scale = min(size.width / max(bounds.width, 1), size.height / max(bounds.height, 1))
    let origin = CGPoint(x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale, y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
    return (scale, origin)
  }

  var body: some View {
    let (scale, origin) = transform
    func map(_ rect: CGRect) -> CGRect {
      CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }
    return Canvas { context, _ in
      for item in items where item.isArea {
        context.fill(Path(roundedRect: map(item.frame), cornerRadius: 3), with: .color(item.color.opacity(0.22)))
      }
      for item in items where !item.isArea {
        context.fill(Path(roundedRect: map(item.frame), cornerRadius: 1.5), with: .color(item.color.opacity(0.9)))
      }
      let visible = CGRect(origin: camera.world(.zero), size: CGSize(width: canvas.width / camera.scale, height: canvas.height / camera.scale))
      let viewport = map(visible).intersection(CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
      if !viewport.isNull {
        context.fill(Path(roundedRect: viewport, cornerRadius: 3), with: .color(.primary.opacity(0.06)))
        context.stroke(Path(roundedRect: viewport, cornerRadius: 3), with: .color(.primary.opacity(0.5)), lineWidth: 1)
      }
    }
    .frame(width: size.width, height: size.height)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    .contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
      move(CGPoint(x: (value.location.x - origin.x) / scale, y: (value.location.y - origin.y) / scale))
    })
    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
  }
}

struct ZoomControls: View {
  let scale: CGFloat
  let perform: (CanvasRequest.Action) -> Void

  var body: some View {
    HStack(spacing: 2) {
      button("minus", "Zoom Out (??)") { perform(.zoomOut) }
      Button { perform(.actualSize) } label: {
        Text("\(Int((scale * 100).rounded()))%")
          .font(.system(size: 11, weight: .medium).monospacedDigit())
          .frame(width: 44, height: 28)
          .contentShape(Rectangle())
      }
      .help("Actual Size (?0)")
      button("plus", "Zoom In (?=)") { perform(.zoomIn) }
      Divider().frame(height: 16).padding(.horizontal, 2)
      button("arrow.up.left.and.arrow.down.right", "Zoom to Fit (?1)") { perform(.fit) }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 6)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
  }

  private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .help(help)
  }
}

/// Scroll and pinch events reach the canvas through a local monitor, since SwiftUI has no scroll-wheel modifier on macOS.
@MainActor
final class EventMonitor {
  private var token: Any?

  func start(_ handler: @escaping (NSEvent) -> NSEvent?) {
    stop()
    token = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify], handler: handler)
  }

  func stop() {
    if let token { NSEvent.removeMonitor(token) }
    token = nil
  }
}
