import SwiftUI

/// Main note editor: H1 title field + plain markdown body.
/// Dark appearance by default; appearance system wired in Task 15.
struct EditorView: View {
    @ObservedObject var bridge: NoteEditorBridge

    var body: some View {
        ZStack {
            Color(red: 0.082, green: 0.078, blue: 0.090)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                TextField("Title", text: Binding(
                    get: { bridge.title },
                    set: { bridge.setTitle($0) }
                ))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                TextEditor(text: Binding(
                    get: { bridge.body },
                    set: { bridge.setBody($0) }
                ))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.85))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
