import SwiftUI

struct RecordingPanelView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var resourceMonitor: ResourceMonitor

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Murmur")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                stateIndicator
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Main content area
            ZStack {
                switch viewModel.state {
                case .idle:
                    idleView

                case .loading:
                    loadingView

                case .recording:
                    recordingView

                case .transcribing:
                    transcribingView

                case .done(let text):
                    doneView(text: text)

                case .cancelled:
                    cancelledView

                case .error(let message):
                    errorView(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Footer
            if case .recording = viewModel.state {
                Divider()
                HStack {
                    Spacer()
                    Button("Stop Recording") {
                        viewModel.stopAndTranscribe()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            // Resource footer — always visible
            Divider()
            resourceFooter
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var resourceFooter: some View {
        HStack(spacing: 12) {
            Label(
                String(format: "%.0f MB", resourceMonitor.memoryMB),
                systemImage: "memorychip"
            )
            Label(
                String(format: "%.1f%% CPU", resourceMonitor.cpuPercent),
                systemImage: "cpu"
            )
            Spacer()
            let h = Int(resourceMonitor.uptimeSeconds) / 3600
            let m = (Int(resourceMonitor.uptimeSeconds) % 3600) / 60
            Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Sub-views

    private var idleView: some View {
        Group {
            if viewModel.isModelReady {
                VStack(spacing: 10) {
                    IdleWaveformView()
                        .frame(height: 50)

                    Text("Press ⌘⇧D to start dictating")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if !viewModel.lastTranscription.isEmpty {
                        Text(viewModel.lastTranscription)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    Divider().padding(.horizontal, 16)

                    Button {
                        viewModel.transcribeFile()
                    } label: {
                        Label("Import audio file…", systemImage: "waveform.badge.plus")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                }
            } else {
                noModelView
            }
        }
    }

    private var noModelView: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No model downloaded")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Open Settings → Models to download one.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Loading model…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var recordingView: some View {
        VStack(spacing: 10) {
            WaveformView(samples: viewModel.waveformSamples, color: .red)
                .frame(height: 60)

            Text("Listening...")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private var transcribingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Transcribing...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func doneView(text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .foregroundStyle(.primary)

            Text("Copied to clipboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cancelledView: some View {
        VStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Recording cancelled")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button("Retry") {
                viewModel.setup()
            }
            .controlSize(.small)
        }
    }

    private var stateIndicator: some View {
        Group {
            switch viewModel.state {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }
}
