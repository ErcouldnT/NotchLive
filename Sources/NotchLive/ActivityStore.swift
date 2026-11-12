import Combine
import CoreServices
import Foundation

/// Watches the folder where macOS stores Live Activity archives mirrored from the
/// iPhone, and publishes the most recently updated one.
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var current: LiveActivity?
    /// Fires when an update arrives that the iPhone app marked as an alert.
    let alerts = PassthroughSubject<Void, Never>()

    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.chronod/chronod/remoteArchives")
    private var stream: FSEventStreamRef?
    private var loaded: (path: String, modified: Date)?
    private var retry: DispatchWorkItem?
    private var lastPayloadID: String?

    func start() {
        reload()

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let store = Unmanaged<ActivityStore>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { store.reload() }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags
        ) else {
            NSLog("NotchLive: could not watch %@", root.path)
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func newestArchive() -> (url: URL, modified: Date)? {
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        var newest: (url: URL, modified: Date)?
        for case let url as URL in files where url.pathExtension == "activity-archive" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            if newest == nil || modified > newest!.modified { newest = (url, modified) }
        }
        return newest
    }

    private func reload() {
        retry?.cancel()
        guard let newest = newestArchive() else {
            loaded = nil
            if current != nil { current = nil }
            return
        }
        if let loaded, loaded.path == newest.url.path, loaded.modified == newest.modified { return }

        do {
            let data = try Data(contentsOf: newest.url)
            let activity = try ArchiveDecoding.decode(data)
            let isFirstLoad = loaded == nil
            current = activity
            loaded = (newest.url.path, newest.modified)
            if let activity, activity.payloadID != lastPayloadID {
                lastPayloadID = activity.payloadID
                if activity.isAlerting, !isFirstLoad { alerts.send() }
            }
        } catch {
            // The file may be caught mid-write; keep showing the last good state and try again.
            NSLog("NotchLive: decode failed, retrying: %@", String(describing: error).prefix(200) as CVarArg)
            let work = DispatchWorkItem { [weak self] in self?.reload() }
            retry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
}
