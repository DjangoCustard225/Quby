import SwiftUI

struct AddTorrentMenu: View, Equatable {
    let canControl: Bool
    let onMagnet: () -> Void
    let onFile: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.canControl == rhs.canControl
    }

    var body: some View {
        Menu {
            Button("Enter magnet link", systemImage: "link", action: onMagnet)
            Button("Select .torrent file", systemImage: "doc.badge.plus", action: onFile)
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .disabled(!canControl)
        .accessibilityLabel("Add torrent")
    }
}

struct TransferFilterMenu: View, Equatable {
    let sortOrder: TorrentSort
    let statusValue: TransferState?
    let categoryValue: String?
    let trackerValue: String?
    @Binding var statusFilter: TransferState?
    @Binding var categoryFilter: String?
    @Binding var trackerFilter: String?
    let categories: [String]
    let trackers: [String]
    let onSort: (TorrentSort) -> Void
    private var hasFilters: Bool { statusValue != nil || categoryValue != nil || trackerValue != nil }
    private var hasActiveOptions: Bool { hasFilters || sortOrder != .dateAdded }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder == rhs.sortOrder && lhs.statusValue == rhs.statusValue
            && lhs.categoryValue == rhs.categoryValue && lhs.trackerValue == rhs.trackerValue
            && lhs.categories == rhs.categories && lhs.trackers == rhs.trackers
    }
    var body: some View {
        Menu {
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort", selection: Binding(get: { sortOrder }, set: onSort)) {
                    ForEach(TorrentSort.allCases) { option in Text(option.rawValue).tag(option) }
                }
            }
            Menu("Status", systemImage: "circle.dotted") {
                Picker("Status", selection: $statusFilter) {
                    Text("All statuses").tag(nil as TransferState?)
                    ForEach(TransferState.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(Optional(status))
                    }
                }
            }
            Menu("Category", systemImage: "folder") {
                Picker("Category", selection: $categoryFilter) {
                    Text("All categories").tag(nil as String?)
                    ForEach(categories, id: \.self) { category in Text(category).tag(Optional(category)) }
                }
            }
            Menu("Tracker", systemImage: "antenna.radiowaves.left.and.right") {
                Picker("Tracker", selection: $trackerFilter) {
                    Text("All trackers").tag(nil as String?)
                    ForEach(trackers, id: \.self) { tracker in Text(tracker).tag(Optional(tracker)) }
                }
            }
            if hasFilters {
                Divider()
                Button("Clear filters", systemImage: "xmark.circle") {
                    statusFilter = nil
                    categoryFilter = nil
                    trackerFilter = nil
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.body.weight(.semibold))
                .foregroundStyle(hasActiveOptions ? Color.blue : Color.white)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if hasActiveOptions {
                        Circle().fill(Color.blue).frame(width: 8, height: 8).padding(5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filters")
        .accessibilityValue(hasActiveOptions ? "Options active" : "No options selected")
    }
}
