import SwiftUI

struct SpeedSummary: View {
    let store: TransferStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    rate("Download", symbol: "arrow.down", bytes: store.info.downloadSpeed, color: .blue)
                    rate("Upload", symbol: "arrow.up", bytes: store.info.uploadSpeed, color: .green)
                }
            } else {
                HStack(spacing: 10) {
                    rate("Download", symbol: "arrow.down", bytes: store.info.downloadSpeed, color: .blue)
                    rate("Upload", symbol: "arrow.up", bytes: store.info.uploadSpeed, color: .green)
                }
            }
        }
    }
    private func rate(_ title: String, symbol: String, bytes: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text(store.hasFreshData ? Torrent.bytes(bytes) + "/s" : "—")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(16)
        .darkCard(cornerRadius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) speed")
        .accessibilityValue(store.hasFreshData ? "\(Torrent.bytes(bytes)) per second" : "Unavailable")
    }
}
