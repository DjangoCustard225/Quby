import SwiftUI

struct SpeedLimitsView: View {
    let store: TransferStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SpeedLimitDraft?
    @State private var loading = false
    @State private var saving = false
    @State private var failure: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                if let instance = store.activeInstance {
                    Label(instance.name, systemImage: "server.rack")
                }
                AlternativeSpeedToggle(store: store)
            }
            .listRowBackground(AppTheme.formRowBackground)
            if draft != nil {
                Section {
                    SpeedLimitPicker(title: "Download", value: field(\.download))
                    SpeedLimitPicker(title: "Upload", value: field(\.upload))
                }
                .listRowBackground(AppTheme.formRowBackground)
                Section {
                    SpeedLimitPicker(title: "Download", value: field(\.alternativeDownload))
                    SpeedLimitPicker(title: "Upload", value: field(\.alternativeUpload))
                } header: {
                    Text("Alternative limits")
                }
                .listRowBackground(AppTheme.formRowBackground)
            } else if loading {
                Section { ProgressView("Loading speed limits…") }
            }
            if let failure {
                Section {
                    Text(failure).font(.subheadline).foregroundStyle(.secondary)
                    if draft == nil { Button("Retry") { Task { await load() } } }
                }
            }
            if saved {
                Section {
                    Label("Speed limits saved", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
            }
        }
        .scrollContentBackground(.hidden).softScrollEdges()
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Speed limits").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(!store.canControl || saving || draft?.limits == nil)
            }
        }
        .disabled(saving)
        .task { await load() }
        .onChange(of: store.activeInstanceID) { _, _ in dismiss() }
    }

    private func field(_ path: WritableKeyPath<SpeedLimitDraft, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: path] ?? "" },
            set: {
                draft?[keyPath: path] = $0
                saved = false
            })
    }

    private func load() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            let limits = try await store.speedLimits()
            guard !Task.isCancelled else { return }
            draft = SpeedLimitDraft(limits)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { failure = QBError.message(for: error) }
        }
    }

    private func save() async {
        guard let limits = draft?.limits else { return }
        saving = true
        failure = nil
        saved = false
        defer { saving = false }
        if await store.setSpeedLimits(limits, onFailure: { failure = $0 }) { saved = true }
    }
}

private struct SpeedLimitPicker: View {
    let title: String
    @Binding var value: String
    private static let presets = [
        0, 10, 25, 50, 100, 250, 500, 750, 1024, 2048, 5120, 10_240,
        25_600, 51_200, 102_400, 256_000, 512_000, 1_048_576, 2_097_151,
    ]
    private var choices: [Int] {
        // Keep a configured server value selectable even when it is not a preset.
        Array(Set(Self.presets + [Int(value) ?? 0])).sorted()
    }
    var body: some View {
        Picker(title, selection: $value) {
            ForEach(choices, id: \.self) { speed in
                Text("\(speed) KiB/s").tag(String(speed))
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("\(title) limit in KiB per second")
    }
}

struct AlternativeSpeedToggle: View {
    let store: TransferStore
    @State private var pending: Bool?
    @State private var failure: String?
    var body: some View {
        Toggle(
            isOn: Binding(
                get: { pending ?? store.info.alternativeSpeedLimits ?? false },
                set: { enabled in
                    guard pending == nil else { return }
                    pending = enabled
                    Task {
                        _ = await store.setAlternativeSpeedLimits(enabled, onFailure: { failure = $0 })
                        pending = nil
                    }
                }
            )
        ) {
            HStack {
                Label("Alternative speed limits", systemImage: "tortoise")
                if pending != nil { ProgressView().controlSize(.small) }
            }
        }
        .disabled(!store.canControl || pending != nil || store.info.alternativeSpeedLimits == nil)
        .alert(
            "Request failed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "Please try again.")
        }
    }
}
