import SwiftUI

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}

extension NodeKind {
  var symbol: String {
    switch self {
    case .user: "person.fill"
    case .client: "macwindow"
    case .ui: "rectangle.3.group.fill"
    case .service: "gearshape.2.fill"
    case .api: "network"
    case .worker: "bolt.fill"
    case .cli: "terminal.fill"
    case .database: "cylinder.split.1x2.fill"
    case .storage: "externaldrive.fill"
    case .queue: "tray.2.fill"
    case .external: "cloud.fill"
    }
  }

  var color: Color {
    switch self {
    case .user: Color(hex: 0x9CA3AF)
    case .client: Color(hex: 0x3B82F6)
    case .ui: Color(hex: 0x6366F1)
    case .service: Color(hex: 0x8B5CF6)
    case .api: Color(hex: 0x14B8A6)
    case .worker: Color(hex: 0xF97316)
    case .cli: Color(hex: 0x22C55E)
    case .database: Color(hex: 0x0EA5E9)
    case .storage: Color(hex: 0xEAB308)
    case .queue: Color(hex: 0xEC4899)
    case .external: Color(hex: 0x64748B)
    }
  }
}

extension StepKind {
  var symbol: String {
    switch self {
    case .action: "hand.tap.fill"
    case .system: "gearshape.fill"
    case .decision: "arrow.triangle.branch"
    case .done: "checkmark.seal.fill"
    }
  }

  var color: Color {
    switch self {
    case .action: Color(hex: 0x3B82F6)
    case .system: Color(hex: 0x8B5CF6)
    case .decision: Color(hex: 0xF59E0B)
    case .done: Color(hex: 0x22C55E)
    }
  }
}

extension FlowActor {
  var symbol: String {
    switch self {
    case .user: "person.fill"
    case .owner: "wrench.and.screwdriver.fill"
    case .agent: "sparkles"
    case .app: "gearshape.2.fill"
    }
  }
}

extension Change {
  var color: Color {
    switch self {
    case .added: Theme.added
    case .removed: Theme.removed
    case .changed: Theme.changed
    case .unchanged: .secondary
    }
  }

  var badge: String {
    switch self {
    case .added: "NEW"
    case .removed: "REMOVED"
    case .changed: "CHANGED"
    case .unchanged: ""
    }
  }
}

/// How the diagrams look. Every theme draws the same layout; only the colors, lines and type change.
enum DiagramTheme: String, CaseIterable, Sendable {
  case blueprint, terminal, minimal, ascii

  var label: String {
    switch self {
    case .blueprint: "Blueprint"
    case .terminal: "Terminal"
    case .minimal: "Minimal"
    case .ascii: "ASCII"
    }
  }

  /// Terminal is always a dark screen. The others follow the app.
  var colorScheme: ColorScheme? {
    self == .terminal ? .dark : nil
  }
}

extension EnvironmentValues {
  @Entry var diagramTheme: DiagramTheme = .blueprint
}

/// The colors, lines and type of a theme other than Blueprint, which keeps its own richer look.
struct DiagramStyle {
  let theme: DiagramTheme
  let scheme: ColorScheme

  init(_ theme: DiagramTheme, _ scheme: ColorScheme) {
    self.theme = theme
    self.scheme = scheme
  }

  static let phosphor = Color(hex: 0x3DFF9A)

  /// Terminal and ASCII set everything in a monospaced face.
  func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: theme == .terminal || theme == .ascii ? .monospaced : .default)
  }

  var cardRadius: CGFloat {
    switch theme {
    case .blueprint: 14
    case .terminal: 3
    case .minimal: 10
    case .ascii: 0
    }
  }

  var boxRadius: CGFloat {
    switch theme {
    case .blueprint: 22
    case .terminal: 4
    case .minimal: 16
    case .ascii: 0
    }
  }

  /// Connections run straight with right-angle turns, like traces or box-drawing lines.
  var isOrthogonal: Bool { theme == .terminal || theme == .ascii }

  /// Text and lines.
  var ink: Color {
    switch theme {
    case .terminal: Self.phosphor
    case .ascii: scheme == .dark ? Color(hex: 0xE6E6E6) : Color(hex: 0x111111)
    default: scheme == .dark ? Color(hex: 0xF4F4F5) : Color(hex: 0x18181B)
    }
  }

  var secondaryInk: Color { ink.opacity(theme == .terminal ? 0.58 : 0.5) }

  var paper: Color {
    switch theme {
    case .blueprint: Theme.card(scheme)
    case .terminal: Color(hex: 0x06120C)
    case .minimal: scheme == .dark ? Color(hex: 0x1F1F22) : .white
    // The sheet itself: boxes are drawn on it, not filled on top of it.
    case .ascii: scheme == .dark ? Color(hex: 0x111111) : .white
    }
  }

  /// What a kind's color becomes: kept for Minimal's small symbols, phosphor on a terminal, ink on paper.
  func tint(_ color: Color) -> Color {
    switch theme {
    case .blueprint, .minimal: color
    case .terminal: Self.phosphor
    case .ascii: ink
    }
  }

  var border: Color {
    switch theme {
    case .blueprint: scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    case .terminal: Self.phosphor.opacity(0.5)
    case .minimal: ink.opacity(scheme == .dark ? 0.16 : 0.13)
    case .ascii: ink
    }
  }

  var borderWidth: CGFloat { theme == .ascii ? 1.5 : 1 }

  /// A faint phosphor glow around what's on a terminal.
  func glow(_ strength: Double) -> Color {
    theme == .terminal ? Self.phosphor.opacity(strength) : .clear
  }
}

enum Theme {
  static let added = Color(hex: 0x34D399)
  static let removed = Color(hex: 0xF87171)
  static let changed = Color(hex: 0xFBBF24)
  static let stale = Color(hex: 0xFB923C)
  static let brand = LinearGradient(colors: [Color(hex: 0x3B82F6), Color(hex: 0x8B5CF6)], startPoint: .topLeading, endPoint: .bottomTrailing)

  static let groupColors: [Color] = [
    Color(hex: 0x60A5FA), Color(hex: 0xA78BFA), Color(hex: 0x2DD4BF), Color(hex: 0xFB923C),
    Color(hex: 0xF472B6), Color(hex: 0x4ADE80), Color(hex: 0x818CF8), Color(hex: 0xFACC15),
  ]

  static func groupColor(_ index: Int) -> Color { groupColors[index % groupColors.count] }

  static func backgroundTop(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x0C1631) : Color(hex: 0xF5F7FB) }
  static func backgroundBottom(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x080F22) : Color(hex: 0xECF0F7) }
  static func grid(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x6E9BFF) : Color(hex: 0x3563D9) }
  static func card(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x121D3B) : .white }
  static func cardTop(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x182650) : .white }
  static func edge(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xA9BCE8) : Color(hex: 0x475569) }
}
