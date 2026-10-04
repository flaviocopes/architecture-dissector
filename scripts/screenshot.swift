// Captures the real Blueprint window for the README, in light and dark.
// It loads the architectures in scripts/demo into a demo data folder first, so your own data stays untouched.
// scripts/screenshot.sh compiles it with the app's sources, in place of BlueprintApp.swift.

import AppKit
import SwiftUI

let output = URL(filePath: CommandLine.arguments[1])
let demoHome = URL(filePath: CommandLine.arguments[2])
let demoData = URL(filePath: CommandLine.arguments[3])
/// Any architecture JSON to check instead of the demo scenes, like one an agent just saved.
let extra = CommandLine.arguments.dropFirst(4).first.flatMap { $0.hasPrefix("-") ? nil : URL(filePath: $0) }
let windowSize = CGSize(width: 1440, height: 880)

struct DemoScene {
  var name: String
  /// No app means the welcome screen, with no apps tracked.
  var app: String?
  var viewing: VersionRef = .current
  var comparing: VersionRef?
  var node: String?
  var tour: Int?
  var mode: CanvasMode = .architecture
  var flow: String?
  var step: String?
  var entity: String?
  var explainer: String?
  /// The slide of the explainer: 0 is its intro.
  var slide = 0
  var theme: DiagramTheme = .blueprint
  var flowGrouping: FlowGrouping = .actor
  /// Zoom steps after the diagram fits: out to see it from afar, or in when negative, to see details.
  var zoomOut = 0
  var level: DiagramLevel = .inDepth
  var block: String?
  /// Zooms to the selected component at full size, like double-clicking it.
  var focus = false
}

let extraArchitecture = extra.flatMap { try? Architecture.decode(Data(contentsOf: $0)) }
let extraNode = extraArchitecture.flatMap { architecture in architecture.nodes.first { !$0.details.isEmpty } ?? architecture.nodes.first }?.id

let extraFlow = extraArchitecture.flatMap { architecture in
  architecture.flows.first { $0.steps.contains { $0.stepKind == .decision } } ?? architecture.flows.first
}

let scenes = extra != nil ? [
  DemoScene(name: "screenshot-extra", app: "extra"),
  DemoScene(name: "screenshot-extra-far", app: "extra", zoomOut: 4),
  DemoScene(name: "screenshot-extra-node", app: "extra", node: extraNode),
  DemoScene(name: "screenshot-extra-tour", app: "extra", tour: extraArchitecture?.walkthrough.isEmpty == false ? 1 : nil),
  DemoScene(name: "screenshot-extra-flow", app: "extra", mode: .flows, flow: extraFlow?.id, step: extraFlow?.steps.first { $0.stepKind == .decision }?.id),
  DemoScene(name: "screenshot-extra-data", app: "extra", mode: .data),
  DemoScene(name: "screenshot-extra-data-entity", app: "extra", mode: .data, entity: extraArchitecture?.entities.max { $0.fields.count < $1.fields.count }?.id),
  DemoScene(name: "screenshot-extra-flows-area", app: "extra", mode: .flows, flow: extraFlow?.id, flowGrouping: .area),
  DemoScene(name: "screenshot-extra-explainer", app: "extra", mode: .explainers, explainer: extraArchitecture?.explainers.first?.id, slide: 2),
  DemoScene(name: "screenshot-extra-terminal", app: "extra", node: extraNode, theme: .terminal),
  DemoScene(name: "screenshot-extra-minimal", app: "extra", node: extraNode, theme: .minimal),
  DemoScene(name: "screenshot-extra-ascii", app: "extra", node: extraNode, theme: .ascii),
  DemoScene(name: "screenshot-extra-level-overview", app: "extra", level: .overview),
  DemoScene(name: "screenshot-extra-level-overview-block", app: "extra", level: .overview, block: extraArchitecture?.overview.max { $0.nodes.count < $1.nodes.count }?.id),
  DemoScene(name: "screenshot-extra-level-technical", app: "extra", level: .technical),
  DemoScene(name: "screenshot-extra-level-technical-near", app: "extra", node: extraNode, level: .technical, focus: true),
] : [
  DemoScene(name: "screenshot-welcome", app: nil),
  DemoScene(name: "screenshot-unmapped", app: "cli-tools"),
  DemoScene(name: "screenshot", app: "skillscout", node: "installer"),
  DemoScene(name: "screenshot-overview", app: "skillscout"),
  DemoScene(name: "screenshot-tour", app: "skillscout", tour: 2),
  DemoScene(name: "screenshot-flows", app: "skillscout", mode: .flows, flow: "prune-skills"),
  DemoScene(name: "screenshot-flows-area", app: "skillscout", mode: .flows, flow: "check-for-updates", flowGrouping: .area),
  DemoScene(name: "screenshot-flow-step", app: "blueprint", mode: .flows, flow: "map-an-app", step: "check"),
  DemoScene(name: "screenshot-data", app: "skillscout", mode: .data),
  DemoScene(name: "screenshot-data-entity", app: "blueprint", mode: .data, entity: "snapshot"),
  DemoScene(name: "screenshot-data-compare", app: "skillscout", comparing: .version("1.0.0"), mode: .data),
  DemoScene(name: "screenshot-explainer", app: "skillscout", mode: .explainers, explainer: "how-usage-is-counted", slide: 2),
  DemoScene(name: "screenshot-explainer-intro", app: "blueprint", mode: .explainers, explainer: "how-an-app-gets-mapped"),
  DemoScene(name: "screenshot-explainer-flow", app: "blueprint", mode: .explainers, explainer: "how-an-app-gets-mapped", slide: 2),
  DemoScene(name: "screenshot-theme-terminal", app: "skillscout", node: "installer", theme: .terminal),
  DemoScene(name: "screenshot-theme-minimal", app: "skillscout", node: "installer", theme: .minimal),
  DemoScene(name: "screenshot-theme-ascii", app: "skillscout", node: "installer", theme: .ascii),
  DemoScene(name: "screenshot-theme-ascii-flow", app: "blueprint", mode: .flows, flow: "map-an-app", step: "check", theme: .ascii),
  DemoScene(name: "screenshot-theme-terminal-data", app: "skillscout", mode: .data, entity: "parsed-file", theme: .terminal),
  DemoScene(name: "screenshot-theme-minimal-flow", app: "skillscout", mode: .flows, flow: "prune-skills", theme: .minimal),
  DemoScene(name: "screenshot-compare", app: "skillscout", comparing: .version("1.0.0")),
  DemoScene(name: "screenshot-version", app: "skillscout", viewing: .version("1.0.0")),  DemoScene(name: "screenshot-status", app: "blueprint"),
  DemoScene(name: "screenshot-level-overview", app: "skillscout", level: .overview),
  DemoScene(name: "screenshot-level-overview-block", app: "skillscout", level: .overview, block: "finder"),
  DemoScene(name: "screenshot-level-overview-tour", app: "skillscout", tour: 1, level: .overview),
  DemoScene(name: "screenshot-level-overview-compare", app: "skillscout", comparing: .version("1.0.0"), level: .overview),
  DemoScene(name: "screenshot-level-overview-ascii", app: "blueprint", theme: .ascii, level: .overview),
  DemoScene(name: "screenshot-level-technical", app: "skillscout", node: "installer", level: .technical),
  DemoScene(name: "screenshot-level-technical-near", app: "skillscout", node: "installer", level: .technical, focus: true),
  DemoScene(name: "screenshot-level-technical-terminal", app: "blueprint", theme: .terminal, zoomOut: -1, level: .technical),
  DemoScene(name: "screenshot-level-technical-minimal", app: "blueprint", theme: .minimal, zoomOut: -1, level: .technical),
  DemoScene(name: "screenshot-level-technical-ascii", app: "blueprint", theme: .ascii, zoomOut: -1, level: .technical),
]

/// An empty data folder for the welcome screen, and made-up git repositories for its suggestions.
func buildWelcomeHome() throws {
  let fm = FileManager.default
  let empty = demoHome.appending(path: "empty")
  try fm.createDirectory(at: empty, withIntermediateDirectories: true)
  setenv("BLUEPRINT_HOME", empty.path, 1)
  let projects = demoHome.appending(path: "projects")
  setenv("BLUEPRINT_PROJECTS_HOME", projects.path, 1)
  for (index, name) in ["waiting-lists", "mac-notes", "api-server", "landing-page", "invoice-pdf", "habit-tracker"].enumerated() {
    let git = projects.appending(path: "dev/\(name)/.git")
    try fm.createDirectory(at: git, withIntermediateDirectories: true)
    let head = git.appending(path: "HEAD")
    try "ref: refs/heads/main\n".write(to: head, atomically: true, encoding: .utf8)
    let date = Date.now.addingTimeInterval(-Double(index * index + 1) * 3 * 3600)
    for file in [git, head] { try fm.setAttributes([.modificationDate: date], ofItemAtPath: file.path) }
  }
}

/// Tracks Skillscout and Blueprint from ~/dev when they're there, with the demo architectures.
func buildDemoHome() throws {
  try? FileManager.default.removeItem(at: demoHome)
  setenv("BLUEPRINT_HOME", demoHome.path, 1)
  let dev = FileManager.default.homeDirectoryForCurrentUser.appending(path: "dev")

  func track(_ id: String, _ name: String) throws -> TrackedApp {
    let app = TrackedApp(id: id, name: name, path: dev.appending(path: id).path, addedAt: .now)
    try Library.write(app, to: Paths.folder(id).appending(path: "app.json"))
    return app
  }
  func architecture(_ file: String) throws -> Architecture {
    try Architecture.decode(Data(contentsOf: demoData.appending(path: file)))
  }

  _ = try track("cli-tools", "CLI Tools")
  let skillscout = try track("skillscout", "Skillscout")
  try Library.savePastVersion(architecture("skillscout-1.0.0.json"), as: "1.0.0", for: skillscout)
  try Library.savePastVersion(architecture("skillscout-1.1.0.json"), as: "1.1.0", for: skillscout)
  try Library.save(architecture("skillscout-1.3.0.json"), for: skillscout)
  try Library.saveVersion("1.3.0", for: skillscout)

  let blueprint = try track("blueprint", "Blueprint")
  try Library.save(architecture("blueprint.json"), for: blueprint)

  if let extra {
    let app = try track("extra", "Extra")
    try Library.save(Architecture.decode(Data(contentsOf: extra)), for: app)
  }

  // Pretend a few files changed since the save, to show the out-of-date state.
  let manifestFile = Paths.folder("blueprint").appending(path: "manifest.json")
  if var manifest = Library.read([String: String].self, from: manifestFile) {
    manifest["Blueprint/Layout.swift"] = "0"
    manifest["Blueprint/Core/Diff.swift"] = "0"
    manifest["CLI/Guide.swift"] = nil
    manifest["Blueprint/Legacy.swift"] = "0"
    try Library.write(manifest, to: manifestFile)
  }
}

@main
enum Screenshot {
  @MainActor
  static func main() {
    try! buildDemoHome()
    try! buildWelcomeHome()
    UserDefaults.standard.set(true, forKey: "showLabels")
    UserDefaults.standard.set(true, forKey: "showInspector")

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let store = AppStore()
    let host = NSHostingController(rootView: AnyView(EmptyView()))
    host.sceneBridgingOptions = [.toolbars, .title]
    let window = ActiveWindow(
      contentRect: CGRect(origin: .zero, size: windowSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = host
    window.toolbarStyle = .unified
    window.setContentSize(windowSize)
    window.center()

    _ = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await capture(store, host: host, window: window) }
      }
    }
    app.run()
  }
}

/// Draws as the active window even when another app is frontmost, which is the case
/// when this runs from a terminal: macOS doesn't let it take focus.
final class ActiveWindow: NSWindow {
  override var isKeyWindow: Bool { true }
  override var isMainWindow: Bool { true }
  @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
  @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
  @objc(_hasKeyAppearance) func hasKeyAppearance() -> Bool { true }
  @objc(_hasMainAppearance) func hasMainAppearance() -> Bool { true }
}

@MainActor
func capture(_ store: AppStore, host: NSHostingController<AnyView>, window: NSWindow) async {
  store.start()
  // SCENES=screenshot,screenshot-level* renders only those scenes; a name ending in * matches the start of names.
  let wanted = (ProcessInfo.processInfo.environment["SCENES"] ?? "").split(separator: ",").map(String.init)
  func isWanted(_ name: String) -> Bool {
    wanted.isEmpty || wanted.contains { $0.hasSuffix("*") ? name.hasPrefix($0.dropLast()) : name == $0 }
  }
  for scene in scenes where isWanted(scene.name) {
    if scene.app != nil, store.apps.isEmpty {
      setenv("BLUEPRINT_HOME", demoHome.path, 1)
      store.reload()
    }
    store.selectedID = scene.app
    store.tourStep = nil
    // The tab goes first: switching it, or the level, moves off versions that have nothing to show there.
    store.mode = scene.mode
    store.viewing = scene.viewing
    store.comparing = scene.comparing
    store.level = scene.level
    store.selectedNode = scene.node
    store.selectedBlock = scene.block
    store.selectedFlowID = scene.flow
    store.selectedStep = scene.step
    store.selectedEntity = scene.entity
    store.selectedExplainerID = scene.explainer
    store.explainerScene = scene.slide
    store.diagramTheme = scene.theme
    store.flowGrouping = scene.flowGrouping
    host.rootView = AnyView(ContentView().id(scene.name).environment(store))
    if scene.zoomOut != 0 {
      try? await Task.sleep(for: .seconds(1))
      for _ in 0..<abs(scene.zoomOut) {
        store.request(scene.zoomOut > 0 ? .zoomOut : .zoomIn)
        try? await Task.sleep(for: .seconds(0.5))
      }
    }
    if scene.focus, let node = scene.node {
      try? await Task.sleep(for: .seconds(1))
      store.request(.focus(node))
    }
    if let tour = scene.tour {
      try? await Task.sleep(for: .seconds(1))
      store.startTour(at: tour)
    }
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      NSApp.appearance = NSAppearance(named: appearance)
      try? await Task.sleep(for: .seconds(2))
      write(framed(snapshot(window)), to: output.appending(path: "\(scene.name)-\(name).png"))
    }
  }
  NSApp.terminate(nil)
}

@MainActor
func snapshot(_ window: NSWindow) -> CGImage {
  let view = window.contentView!.superview!
  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  view.cacheDisplay(in: view.bounds, to: rep)
  return rep.cgImage!
}

/// Rounds the corners like a window and adds a soft shadow on a transparent margin.
func framed(_ image: CGImage) -> CGImage {
  let scale: CGFloat = 2
  let margin = 48 * scale
  let radius = 12 * scale
  let size = CGSize(width: CGFloat(image.width) + 2 * margin, height: CGFloat(image.height) + 2 * margin)
  let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let rect = CGRect(x: margin, y: margin, width: CGFloat(image.width), height: CGFloat(image.height))
  let window = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 36 * scale, color: CGColor(gray: 0, alpha: 0.32))
  context.addPath(window)
  context.setFillColor(CGColor(gray: 0.5, alpha: 1))
  context.fillPath()
  context.restoreGState()

  context.addPath(window)
  context.clip()
  context.draw(image, in: rect)
  context.resetClip()
  context.addPath(window)
  context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
  context.setLineWidth(1)
  context.strokePath()
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let rep = NSBitmapImageRep(cgImage: image)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print(url.path)
}
