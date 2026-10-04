import SwiftUI

struct Inspector: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let data: AppData

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if store.mode == .flows, let diagram = store.diagram {
          if let flow = store.currentFlow, let id = store.selectedStep, let step = flow.step(id) {
            StepDetails(flow: flow, step: step, architecture: diagram.architecture)
          } else {
            FlowsOverview(app: app, architecture: diagram.architecture)
          }
        } else if store.mode == .explainers, let diagram = store.diagram {
          ExplainersOverview(app: app, architecture: diagram.architecture)
        } else if store.mode == .data, let diagram = store.diagram {
          if let id = store.selectedEntity, let entity = diagram.architecture.entity(id) {
            EntityDetails(app: app, entity: entity, diagram: diagram)
          } else if let diff = diagram.diff {
            DataChangesList(diagram: diagram, diff: diff)
          } else {
            DataOverview(app: app, architecture: diagram.architecture)
          }
        } else if let diagram = store.diagram, let id = store.selectedNode, let node = diagram.architecture.node(id) {
          NodeDetails(app: app, node: node, diagram: diagram, status: store.viewing == .current ? data.status : nil)
        } else if let diagram = store.diagram, let diff = diagram.diff {
          ChangesList(diagram: diagram, diff: diff)
        } else {
          Overview(app: app, data: data)
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct InspectorSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased())
        .font(.system(size: 10, weight: .bold))
        .tracking(1)
        .foregroundStyle(.secondary)
      content
    }
  }
}

struct KindTile: View {
  let kind: NodeKind
  var size: CGFloat = 36

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
      .fill(LinearGradient(colors: [kind.color.mix(with: .white, by: 0.12), kind.color.mix(with: .black, by: 0.22)], startPoint: .top, endPoint: .bottom))
      .overlay(Image(systemName: kind.symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
      .frame(width: size, height: size)
  }
}

struct NodeDetails: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let node: Architecture.Node
  let diagram: Diagram
  let status: AppStatus?

  var body: some View {
    let architecture = diagram.architecture
    let change = diagram.diff?.nodes[node.id]

    HStack(spacing: 12) {
      KindTile(kind: node.nodeKind, size: 42)
      VStack(alignment: .leading, spacing: 2) {
        Text(node.name)
          .font(.title3.weight(.semibold))
          .strikethrough(change == .removed)
        Text([node.nodeKind.label, node.group.flatMap { architecture.group($0)?.name }].compactMap { $0 }.joined(separator: " · "))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }

    if let change, change != .unchanged {
      VStack(alignment: .leading, spacing: 6) {
        Text(change == .added ? "New in \(store.viewing.label)" : change == .removed ? "Removed in \(store.viewing.label)" : "Changed in \(store.viewing.label)")
          .font(.callout.weight(.semibold))
          .foregroundStyle(change.color)
        ForEach(diagram.diff?.nodeDetails[node.id] ?? [], id: \.self) { detail in
          Text(detail).font(.callout)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(change.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    RoleCard(label: "Role in \(architecture.name)", summary: node.summary, details: node.details, color: node.nodeKind.color)

    let stored = architecture.entities.filter { $0.store == node.id }
    if !stored.isEmpty {
      InspectorSection("Data") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(stored) { entity in
            Button { store.showEntity(entity.id) } label: {
              HStack(spacing: 9) {
                Image(systemName: "tablecells")
                  .font(.system(size: 11))
                  .foregroundStyle(node.nodeKind.color)
                  .frame(width: 18)
                Text(entity.name).font(.callout)
                Spacer(minLength: 0)
                Text("\(entity.fields.count)")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.tertiary)
              }
              .padding(.vertical, 4)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(entity.name) in the data")
          }
        }
      }
    }

    let steps = architecture.walkthrough.enumerated().filter { $0.element.nodes.contains(node.id) }
    if !steps.isEmpty {
      InspectorSection("In the walkthrough") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(steps, id: \.offset) { index, step in
            Button { store.startTour(at: index) } label: {
              HStack(spacing: 9) {
                StepNumber(number: index + 1, active: false, size: 20)
                Text(step.title)
                  .font(.callout)
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                  .font(.system(size: 9))
                  .foregroundStyle(.tertiary)
              }
              .padding(.vertical, 4)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show this step of the walkthrough")
          }
        }
      }
    }

    if !node.tech.isEmpty {
      InspectorSection("Tech") {
        WrapLayout(spacing: 6) {
          ForEach(node.tech, id: \.self) { tech in
            Text(tech)
              .font(.system(size: 11, weight: .medium))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(node.nodeKind.color.opacity(0.14), in: Capsule())
          }
        }
      }
    }

    let outgoing = architecture.edges.filter { $0.from == node.id }
    let incoming = architecture.edges.filter { $0.to == node.id }
    if !outgoing.isEmpty || !incoming.isEmpty {
      InspectorSection("Works with") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(outgoing) { edge in connection(edge, other: edge.to, outgoing: true) }
          ForEach(incoming) { edge in connection(edge, other: edge.from, outgoing: false) }
        }
      }
    }

    FilesSection(app: app, paths: node.paths, status: status)
  }

  private func connection(_ edge: Architecture.Edge, other: String, outgoing: Bool) -> some View {
    let target = diagram.architecture.node(other)
    let change = diagram.diff?.edges[edge.id]
    return Button { store.request(.focus(other)) } label: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: outgoing ? "arrow.right" : "arrow.left")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(change.map { $0 == .unchanged ? Color.secondary : $0.color } ?? .secondary)
          .frame(width: 14)
        VStack(alignment: .leading, spacing: 1) {
          Text(target?.name ?? other)
            .font(.callout.weight(.medium))
          if let label = edge.label {
            Text(label).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
        if let change, change != .unchanged {
          Text(change.badge)
            .font(.system(size: 8.5, weight: .heavy))
            .foregroundStyle(change.color)
        }
      }
      .padding(.vertical, 5)
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct Overview: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let data: AppData

  var body: some View {
    let snapshot = data.snapshot(store.viewing)
    let architecture = snapshot?.architecture

    VStack(alignment: .leading, spacing: 8) {
      Text(store.name(of: app))
        .font(.system(size: 22, weight: .bold))
      if let summary = architecture?.summary {
        Text(summary)
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      if let architecture {
        Text("\(architecture.nodes.count) components · \(architecture.edges.count) connections · \(architecture.groups.count) groups")
          .font(.system(size: 11.5))
          .foregroundStyle(.tertiary)
      }
    }

    if let architecture, let snapshot {
      if architecture.walkthrough.isEmpty {
        NoWalkthrough(app: app)
      } else {
        WalkthroughSteps(architecture: architecture)
      }

      Divider()

      if store.viewing == .current, data.current != nil {
        StatusSection(app: app, status: data.status)
      }

      InspectorSection(snapshot.version.map { "Version \($0)" } ?? "Saved") {
        VStack(alignment: .leading, spacing: 4) {
          Label(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
          if let commit = snapshot.commit {
            Label("At commit \(commit)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
          }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      KindsLegend(architecture: architecture)
    }

    InspectorSection("Folder") {
      Button { store.reveal(app) } label: {
        Label((app.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
          .font(.system(size: 11.5, design: .monospaced))
      }
      .buttonStyle(.plain)
      .help("Show in Finder")
    }
  }

}

/// The files that make up a component or define an entity, with the ones changed since the last save marked.
struct FilesSection: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let paths: [String]
  var status: AppStatus?

  var body: some View {
    if !paths.isEmpty {
      InspectorSection("Files") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(paths, id: \.self) { path in
            let changed = status?.changedFiles.contains { $0 == path || $0.hasPrefix(path + "/") } ?? false
            Button { store.reveal(app, path: path) } label: {
              HStack(spacing: 6) {
                Image(systemName: path.contains(".") ? "doc.text" : "folder")
                  .foregroundStyle(.secondary)
                  .frame(width: 16)
                Text(path)
                  .font(.system(size: 11.5, design: .monospaced))
                  .lineLimit(2)
                  .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if changed {
                  Circle().fill(Theme.stale).frame(width: 6, height: 6)
                    .help("Changed since the architecture was saved")
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
          }
        }
      }
    }
  }
}

/// What a component does or what an entity holds, in large type, with the points that make it precise.
struct RoleCard: View {
  let label: String
  let summary: String?
  let details: [String]
  let color: Color
  var placeholder = "No one described this component yet."

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel(label)
      Text(summary ?? placeholder)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(summary == nil ? .secondary : .primary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      if !details.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(details, id: \.self) { detail in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text("•")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(color)
              Text(detail)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
          }
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.22), lineWidth: 1))
  }
}

struct StepNumber: View {
  let number: Int
  var active: Bool
  var size: CGFloat = 22

  var body: some View {
    Text("\(number)")
      .font(.system(size: size * 0.5, weight: .bold).monospacedDigit())
      .foregroundStyle(active ? .white : .secondary)
      .frame(width: size, height: size)
      .background(Circle().fill(active ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.08))))
  }
}

/// The steps of the walkthrough. Clicking one shows it on the canvas.
struct WalkthroughSteps: View {
  @Environment(AppStore.self) private var store
  let architecture: Architecture

  var body: some View {
    let steps = architecture.walkthrough
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionLabel("How it works")
        Spacer()
        Button {
          if store.tourStep == nil { store.startTour() } else { store.endTour() }
        } label: {
          Label(store.tourStep == nil ? "Take the Tour" : "End Tour", systemImage: store.tourStep == nil ? "play.fill" : "stop.fill")
            .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
      VStack(alignment: .leading, spacing: 2) {
        ForEach(steps.indices, id: \.self) { index in
          let step = steps[index]
          let active = store.tourStep == index
          Button {
            if active { store.endTour() } else { store.startTour(at: index) }
          } label: {
            HStack(alignment: .top, spacing: 10) {
              StepNumber(number: index + 1, active: active)
              VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                  .font(.system(size: 13, weight: .semibold))
                if !step.text.isEmpty {
                  Text(step.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 3) {
                  ForEach(step.nodes.prefix(10), id: \.self) { id in
                    if let node = architecture.node(id) {
                      KindTile(kind: node.nodeKind, size: 16).help(node.name)
                    }
                  }
                }
                .padding(.top, 1)
              }
              Spacer(minLength: 0)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Color.accentColor.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      Text("Click any component on the canvas to see its role.")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
  }
}

/// The flows of the app: what each one is for, and the steps of the one on the canvas.
struct FlowsOverview: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let architecture: Architecture

  var body: some View {
    @Bindable var store = store
    VStack(alignment: .leading, spacing: 8) {
      Text("Workflows in \(store.name(of: app))")
        .font(.system(size: 20, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)
      Text("Every workflow, step by step: what people using it do, what the owner does, what agents do, and what the app does on its own. Click a step to see what happens and which components handle it.")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    if architecture.flows.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("No flows yet. Ask an agent to map every workflow of the app.")
          .font(.system(size: 12.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.flowsPrompt(for: app))
      }
    } else {
      Picker("Group", selection: $store.flowGrouping) {
        Text("By who").tag(FlowGrouping.actor)
        Text("By area").tag(FlowGrouping.area)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      ForEach(store.flowSections) { section in
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Image(systemName: section.symbol)
              .font(.system(size: 10, weight: .bold))
              .frame(width: 14)
            Text(section.title.uppercased())
              .font(.system(size: 10, weight: .bold))
              .tracking(1)
            Text("\(section.flows.count)")
              .font(.system(size: 10, weight: .semibold).monospacedDigit())
              .foregroundStyle(.tertiary)
          }
          .foregroundStyle(.secondary)
          ForEach(section.flows) { flow in
            flowCard(flow)
          }
        }
      }
    }
  }

  /// What the card says besides the title: the other way the flows can be grouped.
  private func detail(_ flow: Architecture.Flow) -> String {
    let other = store.flowGrouping == .actor ? flow.area : flow.flowActor?.label
    return ([Self.count(flow.steps.count)] + [other].compactMap { $0 }).joined(separator: " · ")
  }

  private func flowCard(_ flow: Architecture.Flow) -> some View {
    let active = flow.id == store.currentFlow?.id
    return VStack(alignment: .leading, spacing: 8) {
      Button { store.selectedFlowID = flow.id } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(flow.title)
            .font(.system(size: 13.5, weight: .semibold))
          if let goal = flow.goal {
            Text(goal)
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Text(detail(flow))
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if active {
        VStack(alignment: .leading, spacing: 1) {
          ForEach(Array(flow.steps.enumerated()), id: \.element.id) { index, step in
            Button { store.selectedStep = step.id } label: {
              HStack(alignment: .top, spacing: 8) {
                StepKindTile(kind: step.stepKind, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                  Text("\(index + 1). \(step.title)")
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                  if let lane = step.lane {
                    Text(lane).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                  }
                }
                Spacer(minLength: 0)
              }
              .padding(.vertical, 4)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.top, 2)
      }
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1))
  }

  private static func count(_ steps: Int) -> String { "\(steps) step\(steps == 1 ? "" : "s")" }
}

/// One step of a flow: what happens, who does it, the components behind it, and where it leads.
struct StepDetails: View {
  @Environment(AppStore.self) private var store
  let flow: Architecture.Flow
  let step: Architecture.FlowStep
  let architecture: Architecture

  var body: some View {
    let kind = step.stepKind
    let number = (flow.steps.firstIndex { $0.id == step.id } ?? 0) + 1

    Button { store.selectedStep = nil } label: {
      Label(flow.title, systemImage: "chevron.left")
        .font(.system(size: 11.5, weight: .medium))
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help("Back to all flows")

    HStack(alignment: .top, spacing: 12) {
      StepKindTile(kind: kind, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(step.title)
          .font(.title3.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        Text(["Step \(number) of \(flow.steps.count)", kind.label, step.lane].compactMap { $0 }.joined(separator: " · "))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }

    if let text = step.text, !text.isEmpty {
      Text(text)
        .font(.system(size: 15, weight: .medium))
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(kind.color.opacity(0.22), lineWidth: 1))
    }

    let components = step.nodes.compactMap(architecture.node)
    if !components.isEmpty {
      InspectorSection("Handled by") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(components) { node in
            Button { store.showComponent(node.id) } label: {
              HStack(alignment: .top, spacing: 9) {
                KindTile(kind: node.nodeKind, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                  Text(node.name).font(.callout.weight(.medium))
                  if let summary = node.summary {
                    Text(summary)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                  }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                  .font(.system(size: 9, weight: .bold))
                  .foregroundStyle(.tertiary)
              }
              .padding(.vertical, 4)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(node.name) in the architecture")
          }
        }
      }
    }

    let next = flow.next(step)
    InspectorSection(next.isEmpty ? "The end" : "Then") {
      if next.isEmpty {
        Text("This is where the flow ends.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(next, id: \.to) { link in
            if let target = flow.step(link.to) {
              Button { store.selectedStep = target.id } label: {
                HStack(spacing: 8) {
                  Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(target.title).font(.callout.weight(.medium))
                    if let label = link.label { Text(label).font(.caption).foregroundStyle(.secondary) }
                  }
                  Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }

    Text("← → move between steps")
      .font(.system(size: 11))
      .foregroundStyle(.tertiary)
  }
}

struct NoWalkthrough: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionLabel("How it works")
      Text("No walkthrough yet. Ask an agent to add one: a few steps that explain how the app works, and the role of every component.")
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      PromptCard(text: store.walkthroughPrompt(for: app))
    }
  }
}

struct StatusSection: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let status: AppStatus?

  var body: some View {
    InspectorSection("Status") {
      if let status {
        if !status.isRepo {
          Text("This folder isn't a git repository, so Blueprint can't tell when the code changes.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if !status.hasManifest {
          Text("Save the architecture again with blueprint set, so Blueprint can track what changes.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if !status.isStale {
          Label("Up to date with the code", systemImage: "checkmark.circle.fill")
            .foregroundStyle(Theme.added)
            .font(.callout.weight(.medium))
        } else {
          VStack(alignment: .leading, spacing: 10) {
            Label("\(status.changedFiles.count) files changed since the last save", systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(Theme.stale)
              .font(.callout.weight(.medium))
            let touched = store.diagram?.architecture.nodes.filter { status.touched.contains($0.id) } ?? []
            if !touched.isEmpty {
              VStack(alignment: .leading, spacing: 2) {
                ForEach(touched) { node in
                  Button { store.request(.focus(node.id)) } label: {
                    HStack(spacing: 8) {
                      KindTile(kind: node.nodeKind, size: 20)
                      Text(node.name).font(.callout)
                      Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                }
              }
            }
            if !status.uncovered.isEmpty {
              VStack(alignment: .leading, spacing: 3) {
                Text("Outside every component")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                ForEach(status.uncovered.prefix(8), id: \.self) { file in
                  Text(file)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                if status.uncovered.count > 8 {
                  Text("and \(status.uncovered.count - 8) more").font(.caption).foregroundStyle(.secondary)
                }
              }
            }
            Button("Copy Prompt for Agent") { store.copyPrompt(for: app) }
              .controlSize(.small)
          }
        }
      } else {
        ProgressView().controlSize(.small)
      }
    }
  }
}

struct KindsLegend: View {
  let architecture: Architecture

  var body: some View {
    let kinds = NodeKind.allCases.filter { kind in architecture.nodes.contains { $0.nodeKind == kind } }
    InspectorSection("Kinds") {
      WrapLayout(spacing: 6) {
        ForEach(kinds, id: \.self) { kind in
          HStack(spacing: 5) {
            Image(systemName: kind.symbol)
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(kind.color)
            Text(kind.label)
              .font(.system(size: 11))
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(kind.color.opacity(0.12), in: Capsule())
        }
      }
    }
  }
}

struct ChangesList: View {
  @Environment(AppStore.self) private var store
  let diagram: Diagram
  let diff: ArchitectureDiff

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("What changed")
        .font(.title2.weight(.semibold))
      Text("\(store.comparing?.label ?? "") → \(store.viewing.label): \(diff.summary.lowercased()).")
        .foregroundStyle(.secondary)
    }

    ForEach([Change.added, .changed, .removed], id: \.self) { change in
      let ids = diff.ids(change)
      if !ids.isEmpty {
        InspectorSection(change.rawValue) {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(ids, id: \.self) { id in
              if let node = diagram.architecture.node(id) {
                Button { store.request(.focus(id)) } label: {
                  HStack(alignment: .top, spacing: 10) {
                    KindTile(kind: node.nodeKind, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(node.name).font(.callout.weight(.medium))
                      ForEach(change == .changed ? diff.nodeDetails[id] ?? [] : [node.summary].compactMap { $0 }, id: \.self) { line in
                        Text(line)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .fixedSize(horizontal: false, vertical: true)
                      }
                    }
                    Spacer(minLength: 0)
                    Circle().fill(change.color).frame(width: 7, height: 7).padding(.top, 5)
                  }
                  .padding(.vertical, 5)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
    }

    let edges = [Change.added, .changed, .removed].flatMap { change in diff.edgeIDs(change).map { (change, $0) } }
    if !edges.isEmpty {
      InspectorSection("Connections") {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(edges, id: \.1) { change, id in
            if let edge = diagram.architecture.edges.first(where: { $0.id == id }) {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(change.color).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                  Text("\(diagram.architecture.node(edge.from)?.name ?? edge.from) → \(diagram.architecture.node(edge.to)?.name ?? edge.to)")
                    .font(.callout)
                  if let label = edge.label {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                  }
                  ForEach(diff.edgeDetails[id] ?? [], id: \.self) { detail in
                    Text(detail).font(.caption).foregroundStyle(change.color)
                  }
                }
              }
            }
          }
        }
      }
    }

    if diff.isEmpty {
      Text("The two architectures are the same.")
        .foregroundStyle(.secondary)
    }
  }
}

/// The explainers of the app, and the scenes of the one on screen. Clicking a scene jumps to it.
struct ExplainersOverview: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let architecture: Architecture

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Explainers")
        .font(.system(size: 20, weight: .bold))
      Text("Short videos about how parts of \(store.name(of: app)) work. Agents write what each scene shows, and Blueprint plays them all in the same style.")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    if architecture.explainers.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("No explainers yet. Ask an agent to write a few.")
          .font(.system(size: 12.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.explainersPrompt(for: app))
      }
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(architecture.explainers) { explainer in
          let active = explainer.id == store.currentExplainer?.id
          VStack(alignment: .leading, spacing: 8) {
            Button { store.selectedExplainerID = explainer.id } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(explainer.title)
                  .font(.system(size: 13.5, weight: .semibold))
                if let summary = explainer.summary {
                  Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(explainer.scenes.count) scenes · \(ExplainerPlayer.clock(ExplainerSlide.total(explainer)))")
                  .font(.system(size: 10.5).monospacedDigit())
                  .foregroundStyle(.tertiary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if active {
              VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(explainer.scenes.enumerated()), id: \.offset) { index, scene in
                  Button { store.showSlide(index + 1) } label: {
                    HStack(alignment: .top, spacing: 8) {
                      StepNumber(number: index + 1, active: store.explainerScene == index + 1, size: 18)
                      VStack(alignment: .leading, spacing: 1) {
                        Text(scene.title)
                          .font(.system(size: 12, weight: .medium))
                          .fixedSize(horizontal: false, vertical: true)
                        Label(Self.shows(scene, in: architecture), systemImage: Self.symbol(scene))
                          .font(.system(size: 10.5))
                          .foregroundStyle(.tertiary)
                          .lineLimit(1)
                      }
                      Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                }
              }
              .padding(.top, 2)
            }
          }
          .padding(10)
          .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03)))
          .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1))
        }
      }
      Text("Space plays and pauses, ← → move between scenes.")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
  }

  private static func shows(_ scene: Architecture.Scene, in architecture: Architecture) -> String {
    if !scene.nodes.isEmpty { return scene.nodes.map { architecture.node($0)?.name ?? $0 }.joined(separator: ", ") }
    if let id = scene.flow { return architecture.flow(id)?.title ?? id }
    if !scene.entities.isEmpty { return scene.entities.map { architecture.entity($0)?.name ?? $0 }.joined(separator: ", ") }
    return "Title card"
  }

  private static func symbol(_ scene: Architecture.Scene) -> String {
    if !scene.nodes.isEmpty { return "square.grid.3x3.square" }
    if scene.flow != nil { return "point.topleft.down.to.point.bottomright.curvepath" }
    if !scene.entities.isEmpty { return "tablecells" }
    return "textformat"
  }
}

/// Where the app keeps its data, and the entities in each store. Clicking one zooms to it.
struct DataOverview: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let architecture: Architecture

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("What \(store.name(of: app)) stores")
        .font(.system(size: 20, weight: .bold))
        .fixedSize(horizontal: false, vertical: true)
      Text("Each box is a place the app keeps data, and each card one kind of record, field by field. A line runs from a field to the record it points to.")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    if architecture.entities.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("No data yet. Ask an agent to add what the app stores.")
          .font(.system(size: 12.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.dataPrompt(for: app))
      }
    } else {
      let stores = architecture.entities.reduce(into: [String?]()) { stores, entity in
        if !stores.contains(entity.store) { stores.append(entity.store) }
      }
      ForEach(stores, id: \.self) { id in
        let node = id.flatMap(architecture.node)
        InspectorSection(node.map { ([$0.name] + $0.tech.prefix(1)).joined(separator: " · ") } ?? "No store") {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(architecture.entities.filter { $0.store == id }) { entity in
              Button { store.request(.focus(entity.id)) } label: {
                HStack(alignment: .top, spacing: 9) {
                  KindTile(kind: architecture.storeKind(entity), size: 22)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(entity.name).font(.callout.weight(.medium))
                    if let summary = entity.summary {
                      Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }
                  }
                  Spacer(minLength: 0)
                  Text("\(entity.fields.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .help("\(entity.fields.count) fields")
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      Text("Click any card to see its fields and what points to it.")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
  }
}

/// One entity: what a record is, its fields, what points to it, and where it's stored.
struct EntityDetails: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let entity: Architecture.Entity
  let diagram: Diagram

  var body: some View {
    let architecture = diagram.architecture
    let kind = architecture.storeKind(entity)
    let change = diagram.diff?.entities[entity.id]
    let location = entity.store.flatMap(architecture.node)

    HStack(spacing: 12) {
      KindTile(kind: kind, size: 42)
      VStack(alignment: .leading, spacing: 2) {
        Text(entity.name)
          .font(.title3.weight(.semibold))
          .strikethrough(change == .removed)
        Text([location.map { "In \($0.name)" }, "\(entity.fields.count) field\(entity.fields.count == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "))
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }

    if let change, change != .unchanged {
      VStack(alignment: .leading, spacing: 6) {
        Text(change == .added ? "New in \(store.viewing.label)" : change == .removed ? "Removed in \(store.viewing.label)" : "Changed in \(store.viewing.label)")
          .font(.callout.weight(.semibold))
          .foregroundStyle(change.color)
        ForEach(diagram.diff?.entityDetails[entity.id] ?? [], id: \.self) { detail in
          Text(detail).font(.callout)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(change.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    RoleCard(label: "What it holds", summary: entity.summary, details: entity.details, color: kind.color, placeholder: "No one described this entity yet.")

    if !entity.fields.isEmpty {
      InspectorSection("Fields") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(entity.fields, id: \.name) { field in
            fieldRow(field, change: diagram.diff.map { $0.field(field.name, of: entity.id) })
          }
        }
      }
    }

    let referrers = architecture.entities.filter { other in other.id != entity.id && other.fields.contains { $0.ref == entity.id } }
    if !referrers.isEmpty {
      InspectorSection("Pointed to by") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(referrers) { other in
            Button { store.request(.focus(other.id)) } label: {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.left")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(.secondary)
                  .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                  Text(other.name).font(.callout.weight(.medium))
                  Text(other.fields.filter { $0.ref == entity.id }.map(\.name).joined(separator: ", "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }
              .padding(.vertical, 4)
              .padding(.horizontal, 6)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }

    if let location {
      InspectorSection("Stored in") {
        Button { store.showComponent(location.id) } label: {
          HStack(alignment: .top, spacing: 9) {
            KindTile(kind: location.nodeKind, size: 24)
            VStack(alignment: .leading, spacing: 1) {
              Text(location.name).font(.callout.weight(.medium))
              if let summary = location.summary {
                Text(summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.tertiary)
          }
          .padding(.vertical, 4)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(location.name) in the architecture")
      }
    }

    FilesSection(app: app, paths: entity.paths)
  }

  private func fieldRow(_ field: Architecture.Field, change: Change?) -> some View {
    let target = field.ref.flatMap(diagram.architecture.entity)
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: field.isKey ? "key.fill" : field.ref != nil ? "link" : "circle.fill")
        .font(.system(size: field.isKey || field.ref != nil ? 9 : 4, weight: .bold))
        .foregroundStyle(field.isKey ? Color(hex: 0xF59E0B) : field.ref != nil ? diagram.architecture.storeKind(entity).color : Color.secondary)
        .frame(width: 14)
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(field.name)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .strikethrough(change == .removed)
          if let type = field.type {
            Text(type)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }
        if let target {
          Button { store.request(.focus(target.id)) } label: {
            Label(target.name, systemImage: "arrow.right")
              .font(.caption.weight(.medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)
          .help("Show \(target.name)")
        }
        if let note = field.note {
          Text(note)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      if let change, change != .unchanged {
        Text(change.badge)
          .font(.system(size: 8.5, weight: .heavy))
          .foregroundStyle(change.color)
      }
    }
    .padding(.vertical, 4)
  }
}

/// What changed in the data between two versions: new, changed and removed entities.
struct DataChangesList: View {
  @Environment(AppStore.self) private var store
  let diagram: Diagram
  let diff: ArchitectureDiff

  var body: some View {
    let counts = [Change.added, .changed, .removed].compactMap { change -> String? in
      let count = diff.entityIDs(change).count
      return count > 0 ? "\(count) \(change.rawValue)" : nil
    }
    VStack(alignment: .leading, spacing: 4) {
      Text("What changed in the data")
        .font(.title2.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
      Text("\(store.comparing?.label ?? "") → \(store.viewing.label): \(counts.isEmpty ? "no changes" : counts.joined(separator: ", ")).")
        .foregroundStyle(.secondary)
    }

    ForEach([Change.added, .changed, .removed], id: \.self) { change in
      let ids = diff.entityIDs(change)
      if !ids.isEmpty {
        InspectorSection(change.rawValue) {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(ids, id: \.self) { id in
              if let entity = diagram.architecture.entity(id) {
                Button { store.request(.focus(id)) } label: {
                  HStack(alignment: .top, spacing: 10) {
                    KindTile(kind: diagram.architecture.storeKind(entity), size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(entity.name).font(.callout.weight(.medium))
                      ForEach(change == .changed ? diff.entityDetails[id] ?? [] : [entity.summary].compactMap { $0 }, id: \.self) { line in
                        Text(line)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .fixedSize(horizontal: false, vertical: true)
                      }
                    }
                    Spacer(minLength: 0)
                    Circle().fill(change.color).frame(width: 7, height: 7).padding(.top, 5)
                  }
                  .padding(.vertical, 5)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
    }

    if counts.isEmpty {
      Text("The data is the same in both versions.")
        .foregroundStyle(.secondary)
    }
  }
}

/// Lays out its children in rows, wrapping when a row is full.
struct WrapLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        y += row + spacing
        x = 0
        row = 0
      }
      x += size.width + spacing
      row = max(row, size.height)
      widest = max(widest, x - spacing)
    }
    return CGSize(width: widest, height: y + row)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        y += row + spacing
        x = bounds.minX
        row = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      row = max(row, size.height)
    }
  }
}
