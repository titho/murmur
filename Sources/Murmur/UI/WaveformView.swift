import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    var color: Color = .accentColor
    var barSpacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { _ in
            Canvas { ctx, size in
                let count = samples.count
                guard count > 0 else { return }

                let totalSpacing = barSpacing * CGFloat(count - 1)
                let barWidth = (size.width - totalSpacing) / CGFloat(count)
                let centerY = size.height / 2

                for (i, sample) in samples.enumerated() {
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let amplitude = CGFloat(sample)
                    let barHeight = max(2, amplitude * size.height * 0.9)

                    let rect = CGRect(
                        x: x,
                        y: centerY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )

                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                    // Fade bars by position — center bars brighter
                    let normalizedPos = abs(CGFloat(i) - CGFloat(count) / 2) / (CGFloat(count) / 2)
                    let opacity = Double(1.0 - normalizedPos * 0.4)

                    ctx.fill(path, with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}

/// Idle/flat waveform placeholder (gentle sine pulse)
struct IdleWaveformView: View {
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
            Canvas { ctx, size in
                let count = 40
                let barWidth: CGFloat = 4
                let spacing: CGFloat = 3
                let centerY = size.height / 2
                let t = timeline.date.timeIntervalSinceReferenceDate

                for i in 0..<count {
                    let x = CGFloat(i) * (barWidth + spacing)
                    let normalizedPos = Double(i) / Double(count)
                    let amplitude = sin(normalizedPos * .pi * 2 + t * 1.5) * 0.12 + 0.08
                    let barHeight = max(2, CGFloat(amplitude) * size.height)

                    let rect = CGRect(
                        x: x,
                        y: centerY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.secondary.opacity(0.5)))
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        WaveformView(samples: (0..<60).map { _ in Float.random(in: 0...1) })
            .frame(width: 280, height: 60)

        IdleWaveformView()
            .frame(width: 280, height: 60)
    }
    .padding()
}
