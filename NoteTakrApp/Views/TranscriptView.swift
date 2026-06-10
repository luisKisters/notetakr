import SwiftUI
import NoteTakrKit

struct TranscriptView: View {
    let state: TranscriptState

    var body: some View {
        ScrollView {
            switch state {
            case .empty:
                Text("No transcript yet.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 32)
            case .segments(let segments):
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if let speaker = segment.speaker {
                                    Text(speaker)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                                Text(segment.startStamp)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            Text(segment.text)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.75))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }
}
