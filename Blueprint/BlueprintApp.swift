import SwiftUI

@main
struct BlueprintApp: App {
  @State private var store = AppStore()

  init() {
    AppUpdater.shared.start(repository: "flaviocopes/blueprint")
  }

  var body: some Scene {
    Window("Blueprint", id: "main") {
      ContentView()
        .environment(store)
        .task { store.start() }
        .onOpenURL { store.open($0) }
    }
    .defaultSize(width: 1320, height: 820)
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") {
          AppUpdater.shared.checkForUpdates()
        }
      }
      CommandGroup(after: .appSettings) {
        Button("Set Up Agents…") { store.isShowingSetup = true }
        Button("Install Command Line Tool…") { CommandLineTool.install() }
        Button("Install Agent Skill…") { AgentSkill.installFromMenu() }
      }
      CommandGroup(replacing: .newItem) {
        Button("Track App Folder…") { store.chooseFolders() }
          .keyboardShortcut("o")
      }
      CommandMenu("Diagram") {
        Picker("Show", selection: $store.mode) {
          Text("Architecture").tag(CanvasMode.architecture)
            .keyboardShortcut("a", modifiers: [.command, .shift])
          Text("Flows").tag(CanvasMode.flows)
            .keyboardShortcut("f", modifiers: [.command, .shift])
          Text("Data").tag(CanvasMode.data)
            .keyboardShortcut("d", modifiers: [.command, .shift])
          Text("Explainers").tag(CanvasMode.explainers)
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        .pickerStyle(.inline)
        .disabled(store.selectedData?.current == nil)
        Divider()
        Picker("Level", selection: $store.level) {
          Text("Overview").tag(DiagramLevel.overview)
            .keyboardShortcut("1", modifiers: [.command, .option])
          Text("In Depth").tag(DiagramLevel.inDepth)
            .keyboardShortcut("2", modifiers: [.command, .option])
          Text("Technical").tag(DiagramLevel.technical)
            .keyboardShortcut("3", modifiers: [.command, .option])
        }
        .pickerStyle(.inline)
        .disabled(store.selectedData?.current == nil || store.mode != .architecture)
        Divider()
        Picker("Theme", selection: $store.diagramTheme) {
          ForEach(DiagramTheme.allCases, id: \.self) { theme in
            Text(theme.label).tag(theme)
          }
        }
        Divider()
        Button("Zoom In") { store.request(.zoomIn) }
          .keyboardShortcut("=")
        Button("Zoom Out") { store.request(.zoomOut) }
          .keyboardShortcut("-")
        Button("Actual Size") { store.request(.actualSize) }
          .keyboardShortcut("0")
        Button("Zoom to Fit") { store.request(.fit) }
          .keyboardShortcut("1")
        Divider()
        Toggle("Show Connection Labels", isOn: $store.showLabels)
          .keyboardShortcut("l")
        Toggle("Show Inspector", isOn: $store.showInspector)
          .keyboardShortcut("i", modifiers: [.command, .option])
        Divider()
        Button("Save Current as Version…") { store.isSavingVersion = true }
          .keyboardShortcut("s")
          .disabled(store.selectedData?.current == nil)
        Button(store.tourStep != nil ? "End Walkthrough" : "Stop Comparing") {
          if store.tourStep != nil { store.endTour() } else { store.comparing = nil }
        }
        .keyboardShortcut(.escape, modifiers: [])
        .disabled(store.tourStep == nil && store.comparing == nil)
        Divider()
        Button("Take the Tour") {
          store.mode = .architecture
          store.startTour()
        }
        .disabled(store.walkthrough.isEmpty)
        Button("Next Step") {
          if store.tourStep != nil {
            store.nextStep()
          } else if store.mode == .explainers {
            store.showSlide(store.explainerScene + 1)
          } else {
            store.moveStep(by: 1)
          }
        }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(!canStep)
        Button("Previous Step") {
          if store.tourStep != nil {
            store.previousStep()
          } else if store.mode == .explainers {
            store.showSlide(store.explainerScene - 1)
          } else {
            store.moveStep(by: -1)
          }
        }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(!canStep)
        // A bare space would take typing away from text fields, so it only works while an explainer is on screen.
        Button(store.explainerPlaying ? "Pause Explainer" : "Play Explainer") { store.toggleExplainer() }
          .keyboardShortcut(.space, modifiers: [])
          .disabled(store.mode != .explainers || store.currentExplainer == nil || store.isSavingVersion)
      }
    }
  }

  private var canStep: Bool {
    store.tourStep != nil
      || (store.mode == .flows && store.currentFlow != nil)
      || (store.mode == .explainers && store.currentExplainer != nil && !store.isSavingVersion)
  }
}
