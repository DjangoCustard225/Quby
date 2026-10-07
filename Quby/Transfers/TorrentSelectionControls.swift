import SwiftUI
import UIKit

struct TorrentSelectionContext {
    let selection: TorrentSelection
    let begin: (String) -> Void
    let toggle: (String) -> Void
}

private struct TorrentSelectionContextKey: EnvironmentKey {
    static let defaultValue: TorrentSelectionContext? = nil
}

extension EnvironmentValues {
    var torrentSelectionContext: TorrentSelectionContext? {
        get { self[TorrentSelectionContextKey.self] }
        set { self[TorrentSelectionContextKey.self] = newValue }
    }
}

extension View {
    func torrentSelection(store: TransferStore, visibleTorrents: [Torrent]) -> some View {
        modifier(TorrentSelectionControls(store: store, visibleTorrents: visibleTorrents))
    }

    func selectableTorrent(_ torrent: Torrent) -> some View {
        modifier(SelectableTorrent(torrent: torrent))
    }
}

private struct SelectableTorrent: ViewModifier {
    let torrent: Torrent
    @Environment(\.torrentSelectionContext) private var context

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    guard let context else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    context.begin(torrent.id)
                }, including: context.map { _ in GestureMask.all } ?? .none
            )
            .accessibilityAction(named: Text("Select torrent")) { context?.begin(torrent.id) }
    }
}

// The selection context lives above the rows, so offscreen rows participate too.
private struct TorrentSelectionControls: ViewModifier {
    let store: TransferStore
    let visibleTorrents: [Torrent]
    @State private var selection = TorrentSelection()
    @State private var actions = TorrentActionController()

    private var selectedTorrents: [Torrent] { store.torrents.filter { selection.ids.contains($0.id) } }

    func body(content: Content) -> some View {
        content
            .environment(
                \.torrentSelectionContext,
                TorrentSelectionContext(
                    selection: selection,
                    begin: { id in
                        guard store.torrents.contains(where: { $0.id == id }) else { return }
                        selection.begin(id)
                    }, toggle: { selection.toggle($0) })
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selection.isSelecting {
                    HStack(spacing: 16) {
                        Button("Done") { selection.clear() }
                        Spacer(minLength: 0)
                        Text("\(selection.ids.count) selected").font(.subheadline.weight(.medium))
                            .monospacedDigit()
                        if actions.running { ProgressView().controlSize(.small) }
                        TorrentSelectionMenu(
                            enabled: store.canControl && !actions.running && !selection.ids.isEmpty,
                            selectedIDs: selection.ids, visibleIDs: Set(visibleTorrents.map(\.id)),
                            onSelectAll: { selection.selectAll(Set(visibleTorrents.map(\.id))) },
                            onDeselectAll: { selection.deselectAll() },
                            onAction: { actions.choose($0, torrents: selectedTorrents, store: store) }
                        ).equatable()
                    }
                    .padding(.leading, 18).padding(.trailing, 6)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, 18).padding(.bottom, 8)
                }
            }
            .modifier(TorrentActionPresentation(store: store, actions: actions))
            .onChange(of: store.torrents.map(\.id)) { _, ids in
                selection.retainAvailable(Set(ids))
            }
            .onChange(of: store.activeInstanceID) { _, _ in selection.clear() }
            .onDisappear { selection.clear() }
    }
}

private struct TorrentSelectionMenu: View, Equatable {
    let enabled: Bool
    let selectedIDs: Set<String>
    let visibleIDs: Set<String>
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onAction: (TorrentAction) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled && lhs.selectedIDs == rhs.selectedIDs && lhs.visibleIDs == rhs.visibleIDs
    }

    var body: some View {
        Menu {
            Button("Select all shown", systemImage: "checkmark.circle", action: onSelectAll)
            Button("Deselect all", systemImage: "circle", action: onDeselectAll)
            Divider()
            TorrentActionButtons(enabled: enabled, onAction: onAction)
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Actions for selected torrents")
    }
}
