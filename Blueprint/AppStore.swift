import AppKit
import Observation
import SwiftUI

enum VersionRef: Hashable {
  case current
  case version(String)

  var label: String {
    switch self {
    case .current: "Current"
    case .version(let name): name
    }
  }

  init(_ name: String?) {
    guard let name, name.lowercased() != "current" else {
      self = .current
      return
    }
    self = .version(Library.normalizeVersion(name))
  }
}

/// What the canvas shows: how the app is built, what people do with it, what it stores, or explainers about it.
enum CanvasMode: String, CaseIterable {
  case architecture, flows, data, explainers

  var label: String {
    switch self {
    case .architecture: "Architecture"
    case .flows: "Flows"
    case .data: "Data"
    case .explainers: "Explainers"
    }
  }

  var symbol: String {
    switch self {
    case .architecture: "rectangle.3.group.fill"
    case .flows: "point.topleft.down.to.point.bottomright.curvepath.fill"
    case .data: "tablecells.fill"
    case .explainers: "play.rectangle.on.rectangle.fill"
    }
  }

  var help: String {
    switch self {
    case .architecture: "How the app is built (⇧⌘A)"
    case .flows: "What people, agents and the app itself do, step by step (⇧⌘F)"
    case .data: "What the app stores, field by field (⇧⌘D)"
    case .explainers: "Short videos about how parts of the app work (⇧⌘E)"
    }
  }
}

/// How the inspector and the flow picker group flows.
enum FlowGrouping: String, CaseIterable {
  case actor, area
}

struct FlowSection: Identifiable {
  var id: String
  var title: String
  var symbol: String
  var flows: [Architecture.Flow]
}

struct AppData {
  var current: Snapshot?
  var versions: [Snapshot] = []
  var status: AppStatus?

  /// Versions oldest first, then the current architecture.
  var refs: [VersionRef] {
    versions.compactMap(\.version).map(VersionRef.version) + (current == nil ? [] : [.current])
  }

  func snapshot(_ ref: VersionRef) -> Snapshot? {
    switch ref {
    case .current: current
    case .version(let name): versions.first { $0.version == name }
    }
  }
}

@MainActor
@Observable
final class AppStore {
  var apps: [TrackedApp] = []
  var data: [String: AppData] = [:]
  var selectedID: String? {
    didSet { if oldValue != selectedID { selectionChanged() } }
  }
  var viewing: VersionRef = .current {
    didSet { if oldValue != viewing { refreshDiagram() } }
  }
  var comparing: VersionRef? {
    didSet { if oldValue != comparing { refreshDiagram() } }
  }
  var selectedNode: String? {
    didSet { if selectedNode != nil, tourStep != nil { tourStep = nil } }
  }
  /// The overview block selected, at the overview level.
  var selectedBlock: String? {
    didSet { if selectedBlock != nil, tourStep != nil { tourStep = nil } }
  }
  var level = DiagramLevel(rawValue: UserDefaults.standard.string(forKey: "diagramLevel") ?? "") ?? .overview {
    didSet {
      guard oldValue != level else { return }
      UserDefaults.standard.set(level.rawValue, forKey: "diagramLevel")
      selectedBlock = nil
      if level == .overview { selectedNode = nil }
      keepVersionsThatShowIt()
      refreshCanvas()
      if let tourStep { showStep(tourStep) } else { request(.fit) }
    }
  }
  var mode: CanvasMode = .architecture {
    didSet {
      guard oldValue != mode else { return }
      selectedStep = nil
      if mode != .architecture { tourStep = nil }
      explainerPlaying = false
      // Explainers play one version as it is, so a comparison would only color them.
      if mode == .explainers { comparing = nil }
      keepVersionsThatShowIt()
    }
  }
  var selectedEntity: String?
  var selectedExplainerID: String? {
    didSet {
      guard oldValue != selectedExplainerID else { return }
      explainerScene = 0
      explainerPlaying = false
    }
  }
  /// The slide of the explainer on screen: 0 is its intro, then one per scene.
  var explainerScene = 0
  var explainerPlaying = false
  var muteExplainers = UserDefaults.standard.bool(forKey: "muteExplainers") {
    didSet { UserDefaults.standard.set(muteExplainers, forKey: "muteExplainers") }
  }
  var selectedFlowID: String? {
    didSet { if oldValue != selectedFlowID { selectedStep = nil } }
  }
  var selectedStep: String?
  /// The walkthrough step shown, if the walkthrough is open.
  var tourStep: Int? {
    didSet { if oldValue != tourStep, let tourStep { showStep(tourStep) } }
  }
  var showLabels = UserDefaults.standard.object(forKey: "showLabels") as? Bool ?? true {
    didSet { UserDefaults.standard.set(showLabels, forKey: "showLabels") }
  }
  var showInspector = UserDefaults.standard.object(forKey: "showInspector") as? Bool ?? true {
    didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
  }
  var diagramTheme = DiagramTheme(rawValue: UserDefaults.standard.string(forKey: "diagramTheme") ?? "") ?? .blueprint {
    didSet { UserDefaults.standard.set(diagramTheme.rawValue, forKey: "diagramTheme") }
  }
  var canvasRequest: CanvasRequest?
  var diagram: Diagram?
  /// What the architecture canvas draws at the current level. Nil at the overview level when there's no overview.
  var canvasDiagram: Diagram?
  var alert: String?
  var isSavingVersion = false
  var isShowingSetup = false
  var isDropTargeted = false

  @ObservationIgnored private var storeWatcher: FileWatcher?
  @ObservationIgnored private var appWatchers: [String: FileWatcher] = [:]
  @ObservationIgnored private var statusGeneration: [String: Int] = [:]
  @ObservationIgnored private var requestSerial = 0
  @ObservationIgnored private var started = false

  var selectedApp: TrackedApp? { apps.first { $0.id == selectedID } }
  var selectedData: AppData? { selectedID.flatMap { data[$0] } }

  func name(of app: TrackedApp) -> String {
    data[app.id]?.current?.architecture.name ?? app.name
  }

  // MARK: Loading

  /// Loads the apps right away, so the first frame already knows whether to show the welcome screen.
  init() {
    reload()
  }

  func start() {
    guard !started else { return }
    started = true
    // An update brings a newer skill with its newer command, so agents keep reading the matching one.
    if AgentSkill.state == .outdated { _ = AgentSkill.install() }
    try? FileManager.default.createDirectory(at: Paths.apps, withIntermediateDirectories: true)
    reload()
    if selectedID == nil {
      let saved = UserDefaults.standard.string(forKey: "selectedApp")
      selectedID = apps.contains { $0.id == saved } ? saved : apps.first?.id
    }
    storeWatcher = FileWatcher(paths: [Paths.apps.path], latency: 0.3) { [weak self] _ in
      Task { @MainActor in self?.reload() }
    }
  }

  /// Rereads every app from disk. The command line tool writes there, so this runs after each `blueprint set`.
  func reload() {
    let fresh = Library.apps()
    var loaded: [String: AppData] = [:]
    for app in fresh {
      loaded[app.id] = AppData(current: Library.current(app.id), versions: Library.versions(app.id), status: data[app.id]?.status)
    }
    let changed = fresh.filter { app in
      data[app.id]?.current != loaded[app.id]?.current || !apps.contains(app)
    }
    apps = fresh
    data = loaded
    if let id = selectedID, !apps.contains(where: { $0.id == id }) {
      selectedID = apps.first?.id
    }
    syncWatchers()
    for app in changed { checkStatus(app) }
    refreshDiagram()
  }

  private func syncWatchers() {
    for app in apps where appWatchers[app.id] == nil {
      let id = app.id
      appWatchers[id] = FileWatcher(paths: [app.path], latency: 1.5) { [weak self] paths in
        let ignored = ["/.git/objects/", "/node_modules/", "/build/", "/.build/", "/dist/", "/DerivedData/", "/.wrangler/", "/.astro/"]
        guard paths.contains(where: { path in !ignored.contains { path.contains($0) } }) else { return }
        Task { @MainActor in
          guard let self, let app = self.apps.first(where: { $0.id == id }) else { return }
          self.checkStatus(app)
        }
      }
    }
    for id in appWatchers.keys where !apps.contains(where: { $0.id == id }) {
      appWatchers[id] = nil
    }
  }

  func checkStatus(_ app: TrackedApp) {
    let generation = (statusGeneration[app.id] ?? 0) + 1
    statusGeneration[app.id] = generation
    let current = data[app.id]?.current
    Task.detached(priority: .utility) { [weak self] in
      let status = AppStatus.check(app, current: current, manifest: Library.manifest(app.id))
      await self?.apply(status, to: app.id, generation: generation)
    }
  }

  private func apply(_ status: AppStatus, to id: String, generation: Int) {
    guard statusGeneration[id] == generation, data[id] != nil, data[id]?.status != status else { return }
    data[id]?.status = status
    if id == selectedID { refreshDiagram() }
  }

  // MARK: What the canvas shows

  private func selectionChanged() {
    UserDefaults.standard.set(selectedID, forKey: "selectedApp")
    selectedNode = nil
    selectedBlock = nil
    selectedFlowID = nil
    selectedStep = nil
    selectedEntity = nil
    selectedExplainerID = nil
    explainerScene = 0
    explainerPlaying = false
    tourStep = nil
    comparing = nil
    viewing = .current
    refreshDiagram()
  }

  func refreshDiagram() {
    defer { refreshCanvas() }
    guard let id = selectedID, let appData = data[id] else {
      diagram = nil
      return
    }
    guard let target = appData.snapshot(viewing) else {
      if viewing != .current {
        viewing = .current
      } else {
        diagram = nil
      }
      return
    }
    var diff: ArchitectureDiff?
    if let comparing {
      guard comparing != viewing, let base = appData.snapshot(comparing) else {
        self.comparing = nil
        return
      }
      diff = ArchitectureDiff(from: base.architecture, to: target.architecture)
    }
    let touched = viewing == .current && diff == nil ? appData.status?.touched ?? [] : []
    diagram = Diagram(architecture: target.architecture, diff: diff, touched: touched)
    if let node = selectedNode, diagram?.architecture.node(node) == nil {
      selectedNode = nil
    }
    if let tourStep, !walkthrough.indices.contains(tourStep) {
      self.tourStep = nil
    }
    if let id = selectedFlowID, !flows.contains(where: { $0.id == id }) {
      selectedFlowID = nil
    }
    if let step = selectedStep, currentFlow?.step(step) == nil {
      selectedStep = nil
    }
    if let entity = selectedEntity, diagram?.architecture.entity(entity) == nil {
      selectedEntity = nil
    }
    if let id = selectedExplainerID, !explainers.contains(where: { $0.id == id }) {
      selectedExplainerID = nil
    }
    if let explainer = currentExplainer, explainerScene >= explainer.slideCount {
      explainerScene = 0
      explainerPlaying = false
    }
  }

  /// Builds what the architecture canvas draws: the overview's blocks, the diagram as it is, or the
  /// diagram laid out with room for every detail.
  private func refreshCanvas() {
    guard let diagram, let id = selectedID, let appData = data[id], let target = appData.snapshot(viewing) else {
      canvasDiagram = nil
      return
    }
    switch level {
    case .inDepth:
      canvasDiagram = diagram
    case .technical:
      canvasDiagram = Diagram(architecture: target.architecture, diff: diagram.diff, touched: diagram.touched, level: .technical)
    case .overview:
      let architecture = target.architecture
      guard !architecture.overview.isEmpty else {
        canvasDiagram = nil
        break
      }
      var diff: ArchitectureDiff?
      if let components = diagram.diff, let comparing, let base = appData.snapshot(comparing) {
        diff = ArchitectureDiff(overviewFrom: base.architecture, to: architecture, components: components)
      }
      let touched = Set(architecture.overview.filter { $0.nodes.contains(where: diagram.touched.contains) }.map(\.id))
      canvasDiagram = Diagram(architecture: architecture.overviewMap, diff: diff, touched: touched, level: .overview)
    }
    if let block = selectedBlock, canvasDiagram?.architecture.node(block) == nil {
      selectedBlock = nil
    }
  }

  /// The versions the timeline offers on this tab and level: the ones that have what it shows, and the current
  /// architecture always. Versions mapped before flows, data, explainers or the overview existed have nothing to show there.
  func timelineRefs(_ data: AppData) -> [VersionRef] {
    data.refs.filter { ref in
      guard ref != .current, let architecture = data.snapshot(ref)?.architecture else { return true }
      return switch mode {
      case .architecture: level != .overview || !architecture.overview.isEmpty
      case .flows: !architecture.flows.isEmpty
      case .data: !architecture.entities.isEmpty
      case .explainers: !architecture.explainers.isEmpty
      }
    }
  }

  /// The saved versions the timeline leaves out on this tab and level, oldest first.
  func versionsMissingPart(_ data: AppData) -> [String] {
    let shown = Set(timelineRefs(data))
    return data.refs.filter { !shown.contains($0) }.map(\.label)
  }

  /// What a version needs to show on this tab and level, in words.
  var timelinePart: String {
    switch mode {
    case .architecture: "overview"
    case .flows: "flows"
    case .data: "data"
    case .explainers: "explainers"
    }
  }

  func pastVersionsPrompt(for app: TrackedApp, versions: [String]) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    let one = versions.count == 1
    return "The Blueprint \(one ? "version" : "versions") \(versions.formatted(.list(type: .and))) of the app in \(path) \(one ? "has" : "have") no \(timelinePart). Fill \(one ? "it" : "them") in from the code of each version in the git history, as `blueprint guide` explains in \"Fill in older versions\"."
  }

  /// Moves off a version, and drops a comparison with one, that has nothing to show on this tab and level.
  private func keepVersionsThatShowIt() {
    guard let data = selectedData else { return }
    let refs = timelineRefs(data)
    if let comparing, !refs.contains(comparing) { self.comparing = nil }
    if !refs.contains(viewing) { viewing = .current }
  }

  /// The overview blocks that stand for any of these components.
  func blocks(covering ids: some Sequence<String>) -> [String] {
    let wanted = Set(ids)
    return (diagram?.architecture.overview ?? []).filter { $0.nodes.contains(where: wanted.contains) }.map(\.id)
  }

  // MARK: Flows

  var flows: [Architecture.Flow] { diagram?.architecture.flows ?? [] }

  var flowGrouping = FlowGrouping(rawValue: UserDefaults.standard.string(forKey: "flowGrouping") ?? "") ?? .actor {
    didSet { UserDefaults.standard.set(flowGrouping.rawValue, forKey: "flowGrouping") }
  }

  /// The flows in groups: by whose workflow they are, in a fixed order, or by area, in the order areas first appear.
  /// Flows that don't say go last.
  var flowSections: [FlowSection] {
    switch flowGrouping {
    case .actor:
      let known = FlowActor.allCases.map { actor in
        FlowSection(id: actor.rawValue, title: actor.label, symbol: actor.symbol, flows: flows.filter { $0.flowActor == actor })
      }
      let unknown = FlowSection(id: "", title: "Whose isn't set", symbol: "questionmark.circle", flows: flows.filter { $0.flowActor == nil })
      return (known + [unknown]).filter { !$0.flows.isEmpty }
    case .area:
      var areas: [String] = []
      for flow in flows { if let area = flow.area, !areas.contains(area) { areas.append(area) } }
      let known = areas.map { area in FlowSection(id: area, title: area, symbol: "square.stack.3d.up", flows: flows.filter { $0.area == area }) }
      let unknown = FlowSection(id: "", title: "No area", symbol: "questionmark.circle", flows: flows.filter { $0.area == nil })
      return (known + [unknown]).filter { !$0.flows.isEmpty }
    }
  }

  var currentFlow: Architecture.Flow? {
    flows.first { $0.id == selectedFlowID } ?? flows.first
  }

  /// Moves the selection along the current flow, in the order its steps are listed.
  func moveStep(by delta: Int) {
    guard let flow = currentFlow, !flow.steps.isEmpty else { return }
    let ids = flow.steps.map(\.id)
    let index = selectedStep.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
    let next = index + delta
    if ids.indices.contains(next) { selectedStep = ids[next] }
  }

  /// Switches to the architecture and zooms to a component, from a step that uses it.
  func showComponent(_ id: String) {
    mode = .architecture
    if level == .overview { level = .inDepth }
    selectedNode = id
    Task {
      try? await Task.sleep(for: .milliseconds(120))
      request(.focus(id))
    }
  }

  func flowsPrompt(for app: TrackedApp) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    return "Map every workflow of the app in \(path) as Blueprint flows: what people using it do, what its owner does, what agents do, and what the app does on its own, each with its actor and area. Run `blueprint guide` to see how."
  }

  // MARK: Data

  /// Switches to the data and zooms to an entity, from the component that stores it.
  func showEntity(_ id: String) {
    mode = .data
    selectedEntity = id
    Task {
      try? await Task.sleep(for: .milliseconds(120))
      request(.focus(id))
    }
  }

  // MARK: Explainers

  var explainers: [Architecture.Explainer] { diagram?.architecture.explainers ?? [] }

  var currentExplainer: Architecture.Explainer? {
    explainers.first { $0.id == selectedExplainerID } ?? explainers.first
  }

  func toggleExplainer() {
    guard let explainer = currentExplainer else { return }
    if !explainerPlaying, explainerScene == explainer.slideCount - 1 { explainerScene = 0 }
    explainerPlaying.toggle()
  }

  func showSlide(_ slide: Int) {
    guard let explainer = currentExplainer, (0..<explainer.slideCount).contains(slide) else { return }
    explainerScene = slide
  }

  func explainersPrompt(for app: TrackedApp) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    return "Add explainers to the Blueprint architecture of the app in \(path): short videos about how parts of it work, scene by scene. Run `blueprint guide` to see how."
  }

  func dataPrompt(for app: TrackedApp) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    return "Add the data to the Blueprint architecture of the app in \(path): every table, collection, file or setting it stores, with its fields and what they point to. Run `blueprint guide` to see how."
  }

  // MARK: Walkthrough

  var walkthrough: [Architecture.Step] { diagram?.architecture.walkthrough ?? [] }

  var spotlight: Set<String>? {
    guard let tourStep, walkthrough.indices.contains(tourStep) else { return nil }
    return Set(walkthrough[tourStep].nodes)
  }

  /// The spotlight on the architecture canvas, where the overview shows blocks instead of components.
  var canvasSpotlight: Set<String>? {
    guard let spotlight, level == .overview else { return spotlight }
    return Set(blocks(covering: spotlight))
  }

  func startTour(at step: Int = 0) {
    guard walkthrough.indices.contains(step) else { return }
    tourStep = step
  }

  func nextStep() {
    guard let tourStep else { return }
    if tourStep + 1 < walkthrough.count { self.tourStep = tourStep + 1 } else { endTour() }
  }

  func previousStep() {
    guard let tourStep, tourStep > 0 else { return }
    self.tourStep = tourStep - 1
  }

  func endTour() {
    guard tourStep != nil else { return }
    tourStep = nil
    request(.fit)
  }

  private func showStep(_ step: Int) {
    guard walkthrough.indices.contains(step) else {
      tourStep = nil
      return
    }
    selectedNode = nil
    selectedBlock = nil
    let nodes = walkthrough[step].nodes
    request(.frame(level == .overview ? blocks(covering: nodes) : nodes, insets: .belowCard))
  }

  func compare(_ base: VersionRef, _ target: VersionRef) {
    viewing = target
    comparing = base
  }

  func request(_ action: CanvasRequest.Action) {
    requestSerial += 1
    canvasRequest = CanvasRequest(action: action, serial: requestSerial)
  }

  // MARK: Actions

  func add(_ urls: [URL]) {
    var added: TrackedApp?
    var problems: [String] = []
    for url in urls {
      do {
        added = try Library.add(url)
      } catch {
        problems.append(error.localizedDescription)
      }
    }
    reload()
    if let added { selectedID = added.id }
    if !problems.isEmpty { alert = problems.joined(separator: "\n") }
  }

  func chooseFolders() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Track"
    panel.message = "Choose the folders of the apps you want Blueprint to track."
    if panel.runModal() == .OK { add(panel.urls) }
  }

  func remove(_ app: TrackedApp) {
    do {
      try Library.remove(app)
    } catch {
      alert = error.localizedDescription
    }
    reload()
  }

  func saveVersion(_ name: String) {
    guard let app = selectedApp else { return }
    do {
      let snapshot = try Library.saveVersion(name, for: app)
      reload()
      if let version = snapshot.version { viewing = .version(version) }
    } catch {
      alert = error.localizedDescription
    }
  }

  func deleteVersion(_ name: String) {
    guard let app = selectedApp else { return }
    do {
      try Library.removeVersion(name, of: app)
    } catch {
      alert = error.localizedDescription
    }
    reload()
  }

  func suggestedVersionName() -> String {
    guard let app = selectedApp else { return "" }
    return Git.tagAtHead(app.url).map(Library.normalizeVersion) ?? ""
  }

  /// What to ask an agent working in a project to map it, for any project.
  static let mapPrompt = "Add this app to Blueprint and map it, including its past releases. Run `blueprint guide` and follow it."

  /// A section for a project's AGENTS.md or CLAUDE.md, so every agent working in it keeps the map current.
  static let agentsSnippet = """
    ## Blueprint

    This app is mapped in Blueprint. Before changing it, read the map with `blueprint show --json`, or `blueprint show --data --json` for what it stores. After changing its structure, workflows or stored data, run `blueprint status`, update the map as `blueprint guide` explains, and save it with `blueprint set`.
    """

  func prompt(for app: TrackedApp) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    guard data[app.id]?.current != nil else {
      return "Map the architecture of the app in \(path) for Blueprint. Run `blueprint guide` and follow it."
    }
    return "The Blueprint architecture of the app in \(path) is out of date. Run `blueprint status` in that folder to see what changed, then update it following `blueprint guide`."
  }

  func walkthroughPrompt(for app: TrackedApp) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    return "Add a walkthrough to the Blueprint architecture of the app in \(path), and give every component a clear role and details. Run `blueprint guide` to see how."
  }

  func overviewPrompt(for app: TrackedApp) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    return "Add an overview to the Blueprint architecture of the app in \(path): 3 to 6 blocks that explain it in plain words, each standing for some of its components. Run `blueprint guide` to see how."
  }

  func notesPrompt(for app: TrackedApp) -> String {
    let path = (app.path as NSString).abbreviatingWithTildeInPath
    return "Add a note to every connection in the Blueprint architecture of the app in \(path): what travels over it, how and when. Run `blueprint guide` to see how."
  }

  func copyPrompt(for app: TrackedApp) {
    copy(prompt(for: app))
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func reveal(_ app: TrackedApp, path: String? = nil) {
    let url = path.map { app.url.appending(path: $0) } ?? app.url
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  /// Handles blueprint://open?app=<id>&version=<v>&compare=<v>, which `blueprint open` sends.
  func open(_ url: URL) {
    guard url.scheme == "blueprint", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
    let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { $1 }
    reload()
    guard let id = query["app"], apps.contains(where: { $0.id == id }) else { return }
    selectedID = id
    viewing = VersionRef(query["version"])
    comparing = query["compare"].map { VersionRef($0) }
    NSApp.activate()
  }
}
