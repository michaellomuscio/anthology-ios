import SwiftUI

struct StatusDot: View {
    let status: SessionStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(status.color.opacity(0.3), lineWidth: 1)
                    .scaleEffect(status == .running ? 1.6 : 1.0)
                    .opacity(status == .running ? 0.0 : 1.0)
                    .animation(
                        status == .running
                            ? .easeOut(duration: 1.4).repeatForever(autoreverses: false)
                            : .default,
                        value: status
                    )
            )
    }
}

#Preview {
    HStack(spacing: 14) {
        ForEach(SessionStatus.allCases, id: \.self) { s in
            VStack { StatusDot(status: s); Text(s.label).font(.caption2) }
        }
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
