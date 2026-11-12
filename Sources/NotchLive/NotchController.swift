import Combine
import DynamicNotchKit
import SwiftUI

/// Shows one slot of the current activity, scaled down to fit a maximum height.
struct ActivitySlot: View {
    @ObservedObject var store: ActivityStore
    let piece: KeyPath<LiveActivity, LiveActivity.Piece?>
    var maxHeight: CGFloat?

    var body: some View {
        if let piece = store.current?[keyPath: piece], piece.size.width > 0, piece.size.height > 0 {
            let scale = maxHeight.map { min(1, $0 / piece.size.height) } ?? 1
            piece.view
                .scaleEffect(scale)
                .frame(width: piece.size.width * scale, height: piece.size.height * scale)
        }
    }
}

/// The expanded card, with a deliberately faint quit button in its corner.
struct ExpandedCard: View {
    @ObservedObject var store: ActivityStore

    var body: some View {
        ActivitySlot(store: store, piece: \.expanded)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("NotchLive'ı kapat")
                .offset(x: 6, y: 6)
            }
    }
}

/// Drives the notch: hidden with no activity, compact beside the camera while one
/// is running, expanded below the notch while the pointer is over it.
@MainActor
final class NotchController {
    private let store: ActivityStore
    private let notch: DynamicNotch<ExpandedCard, ActivitySlot, ActivitySlot>
    private var subscriptions: Set<AnyCancellable> = []
    private var isSyncing = false

    private enum Target { case hidden, compact, expanded }
    private var shown: Target = .hidden
    /// While set and in the future, the card stays open without hovering (after an alert).
    private var alertOpenUntil: Date?
    private static let alertDuration: TimeInterval = 6

    init(store: ActivityStore) {
        self.store = store
        let compactHeight = (NSScreen.screens.first?.safeAreaInsets.top ?? 32) - 6
        notch = DynamicNotch(hoverBehavior: [.keepVisible]) {
            ExpandedCard(store: store)
        } compactLeading: {
            ActivitySlot(store: store, piece: \.compactLeading, maxHeight: compactHeight)
        } compactTrailing: {
            ActivitySlot(store: store, piece: \.compactTrailing, maxHeight: compactHeight)
        }
        notch.transitionConfiguration.skipIntermediateHides = true

        store.$current
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &subscriptions)
        store.alerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.openForAlert() }
            .store(in: &subscriptions)
        notch.$isHovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &subscriptions)
    }

    private var target: Target {
        guard store.current != nil else { return .hidden }
        if let alertOpenUntil, alertOpenUntil > Date() { return .expanded }
        return notch.isHovering ? .expanded : .compact
    }

    private func openForAlert() {
        alertOpenUntil = Date().addingTimeInterval(Self.alertDuration)
        sync()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.alertDuration + 0.1) { [weak self] in self?.sync() }
    }

    /// Moves the notch to the wanted state, one transition at a time, re-checking
    /// afterwards because the wanted state can change while an animation runs.
    private func sync() {
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            while shown != target {
                let next = target
                switch next {
                case .hidden: await notch.hide()
                case .compact: await notch.compact()
                case .expanded: await notch.expand()
                }
                shown = next
            }
            isSyncing = false
        }
    }
}
