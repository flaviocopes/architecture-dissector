import Foundation

struct CLIError: LocalizedError {
  var message: String
  var usage = false
  var errorDescription: String? { message }
}

struct Arguments {
  var command: String?
  var positional: [String] = []
  private var flags: Set<String> = []
  private var options: [String: String] = [:]

  private static let valued: Set<String> = ["file", "version", "from", "to", "compare", "missing"]

  init(_ raw: [String]) throws {
    var queue = raw[...]
    while let argument = queue.popFirst() {
      if argument == "-h" {
        flags.insert("help")
      } else if argument.hasPrefix("--") {
        var name = String(argument.dropFirst(2))
        var value: String?
        if let equals = name.firstIndex(of: "=") {
          value = String(name[name.index(after: equals)...])
          name = String(name[..<equals])
        }
        if name == "version", value == nil, queue.first?.hasPrefix("-") ?? true {
          flags.insert(name)
        } else if Self.valued.contains(name) {
          guard let value = value ?? queue.popFirst() else { throw CLIError(message: "--\(name) needs a value.", usage: true) }
          options[name] = value
        } else {
          flags.insert(name)
        }
      } else if command == nil {
        command = argument
      } else {
        positional.append(argument)
      }
    }
  }

  func flag(_ name: String) -> Bool { flags.contains(name) }
  func option(_ name: String) -> String? { options[name] }
  var json: Bool { flag("json") }

  func check(allowed: [String]) throws {
    let known = Set(allowed + ["help", "no-color", "version"])
    if let unknown = flags.union(options.keys).subtracting(known).sorted().first {
      throw CLIError(message: "\(command.map { "\($0) doesn't take" } ?? "Unknown option") --\(unknown).", usage: true)
    }
  }

  /// The app named by the first argument, or the one that contains the current folder.
  func app() throws -> TrackedApp {
    guard positional.count <= 1 else { throw CLIError(message: "Pass one app at a time.", usage: true) }
    return try Library.resolve(positional.first)
  }
}

enum Command: String, CaseIterable {
  case list, add, show, set, status, snapshot, versions, diff, open, remove, guide, capabilities

  var synopsis: String {
    switch self {
    case .capabilities: "capabilities [--json]"
    case .list: "list [--missing <part>] [--json]"
    case .add: "add [folder]"
    case .show: "show [app] [--version <v>] [--data] [--json]"
    case .set: "set [app] [--file <path>] [--version <v> [--past]]"
    case .status: "status [app] [--json]"
    case .snapshot: "snapshot [app] [--version <v>] [--force | --delete]"
    case .versions: "versions [app] [--json]"
    case .diff: "diff [app] [--from <v>] [--to <v>] [--json]"
    case .open: "open [app] [--version <v>] [--compare <v>]"
    case .remove: "remove [app]"
    case .guide: "guide"
    }
  }

  var summary: String {
    switch self {
    case .capabilities: "What blueprint can do, and what changed in each version"
    case .list: "The apps Blueprint tracks, and whether their architecture is up to date"
    case .add: "Track an app folder"
    case .show: "Print an app's architecture"
    case .set: "Save an app's architecture from JSON"
    case .status: "What changed in the code since the architecture was saved"
    case .snapshot: "Save the current architecture as a version, like 1.2.0"
    case .versions: "An app's saved versions"
    case .diff: "What changed in the architecture between two versions"
    case .open: "Show an app in the Blueprint app"
    case .remove: "Stop tracking an app"
    case .guide: "How to map an app's architecture, for agents"
    }
  }

  var details: String {
    switch self {
    case .capabilities:
      "Prints a short summary, the main tasks this command can handle, with an example command for each, and what changed in each release. With --json it prints the same manifest for other tools and agents to read."
    case .list:
      "Lists the tracked apps, with how many components and entities their architecture has, how many versions you saved, whether code changed since the last save, and what's still missing: the architecture itself, the walkthrough, the overview, the notes on connections (when most have none), the flows (none, too few, or some without an actor or area), the explainers, or the data of an app that stores something. With --missing it lists only the apps missing that part, so an agent can add it to each one."
    case .add:
      "Starts tracking a folder, the current one if you don't pass one. Blueprint keeps its data in its own folder and never writes to the app's folder. Then map the architecture: run blueprint guide to see how."
    case .show:
      "Prints the current architecture of an app, or a saved version. With --json it prints the same JSON blueprint set takes, so you can edit it and save it back. With --data it prints only what the app stores: the components that hold data, and every entity with its fields."
    case .set:
      "Reads an architecture as JSON from --file or from standard input, checks it, and saves it as the app's current architecture, along with the commit and the files it describes. The app redraws it right away. With --version and --past, it saves an older release instead and leaves the current architecture alone. Run blueprint guide to see the format."
    case .status:
      "Compares the app's files with the ones the architecture described when it was saved, and lists what changed, by component. Docs and images don't count. Needs a git repository."
    case .snapshot:
      "Saves a copy of the current architecture as a version, so you can compare versions later. The version defaults to the git tag on the current commit, without its v. Use --force to replace a version, or --delete to move one to the Trash."
    case .versions:
      "Lists the versions saved for an app, oldest first, then the current architecture."
    case .diff:
      "Lists the components, connections and entities that were added, removed or changed between two versions. --from defaults to the newest version, and --to to the current architecture."
    case .open:
      "Opens the Blueprint app on this app. With --version it shows that version, and with --compare it highlights what changed since that version."
    case .remove:
      "Stops tracking an app, and moves its architecture and versions to the Trash. The app's own folder stays as it is."
    case .guide:
      "Prints the instructions an agent follows to map an app: the workflow, what a good architecture looks like, the JSON format and an example."
    }
  }

  var options: [(flag: String, help: String)] {
    let json = ("--json", "Print JSON")
    switch self {
    case .capabilities: return [json]
    case .list: return [("--missing <part>", "Only the apps missing architecture, walkthrough, overview, notes, flows, data or explainers"), json]
    case .versions, .status: return [json]
    case .add, .remove, .guide: return []
    case .show: return [("--version <v>", "Show this saved version"), ("--data", "Only the stores and entities, with their fields"), json]
    case .set: return [
      ("--file <path>", "Read the JSON from this file instead of standard input"),
      ("--version <v>", "Also save it as this version"),
      ("--past", "Save it only as --version, for a release that already shipped"),
      ("--dry-run", "Check the JSON and save nothing"),
    ]
    case .snapshot: return [
      ("--version <v>", "The version name (default: the git tag on HEAD)"),
      ("--force", "Replace the version if it exists"),
      ("--delete", "Move the version to the Trash"),
    ]
    case .diff: return [("--from <v>", "The older version"), ("--to <v>", "The newer version, or current"), json]
    case .open: return [("--version <v>", "Show this version"), ("--compare <v>", "Highlight what changed since this version")]
    }
  }

  var optionNames: [String] {
    options.map { String($0.flag.dropFirst(2).prefix { $0 != " " }) }
  }

  func run(_ args: Arguments) throws {
    switch self {
    case .list: try Commands.list(args)
    case .add: try Commands.add(args)
    case .show: try Commands.show(args)
    case .set: try Commands.set(args)
    case .status: try Commands.status(args)
    case .snapshot: try Commands.snapshot(args)
    case .versions: try Commands.versions(args)
    case .diff: try Commands.diff(args)
    case .open: try Commands.open(args)
    case .remove: try Commands.remove(args)
    case .guide: print(Guide.text)
    case .capabilities: try Manifest.current.print(json: args.json)
    }
  }
}

func printHelp(_ command: Command?) {
  let bold = Terminal.bold
  guard let command else {
    print(Terminal.wrap("Blueprint draws the architecture of your apps and shows how it changes between versions. Agents map an app with this command, and the Blueprint app draws it."))
    print()
    print("\(bold("Usage:")) blueprint [command] [options]")
    print()
    print(bold("Commands:"))
    for command in Command.allCases {
      print("  \(Terminal.pad(command.rawValue, 10)) \(command.summary)")
    }
    print()
    print(Terminal.wrap("Commands that take an app accept its id, its name or its folder. Without one, they use the tracked app that contains the current folder."))
    print()
    print("Run blueprint guide to see how to map an app.")
    print("Run blueprint help <command> to see its options.")
    return
  }

  print("\(bold("Usage:")) blueprint \(command.synopsis)")
  print()
  print(Terminal.wrap(command.details))
  guard !command.options.isEmpty else { return }
  print()
  print(bold("Options:"))
  for option in command.options {
    print("  \(Terminal.pad(option.flag, 18)) \(option.help)")
  }
}

var version: String { Manifest.cliVersion }

do {
  let args = try Arguments(Array(CommandLine.arguments.dropFirst()))
  if args.flag("no-color") { Terminal.colors = false }

  if args.flag("version"), args.command == nil {
    print("blueprint \(version)")
  } else if args.command == "help" {
    let name = args.positional.first
    guard let command = name.map(Command.init(rawValue:)) ?? .some(nil) else {
      throw CLIError(message: "There's no \(name ?? "") command.", usage: true)
    }
    printHelp(command)
  } else if let name = args.command {
    guard let command = Command(rawValue: name) else { throw CLIError(message: "There's no \(name) command.", usage: true) }
    if args.flag("help") {
      printHelp(command)
    } else {
      try args.check(allowed: command.optionNames)
      try command.run(args)
    }
  } else if args.flag("help") {
    printHelp(nil)
  } else {
    try Commands.list(args)
  }
} catch {
  let usage = (error as? CLIError)?.usage == true
  Terminal.note("blueprint: \(error.localizedDescription)")
  if usage { Terminal.note("Run blueprint help for usage.") }
  exit(usage ? 2 : 1)
}
