import AppKit
import CShim
import SwiftUI
import WidgetKit

/// One Live Activity received from the iPhone, decoded into ready-to-show views.
struct LiveActivity {
    struct Piece {
        let view: AnyView
        let size: CGSize
    }

    let payloadID: String
    /// True when the iPhone app sent this update as an alert (a goal, an arrival…),
    /// the same signal that makes the Dynamic Island expand on the iPhone.
    let isAlerting: Bool
    let compactLeading: Piece?
    let compactTrailing: Piece?
    let expanded: Piece?
}

enum ArchiveDecoding {
    private static var decodersRegistered = false

    /// Decodes an `.activity-archive` file's contents with the system's own decoder.
    @MainActor
    static func decode(_ data: Data) throws -> LiveActivity? {
        registerDecodersIfNeeded()
        let collection = try ActivityArchivedViewCollection(contentsOf: data)

        // The archive holds one rendering per environment variant (light/dark,
        // always-on dimming, redaction). Pick the normal dark one: it is the
        // variant designed for the black Dynamic Island.
        var chosen: EnvironmentValues?
        var index = 0
        while index < 64, let candidate = collection.environment.environmentValues(at: index) {
            if candidate.colorScheme == .dark, !candidate.isLuminanceReduced, candidate.redactionReasons.isEmpty {
                chosen = candidate
                break
            }
            index += 1
        }
        guard let environment = chosen ?? collection.environment.environmentValues(at: 0) else { return nil }

        var pieces: [String: LiveActivity.Piece] = [:]
        for tag in collection.viewTags {
            guard let entry = try collection.viewEntry(for: tag, in: environment, ignoring: []) else { continue }
            let view = AnyView(entry.view.fixedSize().environment(\.colorScheme, .dark))
            pieces[tag.description] = .init(view: view, size: NSHostingView(rootView: view).fittingSize)
        }
        return LiveActivity(
            payloadID: collection.payloadID,
            isAlerting: collection.isAlerting,
            compactLeading: pieces["dynamicIsland-compactLeading"],
            compactTrailing: pieces["dynamicIsland-compactTrailing"],
            expanded: pieces["dynamicIsland-expanded"] ?? pieces["listItem"]
        )
    }

    // MARK: - Decoder registration

    /// SwiftUI's archive decoder only knows view types that were registered with it.
    /// The system widget renderer registers WidgetKit's types before decoding; without
    /// this step decoding fails with `missingView("WidgetKit.WidgetURLModifier")`.
    private static func registerDecodersIfNeeded() {
        guard !decodersRegistered else { return }
        decodersRegistered = true

        let groups: [(proto: String, register: String, typeAccessors: [String])] = [
            (
                "$s7SwiftUI23_ArchivableViewModifierMp",
                "$s7SwiftUI23_ArchivableViewModifierPAAE15registerDecoderyyFZ",
                [
                    "$s9WidgetKit0A11URLModifierVMa",
                    "$s9WidgetKit0A15ContentLayerTagVMa",
                    "$s9WidgetKit0A31AccentedDesaturatedViewModifierVMa",
                    "$s9WidgetKit24_ClockHandRotationEffectVMa",
                    "$s9WidgetKit25HideViewInCarPlayModifierVMa",
                    "$s9WidgetKit26HideViewOnSnapshotModifierVMa",
                    "$s9WidgetKit28RevealViewOnSnapshotModifierVMa",
                ]
            ),
            (
                "$s7SwiftUI15_ArchivableViewMp",
                "$s7SwiftUI15_ArchivableViewPAAE15registerDecoderyyFZ",
                ["$s9WidgetKit21AnimatingWaveformViewVMa"]
            ),
        ]

        typealias MetadataAccessor = @convention(c) (Int) -> UnsafeRawPointer
        typealias ConformsToProtocol = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?
        let handle = dlopen(nil, RTLD_NOW)
        guard let conformsSymbol = dlsym(handle, "swift_conformsToProtocol") else { return }
        let conformsToProtocol = unsafeBitCast(conformsSymbol, to: ConformsToProtocol.self)
        for group in groups {
            guard let proto = dlsym(handle, group.proto), let register = dlsym(handle, group.register) else {
                NSLog("NotchLive: decoder registration symbols missing for %@", group.proto)
                continue
            }
            for name in group.typeAccessors {
                guard let accessor = dlsym(handle, name) else {
                    NSLog("NotchLive: type not found: %@", name)
                    continue
                }
                let metadata = unsafeBitCast(accessor, to: MetadataAccessor.self)(0)
                guard let witnessTable = conformsToProtocol(metadata, proto) else { continue }
                la_call_static_on_type(register, metadata, witnessTable)
            }
        }
    }
}
