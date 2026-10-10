import SwiftUI
import UIKit

struct CardSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.headline).foregroundStyle(AppTheme.primaryText).padding(.horizontal, 2)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var monospacedDigits = false

    init(_ title: String, value: String, symbol: String, monospacedDigits: Bool = false) {
        self.title = title
        self.value = value
        self.symbol = symbol
        self.monospacedDigits = monospacedDigits
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Group {
                if monospacedDigits { Text(value).monospacedDigit() } else { Text(value) }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(16)
        .darkCard(cornerRadius: 18)
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var copyable = false

    init(_ title: String, _ value: String, copyable: Bool = false) {
        self.title = title
        self.value = value
        self.copyable = copyable
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title).foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 12)
            Group {
                if copyable {
                    Text(value).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .foregroundStyle(AppTheme.primaryText).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 15)
        .contextMenu {
            if copyable {
                Button("Copy \(title.lowercased())", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = value
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
