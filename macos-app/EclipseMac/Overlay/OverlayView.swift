import SwiftUI

struct OverlayView: View {
    @ObservedObject var runtime: RuntimeModel

    var body: some View {
        HStack(spacing: 16) {
            EclipseOrb(state: runtime.state, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(runtime.state.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(runtime.debugMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("⌥ Space")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(width: 480, height: 156)
        .background(.ultraThinMaterial)
        .background(EclipseTheme.canvas.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .padding(8)
    }
}
