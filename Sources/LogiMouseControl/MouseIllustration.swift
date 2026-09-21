import SwiftUI

/// Original vector artwork, rendered natively; no remote assets or vendor branding.
struct MouseIllustration: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color.mint.opacity(0.08)).frame(width: 165, height: 175).blur(radius: 22).offset(y: 30)
            MouseBody().fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.19), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(MouseBody().stroke(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 16, x: 7, y: 15)
            Path { p in p.move(to: CGPoint(x: 119, y: 23)); p.addCurve(to: CGPoint(x: 118, y: 127), control1: CGPoint(x: 111, y: 44), control2: CGPoint(x: 121, y: 108)) }.stroke(.black.opacity(0.5), lineWidth: 2)
            Path { p in p.move(to: CGPoint(x: 57, y: 88)); p.addCurve(to: CGPoint(x: 160, y: 113), control1: CGPoint(x: 80, y: 107), control2: CGPoint(x: 124, y: 124)) }.stroke(.black.opacity(0.5), lineWidth: 1)
            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5)).frame(width: 22, height: 44).offset(x: 14, y: -60)
            RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(white: 0.65), Color(white: 0.22), Color(white: 0.52)], startPoint: .leading, endPoint: .trailing)).frame(width: 14, height: 32).overlay(VStack(spacing: 3) { ForEach(0..<7) { _ in Rectangle().fill(.black.opacity(0.5)).frame(width: 12, height: 1) } }).offset(x: 14, y: -60)
            Capsule().fill(.black.opacity(0.6)).frame(width: 10, height: 18).offset(x: 14, y: -20)
            Capsule().fill(Color.mint.opacity(0.9)).frame(width: 3, height: 6).shadow(color: .mint.opacity(0.6), radius: 3).offset(x: -25, y: -59)
            RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)).frame(width: 12, height: 30).rotationEffect(.degrees(-18)).offset(x: -53, y: -26)
            Capsule().fill(Color(white: 0.12)).frame(width: 24, height: 8).rotationEffect(.degrees(25)).offset(x: -52, y: 5)
            Capsule().fill(Color(white: 0.12)).frame(width: 24, height: 8).rotationEffect(.degrees(25)).offset(x: -57, y: 20)
            Text("MX").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.23)).rotationEffect(.degrees(4)).offset(x: 15, y: 47)
        }.frame(width: 200, height: 230).rotationEffect(.degrees(-13))
    }
}
private struct MouseBody: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 101, y: 20))
        p.addCurve(to: CGPoint(x: 162, y: 45), control1: CGPoint(x: 126, y: 12), control2: CGPoint(x: 157, y: 21))
        p.addCurve(to: CGPoint(x: 175, y: 169), control1: CGPoint(x: 179, y: 79), control2: CGPoint(x: 183, y: 132))
        p.addCurve(to: CGPoint(x: 120, y: 212), control1: CGPoint(x: 173, y: 200), control2: CGPoint(x: 150, y: 214))
        p.addCurve(to: CGPoint(x: 39, y: 183), control1: CGPoint(x: 81, y: 211), control2: CGPoint(x: 40, y: 204))
        p.addCurve(to: CGPoint(x: 48, y: 118), control1: CGPoint(x: 37, y: 162), control2: CGPoint(x: 49, y: 152))
        p.addCurve(to: CGPoint(x: 101, y: 20), control1: CGPoint(x: 47, y: 62), control2: CGPoint(x: 67, y: 28))
        p.closeSubpath(); return p
    }
}
