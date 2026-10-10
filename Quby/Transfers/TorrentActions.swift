import SwiftUI

extension View {
    func torrentDetailActions(store: TransferStore, torrent: Torrent) -> some View {
        modifier(TorrentDetailActions(store: store, torrent: torrent))
    }
}

private struct TorrentDetailActions: ViewModifier {
    let store: TransferStore
    let torrent: Torrent
    @State private var actions = TorrentActionController()

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TorrentDetailActionMenu(
                        enabled: store.canControl && !actions.running
                            && store.torrents.contains(where: { $0.id == torrent.id }),
                        running: actions.running
                    ) {
                        let current = store.torrents.first { $0.id == torrent.id } ?? torrent
                        actions.choose($0, torrents: [current], store: store)
                    }.equatable()
                }
            }
            .modifier(TorrentActionPresentation(store: store, actions: actions))
    }
}

private struct TorrentDetailActionMenu: View, Equatable {
    let enabled: Bool
    let running: Bool
    let onAction: (TorrentAction) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.enabled == rhs.enabled && lhs.running == rhs.running }

    var body: some View {
        Menu {
            TorrentActionButtons(enabled: enabled, onAction: onAction)
        } label: {
            if running { ProgressView().controlSize(.small) } else { Image(systemName: "ellipsis") }
        }
        .accessibilityLabel("Torrent actions")
    }
}

struct TorrentActionButtons: View {
    let enabled: Bool
    let onAction: (TorrentAction) -> Void
    var body: some View {
        ForEach(TorrentAction.allCases) { action in
            Button(
                action.rawValue, systemImage: action.symbol,
                role: action == .delete || action == .purge ? .destructive : nil
            ) { onAction(action) }.disabled(!enabled)
        }
    }
}

struct TorrentActionPresentation: ViewModifier {
    let store: TransferStore
    @Bindable var actions: TorrentActionController

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.editor) { request in
                TorrentEditView(store: store, request: request, actions: actions)
            }
            .confirmationDialog(
                "\(actions.removal?.action.rawValue ?? "Remove") \(actions.removal?.torrents.count ?? 0) \(actions.removal?.torrents.count == 1 ? "torrent" : "torrents")?",
                isPresented: Binding(
                    get: { actions.removal != nil }, set: { if !$0 { actions.removal = nil } }),
                titleVisibility: .visible, presenting: actions.removal
            ) { request in
                Button(
                    request.action == .purge ? "Purge torrents and files" : "Delete torrents",
                    role: .destructive
                ) {
                    Task {
                        await actions.submit(
                            .delete(deleteFiles: request.action == .purge), request: request, store: store)
                    }
                }
                .disabled(!store.canControl || actions.running)
                Button("Cancel", role: .cancel) {}
            } message: { request in
                let names = request.torrents.prefix(3).map(\.name).joined(separator: ", ")
                Text(
                    "\(names)\(request.torrents.count > 3 ? " and \(request.torrents.count - 3) more" : ""). \(request.action == .purge ? "Downloaded files will also be permanently deleted." : "Downloaded files will be kept.")"
                )
            }
            .alert(
                "Request failed",
                isPresented: Binding(
                    get: { actions.failure != nil && actions.editor == nil },
                    set: { if !$0 { actions.failure = nil } }
                )
            ) {
                Button("OK") { actions.failure = nil }
            } message: {
                Text(actions.failure ?? "Please try again.")
            }
            .overlay(alignment: .bottom) {
                if let feedback = actions.feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .padding(14)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 72)
                        .allowsHitTesting(false)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .task(id: actions.feedback) {
                guard actions.feedback != nil else { return }
                do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
                actions.feedback = nil
                actions.failure = nil
            }
            .onChange(of: store.activeInstanceID) { _, _ in
                actions.editor = nil
                actions.removal = nil
                actions.feedback = nil
            }
    }
}
