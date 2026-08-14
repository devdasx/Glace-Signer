import SwiftUI

struct SignerOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var hasAppeared = false
    @State private var continueFeedbackTrigger = 0

    private let onContinue: () -> Void

    init(onContinue: @escaping () -> Void = {}) {
        self.onContinue = onContinue
    }

    var body: some View {
        GeometryReader { geometry in
            let usesCompactVerticalRhythm =
                geometry.size.height < 720 || dynamicTypeSize.isAccessibilitySize

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: usesCompactVerticalRhythm ? 24 : 56)

                    VStack(spacing: usesCompactVerticalRhythm ? 16 : 24) {
                        Image("BrandIcon")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(
                                width: usesCompactVerticalRhythm ? 88 : 112,
                                height: usesCompactVerticalRhythm ? 88 : 112
                            )
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)

                        VStack(spacing: usesCompactVerticalRhythm ? 8 : 12) {
                            Text("signer.onboarding.brand.title")
                                .font(.largeTitle.bold())
                                .fontDesign(.rounded)
                                .foregroundStyle(.primary)

                            Text("signer.onboarding.hero.title")
                                .font(.title2.weight(.semibold))
                                .fontDesign(.rounded)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            Text("signer.onboarding.hero.body")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: usesCompactVerticalRhythm ? 24 : 56)

                    if dynamicTypeSize.isAccessibilitySize {
                        actionSection
                    }
                }
                .frame(maxWidth: 560)
                .frame(minHeight: geometry.size.height, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, usesCompactVerticalRhythm ? 12 : 20)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: reduceMotion || hasAppeared ? 0 : 12)
                .animation(
                    reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.6),
                    value: hasAppeared
                )
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                actionSection
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            hasAppeared = true
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                // Haptic intent: a medium impact marks entry into the
                // security-sensitive offline signer setup flow.
                continueFeedbackTrigger += 1
                onContinue()
            } label: {
                Text("signer.onboarding.action.continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .sensoryFeedback(
                .impact(weight: .medium, intensity: 0.8),
                trigger: continueFeedbackTrigger
            )

            Text("signer.onboarding.security.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    SignerOnboardingView()
        .preferredColorScheme(.light)
}

#Preview {
    SignerOnboardingView()
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.light)
}
