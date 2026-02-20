import SwiftUI

struct PillHUDView: View {
    @EnvironmentObject var viewModel: DictationViewModel

    var body: some View {
        HStack(spacing: 10) {
            switch viewModel.state {
            case .recording:
                recordingContent
            case .transcribing:
                transcribingContent
            case .cancelled:
                cancelledContent
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(height: 52)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
    }

    // MARK: - States

    private var recordingContent: some View {
        HStack(spacing: 10) {
            PulsingDot()

            MiniWaveformView(samples: viewModel.waveformSamples)
                .frame(width: 80, height: 24)

            Text("Recording")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var transcribingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.75)
                .frame(width: 18, height: 18)

            Text("Transcribing...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var cancelledContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Text("Cancelled")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Subviews

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.red.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.4 : 0.8)
                .opacity(pulsing ? 0 : 0.6)

            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

private struct MiniWaveformView: View {
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            let count = samples.count
            guard count > 0 else { return }

            let slotWidth = size.width / CGFloat(count)
            let barWidth = slotWidth * 0.55
            let midY = size.height / 2

            for (i, sample) in samples.enumerated() {
                let x = CGFloat(i) * slotWidth + (slotWidth - barWidth) / 2
                let barHeight = max(2, CGFloat(sample) * size.height)
                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.red.opacity(0.85))
                )
            }
        }
    }
}
