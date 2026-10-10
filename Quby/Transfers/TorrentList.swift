import SwiftUI
import UIKit

private struct TorrentScrollEffectsEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct TorrentScrollAtTopKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    fileprivate var torrentScrollEffectsEnabled: Bool {
        get { self[TorrentScrollEffectsEnabledKey.self] }
        set { self[TorrentScrollEffectsEnabledKey.self] = newValue }
    }
    fileprivate var torrentScrollAtTop: Bool {
        get { self[TorrentScrollAtTopKey.self] }
        set { self[TorrentScrollAtTopKey.self] = newValue }
    }
}

struct TorrentScrollView<Content: View>: View {
    private let content: Content
    private let onRefresh: (@MainActor @Sendable () async -> Void)?
    @Environment(\.isSearching) private var isSearching
    @State private var hasStartedScrolling = false
    @State private var isAnimatingScroll = false
    @State private var isUserScrolling = false
    @State private var isAtTop = true
    @State private var isRefreshing = false

    init(onRefresh: (@MainActor @Sendable () async -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onRefresh = onRefresh
        self.content = content()
    }

    var body: some View {
        scrollView
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                isAtTop = atTop
                if !atTop, isUserScrolling { hasStartedScrolling = true }
            }
            .onScrollPhaseChange { _, phase in
                let animating = phase == .animating
                let userScrolling = phase == .interacting || phase == .decelerating
                let mayStartEffects = onRefresh == nil || !isAtTop
                let started =
                    !animating && (hasStartedScrolling || (mayStartEffects && userScrolling))
                guard
                    hasStartedScrolling != started || isAnimatingScroll != animating
                        || isUserScrolling != userScrolling
                else { return }
                hasStartedScrolling = started
                isAnimatingScroll = animating
                isUserScrolling = userScrolling
            }
            .contentMargins(.bottom, 48, for: .scrollContent)
            .softScrollEdges()
            .minimizeNavigationBarOnScroll(enabled: !isSearching)
            .background(AppTheme.background.ignoresSafeArea())
    }

    @ViewBuilder private var scrollView: some View {
        if let onRefresh {
            nativeScrollView.refreshable {
                isRefreshing = true
                defer { isRefreshing = false }
                await onRefresh()
            }
        } else {
            nativeScrollView
        }
    }

    private var nativeScrollView: some View {
        let refreshingAtTop = onRefresh != nil && (isRefreshing || isAtTop)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) { content }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .environment(
                    \.torrentScrollEffectsEnabled,
                    hasStartedScrolling && !isAnimatingScroll && !refreshingAtTop
                )
                .environment(\.torrentScrollAtTop, isAtTop)
        }
    }
}

struct TorrentRows: View {
    let store: TransferStore
    let torrents: [Torrent]
    let onOpen: (Torrent) -> Void
    @Environment(\.torrentSelectionContext) private var selectionContext
    var body: some View {
        ForEach(torrents) { torrent in
            TorrentRow(
                torrent: torrent,
                open: {
                    if let context = selectionContext, context.selection.isSelecting {
                        context.toggle(torrent.id)
                    } else {
                        onOpen(torrent)
                    }
                },
                toggle: { Task { await store.toggle(torrent.id) } }, canControl: store.canControl,
                isFresh: store.hasFreshData, isToggling: store.pendingToggles.contains(torrent.id),
                isSelecting: selectionContext?.selection.isSelecting ?? false,
                isSelected: selectionContext?.selection.ids.contains(torrent.id) ?? false
            )
            .equatable()
            .selectableTorrent(torrent)
            .modifier(TorrentCardScrollEffect())
        }
    }
}

private struct TorrentCardScrollEffect: ViewModifier {
    @AppStorage("torrentScrollIntensity") private var intensity = TorrentScrollIntensity.full
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.torrentScrollEffectsEnabled) private var effectsEnabled
    @Environment(\.torrentScrollAtTop) private var isAtTop

    func body(content: Content) -> some View {
        let active = effectsEnabled && !reduceMotion && intensity != .off
        let atTop = isAtTop
        let opacity = intensity == .subtle ? 0.88 : 0.65
        let scale = intensity == .subtle ? 0.98 : 0.92
        return content.scrollTransition(
            // Keep the transition graph stable while the system jumps across lazy rows.
            // Disabling effects changes their values rather than replacing configurations.
            topLeading: .interactive.threshold(.visible.inset(by: 70)),
            bottomTrailing: .interactive.threshold(.visible.inset(by: 70)),
            axis: .vertical
        ) { effect, phase in
            let applyEffect = active && !phase.isIdentity && !(atTop && phase == .topLeading)
            return
                effect
                .opacity(applyEffect ? opacity : 1)
                .scaleEffect(applyEffect ? scale : 1)
        }
    }
}

private struct TorrentRow: View, Equatable {
    @AppStorage("torrentDensity") private var density = TorrentDensity.comfortable
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let torrent: Torrent
    let open: () -> Void
    let toggle: () -> Void
    let canControl: Bool
    let isFresh: Bool
    let isToggling: Bool
    let isSelecting: Bool
    let isSelected: Bool
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.torrent == rhs.torrent && lhs.canControl == rhs.canControl && lhs.isFresh == rhs.isFresh
            && lhs.isToggling == rhs.isToggling && lhs.dynamicTypeSize == rhs.dynamicTypeSize
            && lhs.isSelecting == rhs.isSelecting && lhs.isSelected == rhs.isSelected
            && lhs.density == rhs.density
    }
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: density == .compact ? 4 : 6) {
                    Text(torrent.name)
                        .font(
                            density == .compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold)
                        )
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .multilineTextAlignment(.leading)
                    Text(torrent.category + " · " + torrent.size)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    ViewThatFits(in: .horizontal) {
                        statusLine
                        VStack(alignment: .leading, spacing: 3) {
                            statusLabel
                            speedLabel
                        }
                    }
                    if torrent.progress < 1 {
                        ProgressView(value: torrent.progress).tint(torrent.state.color)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(
                    "\(torrent.name), \(torrent.state.rawValue), \(Int(torrent.progress * 100)) percent, \(torrent.size)"
                )
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(
                    isSelecting ? "Tap to change selection" : "Opens details. Long press to select.")
            if isSelecting {
                Button(action: open) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(isSelected ? Color.blue : AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isSelected ? "Deselect" : "Select") \(torrent.name)")
            } else {
                TorrentControlButton(
                    name: torrent.name, isPaused: torrent.state == .paused,
                    canControl: canControl, isPending: isToggling, action: toggle)
            }
        }
        .padding(.vertical, density == .compact && !dynamicTypeSize.isAccessibilitySize ? 10 : 16)
        .padding(.horizontal, 12)
        .darkCard(cornerRadius: 22)
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 22).strokeBorder(.blue, lineWidth: 2) }
        }
    }
    private var statusLabel: some View {
        HStack(spacing: 6) {
            Text(torrent.state.rawValue)
                .foregroundStyle(torrent.state.color)
            Text("·")
            Text(torrent.trackerLabel)
                .lineLimit(1)
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.secondaryText)
    }
    private var speedLabel: some View {
        Text(
            torrent.progress < 1
                ? "\(Int(torrent.progress * 100))% · \(isFresh ? torrent.speed : "—")"
                : isFresh ? torrent.speed : "—"
        )
        .font(.subheadline).foregroundStyle(AppTheme.secondaryText).monospacedDigit()
    }
    private var statusLine: some View {
        HStack(spacing: 6) {
            statusLabel
            Spacer(minLength: 4)
            speedLabel
        }
    }
}

private struct TorrentControlButton: View {
    let name: String
    let isPaused: Bool
    let canControl: Bool
    let isPending: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsProgress = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .opacity(showsProgress ? 0 : 1)
                if showsProgress {
                    ProgressView().controlSize(.mini).tint(AppTheme.primaryText)
                        .transition(.opacity)
                }
            }
            .frame(width: 20, height: 20)
            .foregroundStyle(canControl ? AppTheme.primaryText : Color.secondary)
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isPaused)
            .animation(.easeInOut(duration: 0.16), value: showsProgress)
        }
        .buttonStyle(TorrentControlStyle())
        .disabled(!canControl || isPending)
        .accessibilityLabel("\(isPaused ? "Resume" : "Pause") \(name)")
        .accessibilityValue(isPending ? "In progress" : "")
        .task(id: isPending) {
            showsProgress = false
            guard isPending else { return }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard !Task.isCancelled else { return }
            showsProgress = true
        }
    }
}

private struct TorrentControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .frame(width: 36, height: 36)
            .background(AppTheme.primaryText.opacity(pressed ? 0.22 : 0.14), in: Circle())
            .overlay {
                Circle().strokeBorder(AppTheme.primaryText.opacity(pressed ? 0.20 : 0.08), lineWidth: 0.5)
            }
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: pressed
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
