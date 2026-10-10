import SwiftUI

struct InstancesView: View {
    let store: TransferStore
    @State private var adding = false
    @State private var editing: ServerInstance?
    @State private var deleting: ServerInstance?
    var body: some View {
        Form {
            if store.connectionIssue != nil {
                Section { ServerMessage(store: store) }
                    .listRowBackground(Color.clear)
            }
            Section {
                if store.instances.isEmpty {
                    Text("No instances saved.")
                        .foregroundStyle(AppTheme.secondaryText)
                        .listRowBackground(AppTheme.formRowBackground)
                } else {
                    ForEach(store.instances) { instance in
                        Button {
                            open(instance)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(instance.name)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.primaryText)
                                    Text(instance.address)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if store.activeInstanceID == instance.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                AppTheme.formRowBackground,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleting = instance
                            }
                            .tint(.red)
                            Button("Edit", systemImage: "pencil") { editing = instance }
                                .tint(.blue)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = instance }
                            if store.activeInstanceID == instance.id {
                                if store.online {
                                    Button("Disconnect", systemImage: "power") { store.disconnect() }
                                } else {
                                    Button("Connect", systemImage: "link") { open(instance) }
                                }
                                if instance.remembersLogin {
                                    Button("Forget saved login", systemImage: "key.slash") {
                                        store.forgetSavedLogin()
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Saved Instances")
            }
        }
        .scrollContentBackground(.hidden)
        .softScrollEdges()
        .listRowSeparatorTint(AppTheme.border)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Instances")
        .minimizeNavigationBarOnScroll()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add instance", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { ServerEditorView(store: store, instance: nil) }
        .sheet(item: $editing) { instance in ServerEditorView(store: store, instance: instance) }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "instance")?",
            isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Delete saved instance", role: .destructive) {
                if let id = deleting?.id { Task { await store.deleteInstance(id) } }
                deleting = nil
            }
        } message: {
            Text(
                "This removes its saved connection and login credentials. Torrents on the server are unaffected."
            )
        }
    }
    private func open(_ instance: ServerInstance) {
        if store.activeInstanceID == instance.id {
            guard !store.online && !store.connecting else { return }
            if store.hasSavedLogin(for: instance.id) {
                Task { await store.reconnectActive() }
            } else {
                editing = instance
            }
        } else {
            Task {
                await store.activateInstance(instance.id)
                if !store.hasSavedLogin(for: instance.id) { editing = instance }
            }
        }
    }
}
