import SwiftUI

struct ContentView: View {
    @StateObject private var log: SpikeLog
    @StateObject private var viewModel: SpikeViewModel

    init() {
        let log = SpikeLog()
        _log = StateObject(wrappedValue: log)
        _viewModel = StateObject(wrappedValue: SpikeViewModel(log: log))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Take", selection: $viewModel.takeLabel) {
                    ForEach(SpikeViewModel.TakeLabel.allCases) { label in
                        Text(label.displayName).tag(label)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .disabled(viewModel.isRecording)

                HStack(spacing: 12) {
                    Button(viewModel.isRecording ? "Stop" : "Record") {
                        viewModel.toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRecording ? .red : .accentColor)

                    Button("Run SpeechTranscriber pass") {
                        viewModel.runTestA()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRecording || viewModel.isRunningTestA || !viewModel.hasRecording)
                }

                if viewModel.isRunningTestA {
                    ProgressView("Running zh-CN pass, then en-US pass…")
                }

                if let note = viewModel.statusNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(log.lines) { line in
                                Text("\(line.stream): \(line.text)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: log.lines.count) { _, _ in
                        if let last = log.lines.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                HStack {
                    ShareLink(item: log.exportText) {
                        Label("Share log", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button("Clear log", role: .destructive) {
                        log.clear()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Bilingual Spike")
            .task {
                await viewModel.requestPermissionsIfNeeded()
            }
        }
    }
}
