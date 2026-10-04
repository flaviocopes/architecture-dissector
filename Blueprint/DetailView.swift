import SwiftUI

struct DetailView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    @Bindable var store = store
    if let app = store.selectedApp, let data = store.selectedData {
      ZStack {
        if let diagram = store.diagram {
          if store.mode == .flows {
            if let flow = store.currentFlow {
              FlowCanvas(flow: flow, architecture: diagram.architecture, selection: $store.selectedStep, request: store.canvasRequest)
                .id("\(app.id)/\(flow.id)")
            } else {
              FlowsEmpty(app: app)
            }
          } else if store.mode == .data {
            if diagram.architecture.entities.isEmpty {
              DataEmpty(app: app)
            } else {
              DataCanvas(diagram: diagram, selection: $store.selectedEntity, request: store.canvasRequest)
                .id("\(app.id)/data")
            }
          } else if store.mode == .explainers {
            if let explainer = store.currentExplainer {
              ExplainerPlayer(app: app, explainer: explainer, diagram: diagram)
                .id("\(app.id)/\(explainer.id)")
            } else {
              ExplainersEmpty(app: app)
            }
          } else if let canvas = store.canvasDiagram {
            DiagramCanvas(
              diagram: canvas,
              selection: store.level == .overview ? $store.selectedBlock : $store.selectedNode,
              spotlight: store.canvasSpotlight,
              showLabels: store.showLabels,
              request: store.canvasRequest
            )
            .id(app.id)
          } else {
            OverviewEmpty(app: app)
          }
        } else {
          EmptyArchitecture(app: app)
        }
      }
      .overlay(alignment: .top) {
        Group {
          if store.mode == .flows {
            if store.flows.count > 1 {
              let items = store.flowSections.flatMap { section in
                section.flows.map { ChipPicker.Item(id: $0.id, title: $0.title, section: section.title) }
              }
              ChipPicker(items: items, selected: store.currentFlow?.id) { store.selectedFlowID = $0 }
            }
          } else if store.mode == .explainers {
            if store.explainers.count > 1 {
              ChipPicker(items: store.explainers.map { .init(id: $0.id, title: $0.title) }, selected: store.currentExplainer?.id) { store.selectedExplainerID = $0 }
            }
          } else {
            VStack(spacing: 10) {
              if store.mode == .architecture, data.current != nil {
                LevelPicker()
              }
              if let step = store.tourStep, let diagram = store.diagram, diagram.architecture.walkthrough.indices.contains(step) {
                TourCard(architecture: diagram.architecture, step: step)
                  .transition(.move(edge: .top).combined(with: .opacity))
              } else {
                TopBanner(app: app, data: data)
              }
            }
          }
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .animation(.smooth(duration: 0.3), value: store.tourStep == nil)
      }
      .overlay(alignment: .bottom) {
        if data.current != nil, store.mode != .explainers {
          Timeline(data: data)
            .padding(.bottom, 16)
        }
      }
      .navigationTitle(store.name(of: app))
      .navigationSubtitle(subtitle(data))
      .toolbar { toolbar(data) }
      .inspector(isPresented: $store.showInspector) {
        Inspector(app: app, data: data)
          .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
      }
    } else {
      WelcomeView()
        .environment(\.diagramTheme, .blueprint)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
  }

  private func subtitle(_ data: AppData) -> String {
    guard let snapshot = data.snapshot(store.viewing) else { return "Not mapped yet" }
    let architecture = snapshot.architecture
    var parts = ["\(architecture.nodes.count) components", "\(architecture.edges.count) connections"]
    parts.append("saved \(snapshot.savedAt.formatted(.relative(presentation: .named)))")
    return parts.joined(separator: " · ")
  }

  @ToolbarContentBuilder
  private func toolbar(_ data: AppData) -> some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Picker("Show", selection: Binding(get: { store.mode }, set: { store.mode = $0 })) {
        ForEach(CanvasMode.allCases, id: \.self) { mode in
          Text(mode.label).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .help("Show how the app is built, what people do with it, what it stores, or explainers about it (⇧⌘A, ⇧⌘F, ⇧⌘D, ⇧⌘E)")
      .disabled(data.current == nil)
    }

    ToolbarItemGroup {
      Menu {
        Picker("Version", selection: Binding(get: { store.viewing }, set: { store.viewing = $0 })) {
          ForEach(data.refs.reversed(), id: \.self) { ref in
            Text(ref.label).tag(ref)
          }
        }
        .pickerStyle(.inline)
        Divider()
        Button("Save Current as Version…") { store.isSavingVersion = true }
          .disabled(data.current == nil)
      } label: {
        Label(store.viewing.label, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
          .labelStyle(.titleAndIcon)
      }
      .help("Choose the version to show")
      .disabled(data.current == nil)

      Menu {
        Button("Don't Compare") { store.comparing = nil }
        Divider()
        ForEach(data.refs.reversed().filter { $0 != store.viewing }, id: \.self) { ref in
          Button("Changes Since \(ref.label)") { store.comparing = ref }
        }
      } label: {
        Label(store.comparing.map { "Since \($0.label)" } ?? "Compare", systemImage: "plusminus")
          .labelStyle(.titleAndIcon)
      }
      .help("Highlight what changed since another version")
      .disabled(data.refs.count < 2)
    }

    ToolbarItemGroup {
      Menu {
        Picker("Theme", selection: Binding(get: { store.diagramTheme }, set: { store.diagramTheme = $0 })) {
          ForEach(DiagramTheme.allCases, id: \.self) { theme in
            Text(theme.label).tag(theme)
          }
        }
        .pickerStyle(.inline)
      } label: {
        Label("Theme", systemImage: "paintpalette")
      }
      .help("Choose how the diagrams look")

      Toggle(isOn: Binding(get: { store.showLabels }, set: { store.showLabels = $0 })) {
        Label("Labels", systemImage: "text.bubble")
      }
      .help("Show connection labels (⌘L)")

      Button { store.request(.fit) } label: {
        Label("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
      }
      .help("Zoom to fit (⌘1)")

      Button { store.showInspector.toggle() } label: {
        Label("Inspector", systemImage: "sidebar.right")
      }
      .help("Show or hide the inspector (⌥⌘I)")
    }
  }
}

/// One step of the walkthrough, over the canvas, with the components it involves highlighted below.
struct TourCard: View {
  @Environment(AppStore.self) private var store
  let architecture: Architecture
  let step: Int

  var body: some View {
    let steps = architecture.walkthrough
    let current = steps[step]
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text("How it works · \(step + 1) of \(steps.count)".uppercased())
          .font(.system(size: 10, weight: .bold))
          .tracking(1)
          .foregroundStyle(.secondary)
        Spacer()
        HStack(spacing: 4) {
          ForEach(steps.indices, id: \.self) { index in
            Capsule()
              .fill(index == step ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.15)))
              .frame(width: index == step ? 16 : 6, height: 6)
              .contentShape(Rectangle())
              .onTapGesture { store.startTour(at: index) }
          }
        }
        Button { store.endTour() } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("End the walkthrough (Esc)")
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(current.title)
          .font(.system(size: 18, weight: .bold))
        if !current.text.isEmpty {
          Text(current.text)
            .font(.system(size: 13.5))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .id(step)
      .transition(.opacity)

      WrapLayout(spacing: 6) {
        ForEach(current.nodes, id: \.self) { id in
          if let node = architecture.node(id) {
            HStack(spacing: 5) {
              KindTile(kind: node.nodeKind, size: 16)
              Text(node.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            }
            .padding(.leading, 3)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(node.nodeKind.color.opacity(0.12), in: Capsule())
          }
        }
      }

      HStack {
        Button("Back") { store.previousStep() }
          .disabled(step == 0)
        Spacer()
        Text("← → to move, Esc to close")
          .font(.system(size: 10.5))
          .foregroundStyle(.tertiary)
        Spacer()
        Button(step + 1 < steps.count ? "Next" : "Done") { store.nextStep() }
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(18)
    .frame(maxWidth: 460)
    .background(.regularMaterial, in: shape)
    .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
    .animation(.smooth(duration: 0.3), value: step)
  }
}

/// Overview, In Depth or Technical, as pills on one track over the architecture. The selection slides over.
struct LevelPicker: View {
  @Environment(AppStore.self) private var store
  @Namespace private var selection

  var body: some View {
    HStack(spacing: 2) {
      ForEach(DiagramLevel.allCases, id: \.self) { level in
        LevelPill(level: level, isSelected: store.level == level, selection: selection) {
          store.level = level
        }
      }
    }
    .padding(3)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
    .fixedSize()
    .animation(.snappy(duration: 0.25), value: store.level)
  }
}

private struct LevelPill: View {
  let level: DiagramLevel
  let isSelected: Bool
  let selection: Namespace.ID
  let action: () -> Void

  @Environment(\.colorScheme) private var scheme
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Label {
        Text(level.label)
          .foregroundStyle(isSelected || isHovering ? Color.primary : .secondary)
      } icon: {
        Image(systemName: level.symbol)
          .foregroundStyle(isSelected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(.secondary))
      }
      .font(.callout.weight(.medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background {
        if isSelected {
          Capsule()
            .fill(scheme == .dark ? Color.white.opacity(0.14) : .white)
            .shadow(color: .black.opacity(scheme == .light ? 0.12 : 0), radius: 1.5, y: 1)
            .matchedGeometryEffect(id: "selection", in: selection)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(level.help)
    .accessibilityLabel(level.label)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// The overview level of an app no agent wrote an overview for yet.
struct OverviewEmpty: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp

  var body: some View {
    ZStack {
      WelcomeBackground()
      VStack(spacing: 16) {
        Image(systemName: "square.grid.2x2")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(Theme.brand)
        Text("No overview yet")
          .font(.title2.weight(.bold))
        Text("The overview explains \(store.name(of: app)) in a few blocks and plain words, for someone who has never seen it. In Depth and Technical show its components.")
          .font(.system(size: 13.5))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.overviewPrompt(for: app), prominent: true)
      }
      .frame(width: 480)
      .padding(40)
    }
  }
}

/// The out-of-date warning on the current architecture, the summary of a comparison, or a note that the
/// technical view has little to write on the connections.
struct TopBanner: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let data: AppData
  @State private var copied = false

  var body: some View {
    if let diagram = store.diagram, let diff = diagram.diff, let base = store.comparing {
      let data = store.mode == .data
      let ids = data ? diff.entityIDs : diff.ids
      HStack(spacing: 10) {
        Image(systemName: "plusminus.circle.fill")
          .foregroundStyle(Color.accentColor)
        Text("\(base.label) → \(store.viewing.label)")
          .fontWeight(.semibold)
        HStack(spacing: 8) {
          count(ids(.added).count, "added", Theme.added)
          count(ids(.changed).count, "changed", Theme.changed)
          count(ids(.removed).count, "removed", Theme.removed)
          let connections = diff.edgeIDs(.added).count + diff.edgeIDs(.removed).count + diff.edgeIDs(.changed).count
          if connections > 0, !data {
            Text("\(connections) connection\(connections == 1 ? "" : "s")")
              .foregroundStyle(.secondary)
          }
          if data, diff.entities.values.allSatisfy({ $0 == .unchanged }) {
            Text("No data changes").foregroundStyle(.secondary)
          } else if !data, ids(.added).isEmpty, ids(.changed).isEmpty, ids(.removed).isEmpty, connections == 0 {
            Text(diff.isEmpty ? "No changes" : "Only the data changed").foregroundStyle(.secondary)
          }
        }
        Button { store.comparing = nil } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Stop comparing (Esc)")
      }
      .font(.system(size: 12))
      .pill()
    } else if store.viewing == .current, let status = data.status, status.isStale {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(Theme.stale)
        VStack(alignment: .leading, spacing: 1) {
          Text("\(status.changedFiles.count) file\(status.changedFiles.count == 1 ? "" : "s") changed since the architecture was saved")
            .fontWeight(.semibold)
          Text(staleDetail(status))
            .foregroundStyle(.secondary)
        }
        Button(copied ? "Copied" : "Copy Prompt for Agent") {
          store.copyPrompt(for: app)
          copied = true
          Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
          }
        }
        .controlSize(.small)
      }
      .font(.system(size: 12))
      .pill()
    } else if store.mode == .architecture, store.level == .technical, store.diagram?.architecture.missing.contains("notes") == true {
      HStack(spacing: 10) {
        Image(systemName: "text.bubble")
          .foregroundStyle(Color.accentColor)
        Text("Most connections have no note yet, so the chart can't say what travels over them.")
        Button(copied ? "Copied" : "Copy Prompt for Agent") {
          store.copy(store.notesPrompt(for: app))
          copied = true
          Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
          }
        }
        .controlSize(.small)
      }
      .font(.system(size: 12))
      .pill()
    }
  }

  private func staleDetail(_ status: AppStatus) -> String {
    var parts: [String] = []
    if !status.touched.isEmpty {
      parts.append("\(status.touched.count) component\(status.touched.count == 1 ? "" : "s") touched")
    }
    if !status.uncovered.isEmpty {
      parts.append("\(status.uncovered.count) file\(status.uncovered.count == 1 ? "" : "s") outside every component")
    }
    if let commits = status.commitsSince, commits > 0 {
      parts.append("\(commits) commit\(commits == 1 ? "" : "s") since")
    }
    return parts.joined(separator: " · ")
  }

  @ViewBuilder
  private func count(_ value: Int, _ word: String, _ color: Color) -> some View {
    if value > 0 {
      HStack(spacing: 4) {
        Circle().fill(color).frame(width: 7, height: 7)
        Text("\(value) \(word)")
      }
    }
  }
}

struct Timeline: View {
  @Environment(AppStore.self) private var store
  let data: AppData
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let refs = data.refs
    let viewing = refs.firstIndex(of: store.viewing)
    let base = store.comparing.flatMap { refs.firstIndex(of: $0) }
    let range: ClosedRange<Int>? = if let viewing, let base { min(viewing, base)...max(viewing, base) } else { nil }

    HStack(spacing: 0) {
      ForEach(Array(refs.enumerated()), id: \.element) { index, ref in
        if index > 0 {
          let active = range.map { $0.contains(index - 1) && $0.contains(index) } ?? false
          Button { store.compare(refs[index - 1], ref) } label: {
            ZStack {
              Capsule()
                .fill(active ? AnyShapeStyle(LinearGradient(colors: [Theme.changed, Theme.added], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.primary.opacity(0.18)))
                .frame(width: 34, height: active ? 3 : 2)
              Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(active ? .white : .secondary)
                .padding(3)
                .background(Circle().fill(active ? Theme.added : Color.primary.opacity(0.0001)))
            }
            .frame(width: 40, height: 28)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help("Show what changed from \(refs[index - 1].label) to \(ref.label)")
        }
        chip(ref, isViewing: index == viewing, isBase: index == base)
      }
      if refs.count == 1 {
        Button { store.isSavingVersion = true } label: {
          Label("Save as Version", systemImage: "plus")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Save the current architecture as a version, to compare it with later ones")
      }
    }
    .padding(5)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    .animation(.snappy(duration: 0.25), value: store.viewing)
    .animation(.snappy(duration: 0.25), value: store.comparing)
  }

  private func chip(_ ref: VersionRef, isViewing: Bool, isBase: Bool) -> some View {
    Button {
      if store.comparing != nil, store.comparing != ref {
        store.viewing = ref
      } else {
        store.comparing = nil
        store.viewing = ref
      }
    } label: {
      HStack(spacing: 5) {
        if ref == .current {
          Circle()
            .fill(data.status?.isStale == true ? Theme.stale : Theme.added)
            .frame(width: 6, height: 6)
        }
        Text(ref.label)
          .font(.system(size: 11.5, weight: isViewing ? .semibold : .medium).monospacedDigit())
      }
      .padding(.horizontal, 11)
      .frame(height: 26)
      .foregroundStyle(isViewing ? .white : .primary)
      .background {
        if isViewing {
          Capsule().fill(Color.accentColor)
        } else if isBase {
          Capsule().strokeBorder(Theme.changed, lineWidth: 1.5)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .contextMenu {
      if ref != store.viewing {
        Button("Changes Since \(ref.label)") { store.comparing = ref }
      }
      if case .version(let name) = ref {
        Divider()
        Button("Delete Version \(name)", role: .destructive) { store.deleteVersion(name) }
      }
    }
  }
}

/// A tracked app that no agent mapped yet.
struct EmptyArchitecture: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  @State private var appeared = false

  var body: some View {
    let name = store.name(of: app)
    GeometryReader { proxy in
      ScrollView {
        content(name)
          .frame(width: min(560, max(proxy.size.width - 80, 280)))
          .padding(40)
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .background { WelcomeBackground() }
    .onAppear { appeared = true }
  }

  private func content(_ name: String) -> some View {
    VStack(spacing: 24) {
      VStack(spacing: 12) {
        Monogram(name: name, seed: app.id, size: 64)
          .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        Text(name)
          .font(.system(size: 30, weight: .bold))
        Text((app.path as NSString).abbreviatingWithTildeInPath)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      .reveal(appeared, delay: 0)

      HStack(spacing: 9) {
        PulsingDot(color: .accentColor)
        Text("Waiting for an agent to map it")
          .fontWeight(.semibold)
      }
      .font(.system(size: 12.5))
      .pill()
      .reveal(appeared, delay: 0.08)

      VStack(spacing: 14) {
        Text("Paste this into an agent working on \(name). It reads the code and saves the architecture with the blueprint command, and the diagram appears here as soon as it does.")
          .font(.system(size: 13.5))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.prompt(for: app), prominent: true)
        VStack(spacing: 6) {
          CLIStatus()
          SkillStatus()
        }
      }
      .reveal(appeared, delay: 0.16)
    }
  }
}

struct PulsingDot: View {
  let color: Color
  @State private var pulse = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
      .background(
        Circle()
          .fill(color.opacity(0.4))
          .scaleEffect(pulse ? 2.6 : 1)
          .opacity(pulse ? 0 : 1)
      )
      .onAppear {
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
      }
  }
}

extension View {
  func pill() -> some View {
    padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(.regularMaterial, in: Capsule())
      .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
  }
}
