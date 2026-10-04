import AVFoundation
import SwiftUI

extension Architecture.Explainer {
  /// The intro, then one slide per scene.
  var slideCount: Int { scenes.count + 1 }
}

/// What one slide of an explainer puts on screen, and for how long.
struct ExplainerSlide: Equatable {
  enum Shot: Equatable {
    /// The whole architecture, dimmed, under a title.
    case card
    case architecture(Set<String>)
    case flow(String, Set<String>)
    case data(Set<String>)
  }

  var title: String
  var text: String
  var shot: Shot
  var duration: TimeInterval

  static let introDuration: TimeInterval = 3.5

  /// Long enough to read the title and the text, at about three words a second.
  static func duration(_ scene: Architecture.Scene) -> TimeInterval {
    let words = (scene.title + " " + scene.text).split(whereSeparator: \.isWhitespace).count
    return min(max(2.2 + Double(words) * 0.32, 4), 11)
  }

  static func total(_ explainer: Architecture.Explainer) -> TimeInterval {
    explainer.scenes.map(duration).reduce(introDuration, +)
  }

  /// The intro with the title, then a slide per scene. A scene whose ids aren't on the diagrams becomes a title card.
  static func slides(_ explainer: Architecture.Explainer, in diagram: Diagram) -> [ExplainerSlide] {
    let intro = ExplainerSlide(title: explainer.title, text: explainer.summary ?? "", shot: .card, duration: introDuration)
    return [intro] + explainer.scenes.map { scene in
      let nodes = Set(scene.nodes.filter { diagram.layout.nodes[$0] != nil })
      let entities = Set(scene.entities.filter { diagram.dataLayout.cards[$0] != nil })
      let shot: Shot = if !nodes.isEmpty {
        .architecture(nodes)
      } else if let flow = scene.flow, diagram.architecture.flow(flow) != nil {
        .flow(flow, Set(scene.steps))
      } else if !entities.isEmpty {
        .data(entities)
      } else {
        .card
      }
      return ExplainerSlide(title: scene.title, text: scene.text, shot: shot, duration: duration(scene))
    }
  }

  /// Whether it lights something up, which gets a pop when it lands.
  var highlights: Bool {
    switch shot {
    case .card: false
    case .flow(_, let steps): !steps.isEmpty
    default: true
    }
  }
}

/// Plays an explainer: the stage, and the controls under it. Each slide waits for its duration, then the next one comes.
struct ExplainerPlayer: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp
  let explainer: Architecture.Explainer
  let diagram: Diagram

  @State private var shownSlide = -1
  @State private var wasPlaying = false
  @State private var startedAt = Date()
  @State private var pausedElapsed: TimeInterval = 0

  var body: some View {
    let slides = ExplainerSlide.slides(explainer, in: diagram)
    let slide = min(store.explainerScene, slides.count - 1)
    ZStack {
      WelcomeBackground()
      VStack(spacing: 16) {
        ExplainerStage(app: app, name: store.name(of: app), explainer: explainer, diagram: diagram, slides: slides, slide: slide, playing: store.explainerPlaying)
          .contentShape(Rectangle())
          .onTapGesture { store.toggleExplainer() }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        controls(slides, slide)
      }
      .padding(.horizontal, 36)
      .padding(.top, store.explainers.count > 1 ? 66 : 28)
      .padding(.bottom, 22)
    }
    .task(id: "\(explainer.id)|\(slide)|\(store.explainerPlaying)") { await run(slides, slide) }
    .onDisappear { store.explainerPlaying = false }
  }

  private func run(_ slides: [ExplainerSlide], _ slide: Int) async {
    let now = Date()
    let playing = store.explainerPlaying
    if slide != shownSlide {
      shownSlide = slide
      pausedElapsed = 0
      startedAt = now
      if playing { cue(slides[slide], at: slide) }
    } else if !playing, wasPlaying {
      pausedElapsed = now.timeIntervalSince(startedAt)
    } else if playing, !wasPlaying, slide == 0, pausedElapsed == 0 {
      play(.chime)
    }
    wasPlaying = playing
    guard playing else { return }
    startedAt = now.addingTimeInterval(-pausedElapsed)
    try? await Task.sleep(for: .seconds(max(0, slides[slide].duration - pausedElapsed)))
    guard !Task.isCancelled, store.explainerPlaying else { return }
    if slide + 1 < slides.count {
      store.explainerScene = slide + 1
    } else {
      store.explainerPlaying = false
      play(.chime)
    }
  }

  /// A chime to open, a whoosh as the camera moves, and a pop when the highlight lands.
  private func cue(_ slide: ExplainerSlide, at index: Int) {
    guard index > 0 else { return play(.chime) }
    play(.whoosh)
    guard slide.highlights else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(800))
      if store.explainerPlaying, store.explainerScene == index { play(.pop) }
    }
  }

  private func play(_ effect: ExplainerSound.Effect) {
    if !store.muteExplainers { ExplainerSound.shared.play(effect) }
  }

  private func controls(_ slides: [ExplainerSlide], _ slide: Int) -> some View {
    let playing = store.explainerPlaying
    let durations = slides.map(\.duration)
    return HStack(spacing: 14) {
      Button { store.showSlide(slide - 1) } label: {
        Image(systemName: "backward.fill").frame(width: 24, height: 24).contentShape(Rectangle())
      }
      .disabled(slide == 0)
      .help("Previous scene (←)")
      Button { store.toggleExplainer() } label: {
        Image(systemName: playing ? "pause.fill" : "play.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 34, height: 34)
          .background(Circle().fill(Color.accentColor))
      }
      .help(playing ? "Pause (Space)" : "Play (Space)")
      Button { store.showSlide(slide + 1) } label: {
        Image(systemName: "forward.fill").frame(width: 24, height: 24).contentShape(Rectangle())
      }
      .disabled(slide + 1 >= slides.count)
      .help("Next scene (→)")

      TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { context in
        let elapsed = playing ? min(max(context.date.timeIntervalSince(startedAt), 0), durations[slide]) : pausedElapsed
        HStack(spacing: 12) {
          SlideProgress(durations: durations, slide: slide, elapsed: elapsed) { store.showSlide($0) }
          Text("\(Self.clock(durations.prefix(slide).reduce(0, +) + elapsed)) / \(Self.clock(durations.reduce(0, +)))")
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
        }
      }

      Button { store.muteExplainers.toggle() } label: {
        Image(systemName: store.muteExplainers ? "speaker.slash.fill" : "speaker.wave.2.fill")
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .help(store.muteExplainers ? "Turn the sound effects on" : "Turn the sound effects off")
    }
    .buttonStyle(.plain)
    .font(.system(size: 12, weight: .semibold))
    .padding(.horizontal, 14)
    .frame(height: 50)
    .frame(maxWidth: 760)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
  }

  static func clock(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", whole / 60, whole % 60)
  }
}

/// One bar per slide, as long as the slide lasts, filling up as it plays. Clicking a bar jumps to its slide.
struct SlideProgress: View {
  let durations: [TimeInterval]
  let slide: Int
  let elapsed: TimeInterval
  let select: (Int) -> Void

  var body: some View {
    GeometryReader { proxy in
      let spacing: CGFloat = 3
      let total = max(durations.reduce(0, +), 0.001)
      let room = proxy.size.width - spacing * CGFloat(durations.count - 1)
      HStack(spacing: spacing) {
        ForEach(durations.indices, id: \.self) { index in
          let width = max(room * durations[index] / total, 4)
          let fill = index < slide ? 1 : index == slide ? min(elapsed / durations[index], 1) : 0
          ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.14))
            Capsule().fill(Color.accentColor).frame(width: width * fill)
          }
          .frame(width: width, height: 5)
          .frame(height: proxy.size.height)
          .contentShape(Rectangle())
          .onTapGesture { select(index) }
        }
      }
    }
    .frame(height: 20)
  }
}

/// One slide of an explainer at 1280 × 720, scaled to fit: the diagram its scene points at, with the camera on
/// what it shows, and the caption. Always light, like every explainer, whatever the app's appearance.
struct ExplainerStage: View {
  static let size = CGSize(width: 1280, height: 720)

  let app: TrackedApp
  let name: String
  let explainer: Architecture.Explainer
  let diagram: Diagram
  let slides: [ExplainerSlide]
  let slide: Int
  let playing: Bool

  private let ink = Color(hex: 0x0F172A)
  private let muted = Color(hex: 0x475569)

  var body: some View {
    GeometryReader { proxy in
      let scale = min(proxy.size.width / Self.size.width, proxy.size.height / Self.size.height)
      content
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: Self.size.width * scale, height: Self.size.height * scale, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .aspectRatio(16 / 9, contentMode: .fit)
    .environment(\.colorScheme, .light)
    // Explainers keep one look in every app, whatever theme the canvases use.
    .environment(\.diagramTheme, .blueprint)
  }

  private var content: some View {
    let current = slides[slide]
    let camera = camera(for: current.shot)
    return ZStack(alignment: .topLeading) {
      // The diagram goes in an overlay, so its size never stretches the stage.
      GridBackground(scale: camera.scale, offset: camera.offset, scheme: .light)
        .overlay(alignment: .topLeading) {
          world(current.shot, camera: camera)
            .id(worldKey(current.shot))
            .transition(.opacity)
        }
        .clipped()
      LinearGradient(colors: [.white.opacity(0.92), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
        .frame(height: 100)
        .allowsHitTesting(false)
      if current.shot == .card {
        titleCard(current)
      } else {
        caption(current)
      }
      header
    }
    .animation(.smooth(duration: 1.1), value: slide)
  }

  // MARK: The diagram

  /// The architecture stays one view across its slides, so the camera glides between them instead of cutting.
  private func worldKey(_ shot: ExplainerSlide.Shot) -> String {
    switch shot {
    case .card, .architecture: "architecture"
    case .flow(let id, _): "flow:\(id)"
    case .data: "data"
    }
  }

  @ViewBuilder
  private func world(_ shot: ExplainerSlide.Shot, camera: Camera) -> some View {
    Group {
      switch shot {
      case .card:
        DiagramWorld(diagram: diagram, showLabels: false, spotlight: [], scale: camera.scale)
      case .architecture(let ids):
        DiagramWorld(diagram: diagram, showLabels: true, spotlight: ids, scale: camera.scale)
      case .flow(let id, let steps):
        if let flow = diagram.architecture.flow(id) {
          FlowWorld(
            flow: flow, architecture: diagram.architecture, layout: FlowDiagramLayout(flow),
            selection: nil, hovered: nil, spotlight: steps.isEmpty ? nil : steps, scale: camera.scale,
            onHover: { _, _ in }, onSelect: { _ in }, onFocus: { _ in }
          )
        }
      case .data(let ids):
        DataWorld(
          diagram: diagram, selection: nil, hovered: nil, spotlight: ids, scale: camera.scale,
          onHover: { _, _ in }, onSelect: { _ in }, onFocus: { _ in }
        )
      }
    }
    .scaleEffect(camera.scale, anchor: .topLeading)
    .offset(camera.offset)
    .allowsHitTesting(false)
  }

  /// Frames what the slide shows above the caption, or the whole architecture behind a title card.
  private func camera(for shot: ExplainerSlide.Shot) -> Camera {
    func union(_ frames: [CGRect]) -> CGRect? {
      frames.first.map { first in frames.reduce(first) { $0.union($1) }.insetBy(dx: -50, dy: -50) }
    }
    let area: CGRect
    switch shot {
    case .card:
      area = diagram.layout.bounds
    case .architecture(let ids):
      area = union(ids.compactMap { diagram.layout.nodes[$0] }) ?? diagram.layout.bounds
    case .flow(let id, let steps):
      let layout = diagram.architecture.flow(id).map(FlowDiagramLayout.init)
      area = union(steps.compactMap { layout?.steps[$0] }) ?? layout?.bounds ?? diagram.layout.bounds
    case .data(let ids):
      area = union(ids.compactMap { diagram.dataLayout.cards[$0] }) ?? diagram.dataLayout.bounds
    }
    var camera = Camera()
    let insets = shot == .card
      ? EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40)
      : EdgeInsets(top: 90, leading: 70, bottom: 200, trailing: 70)
    camera.fit(area, in: Self.size, insets: insets, maximum: 1.3)
    return camera
  }

  // MARK: Words

  private var header: some View {
    HStack(spacing: 10) {
      Monogram(name: name, seed: app.id, size: 28)
      VStack(alignment: .leading, spacing: 1) {
        Text(name.uppercased())
          .font(.system(size: 10.5, weight: .bold))
          .tracking(1.2)
          .foregroundStyle(muted)
        Text(explainer.title)
          .font(.system(size: 14.5, weight: .semibold))
          .foregroundStyle(ink)
      }
      Spacer()
      Text("\(slide) / \(slides.count - 1)")
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.9), in: Capsule())
    }
    .padding(.horizontal, 28)
    .padding(.top, 24)
    .opacity(slide == 0 ? 0 : 1)
  }

  private func caption(_ current: ExplainerSlide) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(current.title)
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(ink)
      Text(current.text)
        .font(.system(size: 19))
        .foregroundStyle(muted)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.leading, 20)
    .overlay(alignment: .leading) { Capsule().fill(Theme.brand).frame(width: 4) }
    .padding(.horizontal, 26)
    .padding(.vertical, 22)
    .frame(maxWidth: 920, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .shadow(color: Color(hex: 0x1E3A8A).opacity(0.14), radius: 26, y: 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .padding(.bottom, 30)
    .id(slide)
    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
  }

  private func titleCard(_ current: ExplainerSlide) -> some View {
    let intro = slide == 0
    return ZStack {
      RadialGradient(colors: [.white.opacity(0.94), .white.opacity(0.6)], center: .center, startRadius: 160, endRadius: 820)
      VStack(spacing: 18) {
        if intro {
          HStack(spacing: 10) {
            Monogram(name: name, seed: app.id, size: 36)
            Text(name)
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(muted)
          }
          Text("EXPLAINER")
            .font(.system(size: 12.5, weight: .heavy))
            .tracking(2.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.brand))
        }
        Text(current.title)
          .font(.system(size: intro ? 62 : 52, weight: .bold))
          .foregroundStyle(ink)
          .multilineTextAlignment(.center)
        if !current.text.isEmpty {
          Text(current.text)
            .font(.system(size: 24))
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
        }
        if intro, !playing {
          Image(systemName: "play.fill")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 70, height: 70)
            .background(Circle().fill(Theme.brand))
            .shadow(color: Color(hex: 0x3B82F6).opacity(0.4), radius: 16, y: 6)
            .padding(.top, 10)
            .transition(.scale.combined(with: .opacity))
        }
      }
      .frame(maxWidth: 940)
      .id(slide)
      .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
    .animation(.smooth(duration: 0.3), value: playing)
  }
}

/// A version with no explainers: what they are, and the prompt that asks an agent for them.
struct ExplainersEmpty: View {
  @Environment(AppStore.self) private var store
  let app: TrackedApp

  var body: some View {
    ZStack {
      WelcomeBackground()
      VStack(spacing: 16) {
        Image(systemName: "play.rectangle.on.rectangle")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(Theme.brand)
        Text("No explainers yet")
          .font(.title2.weight(.bold))
        Text("Explainers are short videos about how parts of \(store.name(of: app)) work. An agent writes what each scene shows and says, and Blueprint plays it on the real diagrams, in the same style for every app.")
          .font(.system(size: 13.5))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        PromptCard(text: store.explainersPrompt(for: app), prominent: true)
      }
      .frame(width: 480)
      .padding(40)
    }
  }
}

/// Sound effects for explainers, synthesized once: no files, and nothing playing under them.
@MainActor
final class ExplainerSound {
  static let shared = ExplainerSound()

  enum Effect: CaseIterable {
    case whoosh, pop, chime
  }

  private let engine = AVAudioEngine()
  private var players: [Effect: AVAudioPlayerNode] = [:]
  private var buffers: [Effect: AVAudioPCMBuffer] = [:]
  private var started = false

  private init() {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
    for effect in Effect.allCases {
      guard let buffer = Self.render(effect, format: format) else { continue }
      let player = AVAudioPlayerNode()
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: format)
      players[effect] = player
      buffers[effect] = buffer
    }
  }

  func play(_ effect: Effect) {
    guard let player = players[effect], let buffer = buffers[effect] else { return }
    if !started {
      guard (try? engine.start()) != nil else { return }
      started = true
    }
    player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    if !player.isPlaying { player.play() }
  }

  private static func render(_ effect: Effect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let rate = format.sampleRate
    let duration = switch effect {
    case .whoosh: 0.6
    case .pop: 0.16
    case .chime: 1.6
    }
    let count = AVAudioFrameCount(duration * rate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count), let samples = buffer.floatChannelData?[0] else { return nil }
    buffer.frameLength = count

    var seed: UInt32 = 0x9E37_79B9
    var low: Double = 0
    var phase: Double = 0
    for i in 0..<Int(count) {
      let t = Double(i) / rate
      let value: Double
      switch effect {
      case .whoosh:
        // Noise through a filter that opens and closes, under a swell.
        seed = seed &* 1_664_525 &+ 1_013_904_223
        let noise = Double(seed) / Double(UInt32.max) * 2 - 1
        let progress = t / duration
        let cutoff = 350 + 2800 * sin(.pi * progress)
        low += (1 - exp(-2 * .pi * cutoff / rate)) * (noise - low)
        value = low * pow(sin(.pi * progress), 2)
      case .pop:
        let frequency = 380 + 900 * exp(-t * 30)
        phase += 2 * .pi * frequency / rate
        value = sin(phase) * min(1, t / 0.003) * exp(-t * 30)
      case .chime:
        let envelope = min(1, t / 0.006) * exp(-t * 2.6)
        value = (sin(2 * .pi * 1046.5 * t) * 0.6 + sin(2 * .pi * 1568 * t) * 0.3 + sin(2 * .pi * 2093 * t) * 0.1) * envelope
      }
      samples[i] = Float(value)
    }

    let peak = (0..<Int(count)).reduce(Float(0)) { max($0, abs(samples[$1])) }
    let target: Float = switch effect {
    case .whoosh: 0.32
    case .pop: 0.42
    case .chime: 0.36
    }
    if peak > 0 {
      for i in 0..<Int(count) { samples[i] *= target / peak }
    }
    return buffer
  }
}
