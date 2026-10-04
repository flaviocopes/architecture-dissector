import CoreServices
import Foundation

final class FileWatcher: @unchecked Sendable {
  private let handler: @Sendable ([String]) -> Void
  private let queue = DispatchQueue(label: "com.flaviocopes.blueprint.watcher")
  private var stream: FSEventStreamRef?

  init(paths: [String], latency: TimeInterval = 2, handler: @escaping @Sendable ([String]) -> Void) {
    self.handler = handler

    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
      guard let info else { return }
      let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
      let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
      watcher.handler(changed)
    }
    let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

    guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
      return
    }
    self.stream = stream
    FSEventStreamSetDispatchQueue(stream, queue)
    FSEventStreamStart(stream)
  }

  deinit {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }
}
