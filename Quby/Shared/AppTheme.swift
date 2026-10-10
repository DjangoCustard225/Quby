import SwiftUI

enum AppTheme {
    static let background = adaptive(light: .systemGroupedBackground, dark: .black)
    static let cardBackground = adaptive(light: .white, dark: UIColor(white: 0.08, alpha: 1))
    static let formRowBackground = adaptive(light: .white, dark: UIColor(white: 0.11, alpha: 1))
    static let primaryText = Color.primary
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let border = adaptive(
        light: UIColor.black.withAlphaComponent(0.14), dark: UIColor.white.withAlphaComponent(0.22))

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum TorrentDensity: String, CaseIterable, Identifiable {
    case comfortable = "Comfortable"
    case compact = "Compact"
    var id: Self { self }
}

enum TorrentScrollIntensity: String, CaseIterable, Identifiable {
    case off = "Off"
    case subtle = "Subtle"
    case full = "Full"
    var id: Self { self }
}

extension TransferState {
    var color: Color {
        switch self {
        case .seeding:
            AppTheme.adaptive(
                light: UIColor(red: 0.05, green: 0.48, blue: 0.24, alpha: 1), dark: .systemGreen)
        case .downloading:
            AppTheme.adaptive(light: UIColor(red: 0, green: 0.39, blue: 0.65, alpha: 1), dark: .systemCyan)
        case .paused, .queued, .stalled:
            AppTheme.adaptive(light: UIColor(red: 0.62, green: 0.32, blue: 0, alpha: 1), dark: .systemOrange)
        case .checking: .blue
        case .error: .red
        case .unknown: .secondary
        }
    }
}

extension View {
    func darkCard(cornerRadius: CGFloat) -> some View {
        background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
    }

    func softScrollEdges() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
    }

    func appListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .softScrollEdges()
    }

    @ViewBuilder
    func minimizeNavigationBarOnScroll(enabled: Bool = true) -> some View {
        if #available(iOS 27.0, *) {
            modifier(ScrollNavigationBar(enabled: enabled))
        } else {
            self
        }
    }
}

@available(iOS 27.0, *)
private struct ScrollNavigationBar: ViewModifier {
    let enabled: Bool
    @State private var isAtTop = true

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                isAtTop = atTop
            }
            // Keep the bar expanded through overscroll and native refresh retraction.
            .toolbarMinimizationBehavior(enabled && !isAtTop ? .onScrollDown : .never, for: .navigationBar)
            .toolbarMinimizationRestoration(.atScrollEdge, for: .navigationBar)
            // Keep the scroll viewport fixed as the bar collapses and restores.
            // Status-bar scroll-to-top must not also change the target's content inset.
            .toolbarMinimizationSafeAreaAdjustment(.disabled, for: .navigationBar)
    }
}
