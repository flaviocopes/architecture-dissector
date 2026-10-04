import Foundation

enum Terminal {
  static let isTTY = isatty(STDOUT_FILENO) == 1
  nonisolated(unsafe) static var colors = isTTY && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

  static var width: Int {
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
    return Int(ProcessInfo.processInfo.environment["COLUMNS"] ?? "") ?? 100
  }

  static func style(_ text: String, _ code: String) -> String {
    colors ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
  }

  static func bold(_ text: String) -> String { style(text, "1") }
  static func dim(_ text: String) -> String { style(text, "2") }
  static func green(_ text: String) -> String { style(text, "32") }
  static func red(_ text: String) -> String { style(text, "31") }
  static func yellow(_ text: String) -> String { style(text, "33") }
  static func blue(_ text: String) -> String { style(text, "34") }

  static func note(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }

  /// Pads before styling, since escape codes would count as characters.
  static func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
  }

  static func truncate(_ text: String, _ width: Int) -> String {
    guard width > 1 else { return "" }
    let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
    return line.count <= width ? line : line.prefix(width - 1) + "…"
  }

  static func wrap(_ text: String, indent: String = "", width: Int = min(Terminal.width, 100)) -> String {
    var lines: [String] = []
    var line = ""
    for word in text.split(whereSeparator: \.isWhitespace) {
      if !line.isEmpty, indent.count + line.count + word.count + 1 > width {
        lines.append(indent + line)
        line = ""
      }
      line += line.isEmpty ? String(word) : " \(word)"
    }
    if !line.isEmpty { lines.append(indent + line) }
    return lines.joined(separator: "\n")
  }

  static func ago(_ date: Date) -> String {
    if abs(date.timeIntervalSinceNow) < 60 { return "just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: .now)
  }

  static func plural(_ count: Int, _ word: String) -> String {
    "\(count) \(word)\(count == 1 ? "" : "s")"
  }
}
