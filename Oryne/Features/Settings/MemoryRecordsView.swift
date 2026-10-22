import SwiftUI
import SwiftData

/// What Oryne knows about you (docs/plans/memory-layer/SPEC.md, decision
/// 4): every record the daily pass wrote, grouped by kind, each editable
/// and deletable. Deleted records do not come back. Refresh runs the pass
/// now, which is also how it is tried on a simulator.
struct MemoryRecordsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.oceanAI) private var ai
    @Query(sort: \MemoryRecord.updatedAt, order: .reverse) private var records: [MemoryRecord]

    @State private var editing: MemoryRecord?
    @State private var draft = ""
    @State private var refreshing = false
    @State private var lastRun = Consolidation.lastRun

    private var grouped: [(kind: MemoryKind, records: [MemoryRecord])] {
        MemoryKind.allCases.compactMap { kind in
            let rows = records.filter { $0.kind == kind }
            return rows.isEmpty ? nil : (kind, rows)
        }
    }

    var body: some View {
        Form {
            if records.isEmpty {
                Section {
                    Text("Nothing yet.")
                        .font(.subheadline)
                        .foregroundStyle(OceanTheme.mist)
                }
                .listRowBackground(OceanTheme.fill)
            }
            ForEach(grouped, id: \.kind) { group in
                Section {
                    ForEach(group.records) { record in
                        Button {
                            draft = record.text
                            editing = record
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(record.text)
                                    .foregroundStyle(OceanTheme.foam)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if record.userEdited {
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundStyle(OceanTheme.mist)
                                        .accessibilityLabel("Edited by you")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let record = group.records[index]
                            MemoryRules.dismiss(record.text)
                            context.delete(record)
                        }
                        try? context.save()
                    }
                } header: {
                    Label(group.kind.label, systemImage: group.kind.symbol)
                }
                .listRowBackground(OceanTheme.fill)
            }
            // One action, one line under it. The page explains itself by its
            // rows; the how and when belong to the Settings footer above it.
            Section {
                Button {
                    refresh()
                } label: {
                    HStack {
                        Text("Refresh now")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
                .disabled(refreshing)
                .accessibilityIdentifier("memory.refresh")
            } footer: {
                if let lastRun {
                    Text("Last refreshed \(lastRun.formatted(.relative(presentation: .named))).")
                        .accessibilityIdentifier("memory.lastRefreshed")
                }
            }
            .listRowBackground(OceanTheme.fill)
        }
        .tint(OceanTheme.accent)
        .listRowSeparatorTint(Color.white.opacity(0.08))
        .scrollContentBackground(.hidden)
        .background(OceanBackground(animated: false))
        .navigationTitle("What Oryne knows about you")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("In your words", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Text", text: $draft)
            Button("Cancel", role: .cancel) { editing = nil }
            Button("Save") {
                if let record = editing {
                    let text = draft.trimmed
                    if !text.isEmpty {
                        record.text = text
                        record.userEdited = true
                        record.updatedAt = .now
                        try? context.save()
                    }
                }
                editing = nil
            }
        }
    }

    private func refresh() {
        refreshing = true
        Task {
            let summary = await Consolidation.run(context: context, ai: ai, reason: .manual)
            _ = summary
            await MainActor.run {
                lastRun = Consolidation.lastRun
                refreshing = false
            }
        }
    }
}
