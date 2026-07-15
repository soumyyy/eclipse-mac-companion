import SwiftUI

enum EclipseTheme {
    static let canvas = Color(red: 0.12, green: 0.11, blue: 0.14)
    static let ink = Color(red: 0.91, green: 0.89, blue: 0.84)
    static let violet = Color(red: 0.64, green: 0.54, blue: 0.94)
    static let blue = Color(red: 0.42, green: 0.68, blue: 0.96)
    static let mint = Color(red: 0.42, green: 0.82, blue: 0.68)
    static let amber = Color(red: 0.95, green: 0.70, blue: 0.33)
    static let coral = Color(red: 0.95, green: 0.43, blue: 0.40)
}

struct EclipseOrb: View {
    let state: AssistantState
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [state.tint.opacity(0.95), EclipseTheme.canvas],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size
                    )
                )
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 1)
            Image(systemName: state.symbolName)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
        .shadow(color: state.tint.opacity(0.24), radius: 14, y: 5)
        .animation(.easeInOut(duration: 0.24), value: state)
    }
}

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }
    }
}
