import SwiftUI

struct NodeCard: View {
  let node: Architecture.Node
  var change: Change?
  var isSelected = false
  var isHovered = false
  var isDimmed = false
  var isTouched = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  private var kind: NodeKind { node.nodeKind }

  private var accent: Color {
    guard let change, change != .unchanged else { return kind.color }
    return change.color
  }

  private var subtitle: String {
    ([kind.label] + node.tech.prefix(3)).joined(separator: " · ")
  }

  private var opacity: Double {
    var value = 1.0
    if change == .unchanged { value = 0.55 }
    if change == .removed { value = 0.7 }
    if isDimmed { value = min(value, 0.28) }
    return value
  }

  var body: some View {
    if theme == .blueprint {
      blueprint
    } else {
      themed
    }
  }

  /// The card in Terminal, Minimal and ASCII: flat, with the theme's border and type.
  private var themed: some View {
    let style = DiagramStyle(theme, scheme)
    let shape = RoundedRectangle(cornerRadius: style.cardRadius, style: .continuous)
    let label = theme == .terminal ? subtitle.lowercased() : subtitle
    return Group {
      if theme == .ascii {
        VStack(spacing: 4) {
          Text(node.name)
            .font(style.font(13, .semibold))
            .strikethrough(change == .removed, color: Theme.removed)
          Text("<\(kind.label.lowercased())>")
            .font(style.font(10.5))
            .foregroundStyle(style.secondaryInk)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
      } else {
        HStack(spacing: 11) {
          Image(systemName: kind.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(style.tint(kind.color))
            .frame(width: 22)
          VStack(alignment: .leading, spacing: 3) {
            Text(node.name)
              .font(style.font(13, .semibold))
              .strikethrough(change == .removed, color: Theme.removed)
            Text(label)
              .font(style.font(10.5))
              .foregroundStyle(style.secondaryInk)
          }
          .lineLimit(1)
          Spacer(minLength: 0)
        }
      }
    }
    .foregroundStyle(style.ink)
    .padding(.horizontal, 14)
    .frame(width: DiagramLayout.nodeSize.width, height: DiagramLayout.nodeSize.height)
    .background(shape.fill(style.paper))
    .overlay(themedBorder(shape, style))
    .overlay(alignment: .topTrailing) { badge }
    .shadow(color: style.glow(isSelected ? 0.55 : 0.14), radius: isSelected ? 12 : 6)
    .opacity(opacity)
    .scaleEffect(isHovered && !isSelected ? 1.025 : 1)
    .animation(.snappy(duration: 0.18), value: isHovered)
    .animation(.smooth(duration: 0.25), value: isDimmed)
  }

  @ViewBuilder
  private func themedBorder(_ shape: RoundedRectangle, _ style: DiagramStyle) -> some View {
    if isSelected {
      shape.strokeBorder(change.flatMap { $0 == .unchanged ? nil : $0.color } ?? style.ink, lineWidth: theme == .ascii ? 3 : 2)
    } else if change == .removed {
      shape.strokeBorder(Theme.removed.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    } else if let change, change != .unchanged {
      shape.strokeBorder(change.color, lineWidth: 1.5)
    } else if isHovered {
      shape.strokeBorder(style.ink.opacity(0.7), lineWidth: style.borderWidth)
    } else {
      shape.strokeBorder(style.border, lineWidth: style.borderWidth)
    }
  }

  private var blueprint: some View {
    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    return HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(LinearGradient(colors: [kind.color.mix(with: .white, by: 0.12), kind.color.mix(with: .black, by: 0.22)], startPoint: .top, endPoint: .bottom))
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        Image(systemName: kind.symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: 40, height: 40)
      .shadow(color: kind.color.opacity(scheme == .dark ? 0.5 : 0.3), radius: 6, y: 2)

      VStack(alignment: .leading, spacing: 3) {
        Text(node.name)
          .font(.system(size: 13.5, weight: .semibold))
          .strikethrough(change == .removed, color: Theme.removed)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .frame(width: DiagramLayout.nodeSize.width, height: DiagramLayout.nodeSize.height)
    .background(shape.fill(LinearGradient(colors: [Theme.cardTop(scheme), Theme.card(scheme)], startPoint: .top, endPoint: .bottom)))
    .overlay(border(shape))
    .overlay(alignment: .topTrailing) { badge }
    .shadow(color: glow, radius: isSelected ? 16 : 10, y: isSelected ? 0 : 4)
    .opacity(opacity)
    .scaleEffect(isHovered && !isSelected ? 1.025 : 1)
    .animation(.snappy(duration: 0.18), value: isHovered)
    .animation(.smooth(duration: 0.25), value: isDimmed)
    // No .help tooltip: on macOS it takes the card's clicks and hover away from the canvas.
  }

  @ViewBuilder
  private func border(_ shape: RoundedRectangle) -> some View {
    if isSelected {
      shape.strokeBorder(accent, lineWidth: 2)
    } else if change == .removed {
      shape.strokeBorder(Theme.removed.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    } else if let change, change != .unchanged {
      shape.strokeBorder(change.color, lineWidth: 1.5)
    } else if isHovered {
      shape.strokeBorder(kind.color.opacity(0.7), lineWidth: 1)
    } else {
      shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08), lineWidth: 1)
    }
  }

  private var glow: Color {
    if isSelected { return accent.opacity(0.55) }
    if let change, change == .added || change == .changed { return change.color.opacity(0.35) }
    return .black.opacity(scheme == .dark ? 0.35 : 0.08)
  }

  @ViewBuilder
  private var badge: some View {
    if let change, change != .unchanged {
      Text(change.badge)
        .font(theme == .blueprint ? .system(size: 8.5, weight: .heavy) : DiagramStyle(theme, scheme).font(8.5, .heavy))
        .tracking(0.8)
        .foregroundStyle(.black.opacity(0.78))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: theme == .blueprint ? 8 : DiagramStyle(theme, scheme).cardRadius, style: .continuous).fill(change.color))
        .offset(x: -12, y: -8)
    } else if isTouched {
      Image(systemName: "pencil.circle.fill")
        .font(.system(size: 16))
        .foregroundStyle(.white, Theme.stale)
        .symbolEffect(.pulse, options: .repeat(.continuous))
        .background(Circle().fill(Theme.card(scheme)).padding(1))
        .offset(x: 6, y: -6)
    }
  }
}
