import SwiftUI
import Combine

// =============================================================================
// SplashView — Animated launch screen shown for ~2 seconds on app start.
//
// Shows the Nudge bell icon with a bounce animation, the app name,
// tagline, and a subtle loading indicator. Fades out smoothly before
// handing off to ContentView.
// =============================================================================

struct SplashView: View {
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var loadingOpacity: Double = 0

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.35, blue: 0.25),
                    Color(red: 1.0, green: 0.55, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 20) {
                Spacer()

                // App icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 140, height: 140)

                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(.white, .white.opacity(0.8))
                        .symbolEffect(.bounce, options: .repeating.speed(0.3))
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .accessibilityHidden(true)

                // App name
                Text("Nudge")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(textOpacity)

                // Tagline
                Text("Never miss a meeting again")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .opacity(taglineOpacity)

                Spacer()

                // Loading indicator
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.1)
                    .opacity(loadingOpacity)
                    .padding(.bottom, 60)
                    .accessibilityLabel("Loading")
            }
        }
        .onAppear {
            // Staggered entrance animations
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                textOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                taglineOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
                loadingOpacity = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
