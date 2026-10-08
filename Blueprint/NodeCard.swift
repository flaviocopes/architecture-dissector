import SwiftUI

struct NodeCard: View {
  let node: Architecture.Node
  var level: DiagramLevel = .inDepth
  var change: Change?
  var isSelected = false
  var isHovered = false
  var isDimmed = false
  var isTouched = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.diagramTheme) private var theme

  private var kind: NodeKind { node.nodeKind }
  private var size: CGSize { level.metrics.node }

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
      if level != .inDepth {
        detailed(style)
      } else if theme == .ascii {
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
        .padding(.horizontal, 14)
      } else {
        HStack(spacing: 11) {
          icon(22, style)
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
        .padding(.horizontal, 14)
      }
    }
    .foregroundStyle(style.ink)
    .frame(width: size.width, height: size.height)
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
    return Group {
      if level != .inDepth {
        detailed(nil)
      } else {
        HStack(spacing: 12) {
          icon(40, nil)
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
      }
    }
    .frame(width: size.width, height: size.height)
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

  /// The kind's symbol: a tile with a gradient in Architecture Dissector, a tinted symbol in the other themes, nothing in ASCII.
  @ViewBuilder
  private func icon(_ side: CGFloat, _ style: DiagramStyle?) -> some View {
    if let style {
      if theme != .ascii {
        Image(systemName: kind.symbol)
          .font(.system(size: side * 0.64, weight: .semibold))
          .foregroundStyle(style.tint(kind.color))
          .frame(width: side)
      }
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: side / 4, style: .continuous)
          .fill(LinearGradient(colors: [kind.color.mix(with: .white, by: 0.12), kind.color.mix(with: .black, by: 0.22)], startPoint: .top, endPoint: .bottom))
        RoundedRectangle(cornerRadius: side / 4, style: .continuous)
          .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        Image(systemName: kind.symbol)
          .font(.system(size: side * 0.4, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: side, height: side)
      .shadow(color: kind.color.opacity(scheme == .dark ? 0.5 : 0.3), radius: 6, y: 2)
    }
  }

  /// The overview card, a name over what it does in plain words, in type big enough to read with the whole
  /// overview in view, or the technical one, which adds the component's points, tech and files.
  /// `style` is nil in Architecture Dissector.
  @ViewBuilder
  private func detailed(_ style: DiagramStyle?) -> some View {
    if level == .overview {
      plainWords(style)
    } else {
      technical(style)
    }
  }

  private func font(_ size: CGFloat, _ weight: Font.Weight = .regular, _ style: DiagramStyle?) -> Font {
    style?.font(size, weight) ?? .system(size: size, weight: weight)
  }

  private func plainWords(_ style: DiagramStyle?) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        icon(30, style)
        Text(node.name)
          .font(font(17, .semibold, style))
          .strikethrough(change == .removed, color: Theme.removed)
          .lineLimit(2)
      }
      if let summary = node.summary {
        Text(summary)
          .font(font(14, .regular, style))
          .foregroundStyle(style?.secondaryInk ?? Color.secondary)
          .lineSpacing(2)
          .lineLimit(5)
      }
    }
    .padding(16)
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }

  private func technical(_ style: DiagramStyle?) -> some View {
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { self.font(size, weight, style) }
    let secondary = style?.secondaryInk ?? Color.secondary
    let bullet = style.map { $0.tint(kind.color) } ?? kind.color
    let line = theme == .terminal ? subtitle.lowercased() : theme == .ascii ? "<\(subtitle.lowercased())>" : subtitle

    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        icon(34, style)
        VStack(alignment: .leading, spacing: 2) {
          Text(node.name)
            .font(font(13.5, .semibold))
            .strikethrough(change == .removed, color: Theme.removed)
            .lineLimit(2)
          Text(line)
            .font(font(10.5))
            .foregroundStyle(secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      if let summary = node.summary {
        Text(summary)
          .font(font(11.5, .medium))
          .lineSpacing(1)
          .lineLimit(3)
      }
      if !node.details.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(node.details.prefix(3), id: \.self) { detail in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(theme == .ascii ? "-" : "•")
                .font(font(11, .heavy))
                .foregroundStyle(bullet)
              Text(detail)
                .font(font(10.5))
                .foregroundStyle(secondary)
                .lineLimit(2)
            }
          }
        }
      }
      Spacer(minLength: 0)
      if !node.paths.isEmpty {
        Text(node.paths.joined(separator: "  "))
          .font(style?.font(9.5) ?? .system(size: 9.5, design: .monospaced))
          .foregroundStyle(secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(14)
    .frame(width: size.width, height: size.height, alignment: .topLeading)
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
