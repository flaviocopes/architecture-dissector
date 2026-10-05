import Foundation

struct Manifest: Encodable {
  struct Capability: Encodable {
    let description: String
    var command: String? = nil
  }

  struct Release: Encodable {
    let version: String
    let date: String
    let changes: [String]
  }

  let name: String
  let version: String
  let summary: String
  let capabilities: [Capability]
  let changelog: [Release]

  static var cliVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
  }

  static var current: Manifest {
    Manifest(
      name: "blueprint",
      version: cliVersion,
      summary: "Tracks apps and saves their architecture, flows, data and explainers as JSON for the Blueprint app to draw, and compares versions.",
      capabilities: [
        Capability(description: "Track an app folder for architecture mapping", command: "blueprint add ~/dev/my-app"),
        Capability(description: "Print the mapping workflow and JSON format for agents", command: "blueprint guide"),
        Capability(description: "Save an app's architecture from JSON", command: "blueprint set myapp --file /tmp/myapp.json"),
        Capability(description: "Print an app's architecture as JSON to edit", command: "blueprint show myapp --json"),
        Capability(description: "Print what an app stores, with entities and fields", command: "blueprint show myapp --data --json"),
        Capability(description: "See what changed in the code since the map was saved", command: "blueprint status myapp --json"),
        Capability(description: "List tracked apps and what each one is still missing", command: "blueprint list --missing flows --json"),
        Capability(description: "Compare an app's architecture between two versions", command: "blueprint diff myapp --from 1.0.0 --json"),
        Capability(description: "Save the current architecture as a release version", command: "blueprint snapshot myapp --version 1.2.0"),
        Capability(description: "Open an app in Blueprint and highlight changes since a version", command: "blueprint open myapp --compare 1.0.0"),
      ],
      changelog: [
        Release(
          version: "1.0.0",
          date: "2026-10-04",
          changes: [
            "First release: track apps, map architectures from JSON, save versions, and diff them.",
            "Commands for status, list --missing, show --data, snapshot, and opening the Blueprint app.",
            "Run blueprint guide for the workflow agents follow when mapping an app.",
          ]
        ),
      ]
    )
  }

  func print(json: Bool) throws {
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      Swift.print(String(decoding: try encoder.encode(self), as: UTF8.self))
      return
    }

    Swift.print("\(name) \(version)\n\(summary)\n\nWhat it can do:")
    for capability in capabilities {
      Swift.print("  \(capability.description)")
      if let command = capability.command { Swift.print("    $ \(command)") }
    }
    Swift.print("\nChanges:")
    for release in changelog {
      Swift.print("  \(release.version) (\(release.date))")
      release.changes.forEach { Swift.print("    - \($0)") }
    }
  }
}
