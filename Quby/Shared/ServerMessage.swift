import SwiftUI

struct ServerMessage: View {
    let store: TransferStore
    var body: some View {
        if let message = store.connectionIssue {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.connected ? "Reconnecting…" : "Connection lost")
                        .fontWeight(.semibold)
                    Text(store.connected ? message : "Open Settings to connect again.")
                        .fixedSize(horizontal: false, vertical: true)
                    if let updated = store.lastUpdated {
                        HStack(spacing: 3) {
                            Text("Last updated")
                            Text(updated, style: .relative)
                        }.foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 4)
                if store.connected {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry connection")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14)
            )
            .accessibilityElement(children: .contain)
        }
    }
}

@MainActor func retryServerConnection(_ store: TransferStore, selectedTab: Binding<AppTab>) async {
    if store.connected {
        await store.refresh()
    } else if let id = store.activeInstanceID, store.hasSavedLogin(for: id) {
        await store.reconnectActive()
    } else {
        selectedTab.wrappedValue = .settings
    }
}
