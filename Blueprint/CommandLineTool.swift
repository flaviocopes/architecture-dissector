import AppKit

/// Links the `blueprint` command bundled in the app into /usr/local/bin.
enum CommandLineTool {
  static let link = URL(fileURLWithPath: "/usr/local/bin/blueprint")
  static let bundled = Bundle.main.bundleURL.appending(path: "Contents/Helpers/blueprint")

  static var isInstalled: Bool {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == bundled.path
  }

  @MainActor
  static func install() {
    let fm = FileManager.default
    if isInstalled {
      show("The blueprint command is already installed.", detail: "Run blueprint help in your terminal to see what it does.")
      return
    }

    do {
      try? fm.removeItem(at: link)
      try fm.createSymbolicLink(at: link, withDestinationURL: bundled)
    } catch {
      let command = "mkdir -p /usr/local/bin && ln -sf '\(bundled.path)' '\(link.path)'"
      var failure: NSDictionary?
      NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges")?.executeAndReturnError(&failure)
      if let failure {
        if failure[NSAppleScript.errorNumber] as? Int == -128 { return }
        show("Couldn't install the command.", detail: failure[NSAppleScript.errorMessage] as? String ?? "")
        return
      }
    }
    show("Installed the blueprint command.", detail: "Open a new terminal window and run blueprint help to get started. Agents learn the format with blueprint guide.")
  }

  @MainActor
  private static func show(_ message: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.runModal()
  }
}
