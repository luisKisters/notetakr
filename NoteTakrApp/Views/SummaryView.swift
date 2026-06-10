import SwiftUI
import NoteTakrKit

struct SummaryView: View {
    let state: SummaryState
    let onGenerate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch state {
                case .missing:
                    Button("Generate summary", action: onGenerate)
                        .buttonStyle(.plain)
                        .foregroundColor(Color(red: 0.545, green: 0.361, blue: 0.965))
                        .font(.system(size: 14))
                        .padding(.top, 8)
                case .generating:
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Generating…")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .padding(.top, 8)
                case .ready(let text):
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(.red.opacity(0.8))
                        Button("Retry", action: onGenerate)
                            .buttonStyle(.plain)
                            .foregroundColor(Color(red: 0.545, green: 0.361, blue: 0.965))
                            .font(.system(size: 14))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
