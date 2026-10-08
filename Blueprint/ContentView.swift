import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Environment(AppStore.self) private var store
  @State private var columns = NavigationSplitViewVisibility.all

  var body: some View {
    @Bindable var store = store
    NavigationSplitView(columnVisibility: $columns) {
      Sidebar()
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
    } detail: {
      DetailView()
        .environment(\.diagramTheme, store.diagramTheme)
    }
    // The welcome screen takes the whole window until the first app is tracked.
    .onChange(of: store.apps.isEmpty, initial: true) { _, empty in
      withAnimation { columns = empty ? .detailOnly : .all }
    }
    .onDrop(of: [.fileURL], isTargeted: $store.isDropTargeted) { providers in
      // Each item loads on its own, and only its URL crosses back, since item providers aren't sendable.
      for provider in providers {
        _ = provider.loadObject(ofClass: URL.self) { [tracker = self.store] url, _ in
          guard let url, isFolder(url) else { return }
          Task { @MainActor in tracker.add([url]) }
        }
      }
      return true
    }
    .overlay {
      if store.isDropTargeted, store.selectedApp != nil { DropOverlay() }
    }
    .alert("Architecture Dissector", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
      Button("OK") { store.alert = nil }
    } message: {
      Text(store.alert ?? "")
    }
    .sheet(isPresented: $store.isSavingVersion) {
      SaveVersionSheet(suggested: store.suggestedVersionName()) { store.saveVersion($0) }
    }
    .sheet(isPresented: $store.isShowingSetup) {
      SetupSheet()
    }
  }
}

/// Whether a dropped item is a folder. Files are skipped, since Architecture Dissector tracks app folders.
func isFolder(_ url: URL) -> Bool {
  var isDirectory: ObjCBool = false
  return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
}

struct DropOverlay: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.accentColor.opacity(0.08))
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
      VStack(spacing: 10) {
        Image(systemName: "folder.badge.plus")
          .font(.system(size: 44, weight: .light))
        Text("Drop app folders to track them")
          .font(.title3.weight(.semibold))
      }
      .foregroundStyle(Color.accentColor)
    }
    .padding(12)
    .allowsHitTesting(false)
  }
}

struct Sidebar: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    @Bindable var store = store
    List(selection: $store.selectedID) {
      Section("Apps") {
        ForEach(store.apps) { app in
          AppRow(app: app, name: store.name(of: app), data: store.data[app.id])
            .tag(app.id)
            .contextMenu {
              Button("Show in Finder") { store.reveal(app) }
              Button("Copy Prompt for Agent") { store.copyPrompt(for: app) }
              Divider()
              Button("Stop Tracking", role: .destructive) { store.remove(app) }
            }
        }
      }
    }
    .overlay {
      if store.apps.isEmpty {
        Text("The apps you track show up here.")
          .font(.callout)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
          .padding(24)
      }
    }
    .safeAreaInset(edge: .bottom) {
      HStack {
        Button { store.chooseFolders() } label: {
          Label("Track App Folder", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
  }
}

struct AppRow: View {
  let app: TrackedApp
  let name: String
  let data: AppData?

  private var detail: String {
    guard let current = data?.current else { return "Not mapped yet" }
    let versions = data?.versions.count ?? 0
    let components = "\(current.architecture.nodes.count) components"
    return versions == 0 ? components : "\(components) · \(versions) version\(versions == 1 ? "" : "s")"
  }

  var body: some View {
    HStack(spacing: 10) {
      Monogram(name: name, seed: app.id)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      StatusDot(data: data)
    }
    .padding(.vertical, 3)
  }
}

struct StatusDot: View {
  let data: AppData?

  var body: some View {
    if data?.current == nil {
      Image(systemName: "circle.dashed")
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .help("No architecture yet")
    } else if let status = data?.status, status.hasManifest {
      if status.isStale {
        Text("\(status.changedFiles.count)")
          .font(.system(size: 10, weight: .bold).monospacedDigit())
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(Theme.stale))
          .help("\(status.changedFiles.count) files changed since the architecture was saved")
      } else {
        Circle()
          .fill(Theme.added)
          .frame(width: 7, height: 7)
          .help("Up to date")
      }
    }
  }
}

struct Monogram: View {
  let name: String
  let seed: String
  var size: CGFloat = 30

  var body: some View {
    let hash = seed.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    let color = Theme.groupColor(abs(hash))
    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
      .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.1), color.mix(with: .black, by: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
      .overlay(
        Text(String(name.prefix(1)).uppercased())
          .font(.system(size: size * 0.47, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
      )
      .frame(width: size, height: size)
  }
}

struct SaveVersionSheet: View {
  @State var name: String
  let save: (String) -> Void
  @Environment(\.dismiss) private var dismiss

  init(suggested: String, save: @escaping (String) -> Void) {
    _name = State(initialValue: suggested)
    self.save = save
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Save Current as Version")
        .font(.headline)
      Text("Architecture Dissector keeps a copy of the current architecture under this name, so you can compare it with later versions.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      TextField("Version", text: $name, prompt: Text("1.2.0"))
        .textFieldStyle(.roundedBorder)
        .onSubmit(submit)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Save", action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
  }

  private func submit() {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    save(trimmed)
    dismiss()
  }
}
