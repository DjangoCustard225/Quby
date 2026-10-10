import SwiftUI
import UIKit

struct SearchResultRows: View {
    let store: TransferStore
    let session: TorrentSearchSession
    let matches: [Torrent]
    let configuration: SearchConfiguration
    let scope: SearchScope?
    var body: some View {
        HStack {
            Text(configuration.status?.rawValue ?? "Results")
            Spacer()
            Text(matches.count, format: .number).monospacedDigit()
            SearchOptionsMenu(configuration: configuration) { session.update($0, scope: scope) }
                .equatable()
        }
        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        .padding(.top, 8)
        if matches.isEmpty {
            ContentUnavailableView {
                Label(
                    configuration.hasSearch ? "No matches" : "No torrents", systemImage: "magnifyingglass")
            } description: {
                Text(
                    configuration.hasSearch
                        ? "Try another search or clear the filters."
                        : "There are no torrents in this \(scope?.kind.lowercased() ?? "server").")
            } actions: {
                if configuration.hasSearch {
                    Button("Clear search and filters") {
                        var next = configuration
                        next.query = ""
                        next.status = nil
                        session.update(next, scope: scope)
                    }
                }
            }.searchEmptyRow()
        } else {
            TorrentRows(store: store, torrents: matches) { torrent in
                session.openTorrent(torrent)
                dismissSearchKeyboard()
            }
        }
    }
}

struct SearchInstanceRow: View {
    let store: TransferStore
    var scope: SearchScope?
    var body: some View {
        if let instance = store.activeInstance {
            HStack(spacing: 8) {
                Label(instance.name, systemImage: "server.rack")
                Spacer(minLength: 8)
                Text(scope?.kind ?? "\(store.torrents.count) torrents")
            }
            .font(.subheadline).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
    }
}

struct SearchConnectionNotice: View {
    let store: TransferStore
    @Binding var selectedTab: AppTab
    var body: some View {
        if store.activeInstance != nil && !store.online {
            HStack(alignment: .top, spacing: 12) {
                if store.connecting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        store.connecting
                            ? "Connecting…"
                            : store.lastUpdated != nil ? "Showing last known results" : "Server unavailable"
                    )
                    .fontWeight(.semibold)
                    Text(
                        store.lastUpdated != nil
                            ? "Results may be out of date. Connect again to refresh."
                            : "Check your connection or sign in through Settings."
                    )
                    .foregroundStyle(.secondary)
                    if let updated = store.lastUpdated {
                        Text("Updated \(Text(updated, style: .relative)) ago")
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                Button(
                    store.connected || store.activeInstanceID.map(store.hasSavedLogin) == true
                        ? "Retry" : "Settings"
                ) {
                    Task { await retryServerConnection(store, selectedTab: $selectedTab) }
                }
                .disabled(store.connecting)
            }
            .font(.footnote)
            .padding(12)
            .background(AppTheme.formRowBackground, in: RoundedRectangle(cornerRadius: 16))
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
    }
}

struct SearchLoadingRow: View {
    var body: some View {
        ProgressView("Searching…")
            .frame(maxWidth: .infinity, minHeight: 100)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}

struct SearchOptionsMenu: View, Equatable {
    let configuration: SearchConfiguration
    let onChange: (SearchConfiguration) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.configuration == rhs.configuration }
    var body: some View {
        Menu {
            Menu("Status", systemImage: "circle.dotted") {
                Picker(
                    "Status",
                    selection: Binding(
                        get: { configuration.status },
                        set: { value in
                            var next = configuration
                            next.status = value
                            onChange(next)
                        })
                ) {
                    Text("All statuses").tag(nil as TransferState?)
                    ForEach(TransferState.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
            }
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker(
                    "Sort",
                    selection: Binding(
                        get: { configuration.sort },
                        set: { value in
                            var next = configuration
                            next.sort = value
                            onChange(next)
                        })
                ) {
                    ForEach(SearchResultSort.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            if configuration.status != nil || configuration.sort != .relevance {
                Button("Reset filters", systemImage: "xmark.circle") {
                    var next = configuration
                    next.status = nil
                    next.sort = .relevance
                    onChange(next)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(configuration.status != nil || configuration.sort != .relevance ? .blue : .primary)
        .accessibilityLabel("Filter and sort results")
        .accessibilityValue(
            "\(configuration.status?.rawValue ?? "All statuses"), sorted by \(configuration.sort.rawValue.lowercased())"
        )
    }
}

struct BrowseSortMenu: View, Equatable {
    let sort: SearchBrowseSort
    let onChange: (SearchBrowseSort) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.sort == rhs.sort }
    var body: some View {
        Menu {
            Picker("Sort", selection: Binding(get: { sort }, set: onChange)) {
                ForEach(SearchBrowseSort.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort by \(sort.rawValue.lowercased())")
    }
}

@MainActor func dismissSearchKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    func searchEmptyRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 180)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
    func searchListStyle() -> some View {
        modifier(SearchListStyle())
    }
}

private struct SearchListStyle: ViewModifier {
    @Environment(\.isSearching) private var isSearching

    func body(content: Content) -> some View {
        content.listStyle(.plain)
            .minimizeNavigationBarOnScroll(enabled: !isSearching)
            .scrollContentBackground(.hidden).softScrollEdges()
            .scrollDismissesKeyboard(.interactively)
            .listRowSeparatorTint(AppTheme.border)
            .background(AppTheme.background.ignoresSafeArea())
    }
}
