import SwiftUI

/// The first screen: what Blueprint does, a live demo, and the quickest ways to track an app.
struct WelcomeView: View {
  @Environment(AppStore.self) private var store
  @State private var projects: [SuggestedProject] = []
  @State private var projectsFolder: String?
  @State private var appeared = false

  var body: some View {
    GeometryReader { proxy in
      let wide = proxy.size.width >= 960
      ScrollView {
        HStack(alignment: .top, spacing: 52) {
          column
            .frame(width: wide ? 420 : min(540, proxy.size.width - 80))
          if wide {
            WelcomeDemo()
              .frame(maxWidth: 900)
              .padding(.top, 96)
              .reveal(appeared, delay: 0.3)
          }
        }
        .padding(.horizontal, wide ? 56 : 40)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .background { WelcomeBackground() }
    .onAppear { appeared = true }
    .task(id: store.apps.count) {
      let tracked = Set(store.apps.map(\.path))
      let found = await Task.detached(priority: .utility) { ProjectFinder.recent(excluding: tracked) }.value
      withAnimation(.smooth) {
        projects = found.projects
        projectsFolder = found.folder
      }
    }
  }

  private var column: some View {
    VStack(alignment: .leading, spacing: 28) {
      header
        .reveal(appeared, delay: 0)
      SetupGuide {
        VStack(alignment: .leading, spacing: 10) {
          DropZone(targeted: store.isDropTargeted) { store.chooseFolders() }
          if !projects.isEmpty {
            HStack(spacing: 6) {
              SectionLabel("Recent projects")
              if let projectsFolder {
                Text("in \(projectsFolder)")
                  .font(.system(size: 10.5))
                  .foregroundStyle(.tertiary)
              }
            }
            .padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
              ForEach(projects) { project in
                ProjectChip(project: project) { store.add([project.url]) }
              }
            }
          }
        }
      }
      .reveal(appeared, delay: 0.1)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 42, height: 42)
          .shadow(color: Color(hex: 0x2F63EC).opacity(0.35), radius: 8, y: 3)
        Text("Blueprint")
          .font(.system(size: 18, weight: .semibold))
      }
      (Text("See how your apps\nare built, ") + Text("and how\nthey change.").foregroundStyle(Theme.brand))
        .font(.system(size: 36, weight: .bold))
        .lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
      Text("Your coding agents map each app's architecture. Blueprint draws it, tells you when the code moves on, and shows what changed between versions.")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct WelcomeBackground: View {
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let dark = scheme == .dark
    ZStack {
      GridBackground(scale: 1, offset: CGSize(width: 12, height: 12), scheme: scheme)
      RadialGradient(colors: [Color(hex: 0x3B82F6).opacity(dark ? 0.24 : 0.14), .clear], center: UnitPoint(x: 0.72, y: 0.45), startRadius: 0, endRadius: 560)
      RadialGradient(colors: [Color(hex: 0x8B5CF6).opacity(dark ? 0.18 : 0.10), .clear], center: UnitPoint(x: 0.98, y: 0.98), startRadius: 0, endRadius: 480)
      RadialGradient(colors: [Color(hex: 0x14B8A6).opacity(dark ? 0.12 : 0.08), .clear], center: UnitPoint(x: 0.02, y: 0.02), startRadius: 0, endRadius: 420)
    }
    .ignoresSafeArea()
  }
}

struct SectionLabel: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 10, weight: .bold))
      .tracking(1.1)
      .foregroundStyle(.secondary)
  }
}

struct DropZone: View {
  let targeted: Bool
  let choose: () -> Void
  @State private var hovering = false
  @State private var phase: CGFloat = 0
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Theme.brand)
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        Image(systemName: targeted ? "arrow.down" : "folder.badge.plus")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(.white)
          .contentTransition(.symbolEffect(.replace))
      }
      .frame(width: 54, height: 54)
      .shadow(color: Color(hex: 0x3B82F6).opacity(0.4), radius: 10, y: 4)

      VStack(alignment: .leading, spacing: 4) {
        Text(targeted ? "Drop to track it" : "Drop an app folder here")
          .font(.system(size: 15, weight: .semibold))
        Text(targeted ? "Blueprint starts watching it right away." : "Or click to choose one. Drop several to track them all.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .background(.regularMaterial, in: shape)
    .overlay(
      shape.strokeBorder(
        targeted ? Color.accentColor : Color.primary.opacity(hovering ? 0.32 : 0.18),
        style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [7, 5], dashPhase: phase)
      )
    )
    .shadow(color: targeted ? Color.accentColor.opacity(0.35) : .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: targeted ? 20 : 12, y: 4)
    .scaleEffect(targeted ? 1.025 : hovering ? 1.01 : 1)
    .animation(.snappy(duration: 0.2), value: targeted)
    .animation(.snappy(duration: 0.2), value: hovering)
    .contentShape(shape)
    .onTapGesture(perform: choose)
    .onHover { hovering = $0 }
    .onAppear {
      withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = -24 }
    }
  }
}

struct ProjectChip: View {
  let project: SuggestedProject
  let track: () -> Void
  @State private var hovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
    Button(action: track) {
      HStack(spacing: 9) {
        Monogram(name: project.name, seed: Library.slug(project.url.lastPathComponent), size: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text(project.name)
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
          Text(project.updated.formatted(.relative(presentation: .named)))
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Image(systemName: "plus.circle.fill")
          .font(.system(size: 15))
          .foregroundStyle(Color.accentColor)
          .opacity(hovering ? 1 : 0)
      }
      .padding(8)
      .background(shape.fill(.regularMaterial))
      .background(shape.fill(Color.primary.opacity(hovering ? 0.06 : 0)))
      .overlay(shape.strokeBorder(hovering ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1))
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.snappy(duration: 0.15), value: hovering)
    .help("Track \((project.url.path as NSString).abbreviatingWithTildeInPath)")
  }
}

/// A prompt to paste into a coding agent, with a copy button.
struct PromptCard: View {
  let text: String
  var prominent = false
  /// The copy button under the prompt instead of beside it, for narrow columns like the inspector.
  var stacked = false
  @State private var copied = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    Group {
      if stacked {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 10) {
            icon
            prompt
          }
          copyButton
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } else {
        HStack(spacing: 12) {
          icon
          prompt
          copyButton
        }
      }
    }
    .padding(14)
    .background(.regularMaterial, in: shape)
    .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
  }

  private var icon: some View {
    Image(systemName: "text.bubble.fill")
      .font(.system(size: 17))
      .foregroundStyle(Theme.brand)
  }

  private var prompt: some View {
    Text(text)
      .font(.system(size: 12.5, design: .monospaced))
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: stacked)
  }

  private var copyButton: some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      copied = true
      Task {
        try? await Task.sleep(for: .seconds(2))
        copied = false
      }
    } label: {
      Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
        .contentTransition(.symbolEffect(.replace))
    }
    .controlSize(prominent ? .large : .regular)
    .modifier(CopyButtonStyle(prominent: prominent))
  }
}

struct CopyButtonStyle: ViewModifier {
  let prominent: Bool

  func body(content: Content) -> some View {
    if prominent {
      content.buttonStyle(.borderedProminent)
    } else {
      content.buttonStyle(.bordered)
    }
  }
}

/// The steps that connect projects to Blueprint through their agents: the command and the skill agents use,
/// tracking an app, the prompt that maps it, and the snippet that keeps it current. `track` is how step 3
/// tracks a folder where the guide is shown.
struct SetupGuide<Track: View>: View {
  @ViewBuilder var track: Track
  @State private var commandInstalled = CommandLineTool.isInstalled
  @State private var skill = AgentSkill.state
  @State private var problem: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SetupStep(number: 1, title: "Install the blueprint command", detail: "Agents save each map with it. Blueprint links it into /usr/local/bin.", done: commandInstalled) {
        install(done: commandInstalled, title: "Install") {
          CommandLineTool.install()
          commandInstalled = CommandLineTool.isInstalled
        }
      } content: {
        EmptyView()
      }
      SetupStep(number: 2, title: "Install the agent skill", detail: "It teaches Claude Code, Cursor and Codex when and how to use Blueprint, in every project.", done: skill == .installed) {
        install(done: skill == .installed, title: skill == .outdated ? "Update" : "Install") {
          problem = AgentSkill.install()
          skill = AgentSkill.state
        }
      } content: {
        if let problem {
          Text(problem)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.removed)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      SetupStep(number: 3, title: "Track an app", detail: "Blueprint watches its folder for changes, and never writes to it.") {
        EmptyView()
      } content: {
        track
      }
      SetupStep(number: 4, title: "Ask an agent to map it", detail: "Paste this into a coding agent working in that app. The diagram shows up as soon as it saves.") {
        EmptyView()
      } content: {
        PromptCard(text: AppStore.mapPrompt)
      }
      SetupStep(number: 5, title: "Keep it current", detail: "Add this to the app's AGENTS.md or CLAUDE.md, so every agent updates the map after a change and reads it before one.") {
        EmptyView()
      } content: {
        PromptCard(text: AppStore.agentsSnippet)
      }
    }
  }

  @ViewBuilder
  private func install(done: Bool, title: String, action: @escaping () -> Void) -> some View {
    if done {
      Label("Installed", systemImage: "checkmark.circle.fill")
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Theme.added)
    } else {
      Button(title, action: action)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
  }
}

/// One numbered step of the setup guide, with an accessory on the right and anything it needs below.
struct SetupStep<Accessory: View, Content: View>: View {
  let number: Int
  let title: String
  let detail: String
  var done = false
  @ViewBuilder var accessory: Accessory
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle().fill(done ? AnyShapeStyle(Theme.added) : AnyShapeStyle(Theme.brand))
        if done {
          Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
        } else {
          Text("\(number)").font(.system(size: 11, weight: .bold).monospacedDigit())
        }
      }
      .foregroundStyle(.white)
      .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text(title)
              .font(.system(size: 13.5, weight: .semibold))
            Text(detail)
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
          accessory
        }
        content
      }
    }
  }
}

/// The setup guide in a sheet, for anyone who already tracks apps and wants to connect another project.
struct SetupSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Connect your projects")
          .font(.title2.weight(.bold))
        Text("Coding agents map each app with the blueprint command, and Blueprint draws what they save. Do the first two steps once, then the rest for every app.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      ScrollView {
        SetupGuide {
          Button("Choose a Folder…") {
            dismiss()
            store.chooseFolders()
          }
          .controlSize(.small)
        }
        .padding(.vertical, 4)
      }
      .scrollBounceBehavior(.basedOnSize)
      HStack {
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 560, height: 640)
  }
}

struct SkillStatus: View {
  @State private var state = AgentSkill.state

  var body: some View {
    HStack(spacing: 6) {
      if state == .installed {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Theme.added)
        Text("The agent skill is installed, so agents know about Blueprint.")
          .foregroundStyle(.secondary)
      } else {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(Theme.stale)
        Text(state == .outdated ? "The agent skill is out of date." : "Agents work best with the agent skill.")
          .foregroundStyle(.secondary)
        Button(state == .outdated ? "Update it" : "Install it") {
          _ = AgentSkill.install()
          state = AgentSkill.state
        }
        .buttonStyle(.link)
      }
    }
    .font(.system(size: 11.5))
  }
}

struct CLIStatus: View {
  @State private var installed = CommandLineTool.isInstalled

  var body: some View {
    HStack(spacing: 6) {
      if installed {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Theme.added)
        Text("The blueprint command is installed, so agents can use it.")
          .foregroundStyle(.secondary)
      } else {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(Theme.stale)
        Text("Agents need the blueprint command.")
          .foregroundStyle(.secondary)
        Button("Install it…") {
          CommandLineTool.install()
          installed = CommandLineTool.isInstalled
        }
        .buttonStyle(.link)
      }
    }
    .font(.system(size: 11.5))
  }
}

// MARK: - The live demo

/// A small made-up app that loops through the three things Blueprint does.
struct WelcomeDemo: View {
  @State private var step = 0
  private static let duration: Double = 4.5

  private static let steps = [
    ("Your agent maps it", "It reads the code and saves the diagram with the blueprint command."),
    ("Changes get flagged", "When files change, the components they belong to light up."),
    ("Versions compare", "New parts in green, changed ones in amber, removed ones in red."),
  ]

  private var diagram: Diagram {
    switch step {
    case 0: Diagram(architecture: DemoArchitecture.v10)
    case 1: Diagram(architecture: DemoArchitecture.v10, touched: ["signup-api", "dashboard"])
    default: Diagram(architecture: DemoArchitecture.v11, diff: ArchitectureDiff(from: DemoArchitecture.v10, to: DemoArchitecture.v11))
    }
  }

  var body: some View {
    VStack(spacing: 24) {
      panel
      stepPicker
    }
    .task(id: step) {
      try? await Task.sleep(for: .seconds(Self.duration))
      guard !Task.isCancelled else { return }
      withAnimation(.smooth(duration: 0.8)) { step = (step + 1) % Self.steps.count }
    }
  }

  /// A small canvas that zooms to fit each step, with the banner the app shows on top.
  private var panel: some View {
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    let diagram = self.diagram
    return ZStack(alignment: .top) {
      PanelGrid()
      GeometryReader { proxy in
        let bounds = diagram.layout.bounds
        let content = CGSize(width: bounds.width - 2 * DiagramLayout.margin + 40, height: bounds.height - 2 * DiagramLayout.margin + 40)
        let scale = min(proxy.size.width / content.width, proxy.size.height / content.height, 0.95)
        DiagramWorld(diagram: diagram, highlightAll: step == 0, scale: scale)
          .scaleEffect(scale)
          .frame(width: proxy.size.width, height: proxy.size.height)
      }
      .padding(.top, 60)
      .padding([.horizontal, .bottom], 20)
      banner
        .padding(.top, 16)
    }
    .aspectRatio(2.15, contentMode: .fit)
    .clipShape(shape)
    .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
    .allowsHitTesting(false)
  }

  private var banner: some View {
    HStack(spacing: 8) {
      switch step {
      case 0:
        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.added)
        Text("Mapped by your agent").fontWeight(.semibold)
        Text("4 components · 3 connections").foregroundStyle(.secondary)
      case 1:
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.stale)
        Text("3 files changed since the architecture was saved").fontWeight(.semibold)
      default:
        Image(systemName: "plusminus.circle.fill").foregroundStyle(Color.accentColor)
        Text("1.0 → 1.1").fontWeight(.semibold)
        Circle().fill(Theme.added).frame(width: 7, height: 7)
        Text("2 added")
        Circle().fill(Theme.changed).frame(width: 7, height: 7)
        Text("1 changed")
      }
    }
    .font(.system(size: 12))
    .pill()
    .id(step)
    .transition(.blurReplace)
  }

  private var stepPicker: some View {
    HStack(alignment: .top, spacing: 18) {
      ForEach(Self.steps.indices, id: \.self) { index in
        let active = index == step
        Button {
          withAnimation(.smooth(duration: 0.8)) { step = index }
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            StepProgress(active: active, duration: Self.duration)
              .id(active ? "active-\(step)" : "idle-\(index)")
            HStack(spacing: 7) {
              Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(active ? .white : .secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(active ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.1))))
              Text(Self.steps[index].0)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(active ? .primary : .secondary)
            }
            Text(Self.steps[index].1)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .opacity(active ? 1 : 0.6)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: 620)
  }
}

struct PanelGrid: View {
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    GridBackground(scale: 0.75, offset: CGSize(width: 9, height: 9), scheme: scheme)
  }
}

struct StepProgress: View {
  let active: Bool
  let duration: Double
  @State private var fill: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.1))
        Capsule().fill(Theme.brand).frame(width: proxy.size.width * fill)
      }
    }
    .frame(height: 3)
    .onAppear {
      guard active else { return }
      withAnimation(.linear(duration: duration)) { fill = 1 }
    }
  }
}

enum DemoArchitecture {
  static let v10 = Architecture(
    name: "Waiting Lists",
    summary: "A site where makers collect signups for products they haven't launched yet.",
    groups: [
      .init(id: "site", name: "Astro site"),
      .init(id: "cloudflare", name: "Cloudflare"),
    ],
    nodes: [
      node("pages", "Landing pages", .client, "site", ["Astro"]),
      node("dashboard", "Dashboard", .ui, "site", ["Astro"]),
      node("signup-api", "Signup API", .api, "cloudflare", ["Workers"]),
      node("signups", "Signups", .database, "cloudflare", ["D1"]),
    ],
    edges: [
      .init(from: "pages", to: "signup-api", label: "posts the form"),
      .init(from: "signup-api", to: "signups", label: "inserts signup", kind: "writes"),
      .init(from: "dashboard", to: "signups", label: "lists signups", kind: "reads"),
    ]
  )

  static let v11: Architecture = {
    var architecture = v10
    architecture.groups.append(.init(id: "services", name: "Services"))
    architecture.nodes[2].tech.append("Queues")
    architecture.nodes += [
      node("mailer", "Mailer", .worker, "cloudflare", ["Queues"]),
      node("resend", "Resend", .external, "services", ["Email"]),
    ]
    architecture.edges += [
      .init(from: "signup-api", to: "mailer", label: "queues email", kind: "sends"),
      .init(from: "mailer", to: "resend", label: "sends confirmation"),
    ]
    return architecture
  }()
  private static func node(_ id: String, _ name: String, _ kind: NodeKind, _ group: String, _ tech: [String]) -> Architecture.Node {
    Architecture.Node(id: id, name: name, kind: kind.rawValue, group: group, tech: tech, paths: [])
  }
}

extension View {
  /// Fades and lifts the view in once `shown` turns true.
  func reveal(_ shown: Bool, delay: Double) -> some View {
    opacity(shown ? 1 : 0)
      .offset(y: shown ? 0 : 14)
      .animation(.smooth(duration: 0.6).delay(delay), value: shown)
  }
}
