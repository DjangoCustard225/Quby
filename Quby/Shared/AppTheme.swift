import SwiftUI

enum AppTheme {
    static let background = Color.black
    static let cardBackground = Color(white: 0.08)
    static let formRowBackground = Color(white: 0.11)
    static let secondaryText = Color.white.opacity(0.72)
    static let border = Color.white.opacity(0.22)
}

extension TransferState {
    var color: Color {
        switch self {
        case .seeding: .green
        case .downloading: .cyan
        case .paused, .queued, .stalled: .orange
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
