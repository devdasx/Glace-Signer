import SwiftUI

struct SignerOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var hasAppeared = false
    @State private var importFeedbackTrigger = 0
    @State private var createFeedbackTrigger = 0

    private let onImportWallet: () -> Void
    private let onCreateWallet: () -> Void

    init(
        onImportWallet: @escaping () -> Void = {},
        onCreateWallet: @escaping () -> Void = {}
    ) {
        self.onImportWallet = onImportWallet
        self.onCreateWallet = onCreateWallet
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

                        Text("signer.onboarding.hero.body")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
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
        .navigationTitle(
            Text("signer.onboarding.brand.title")
                .fontDesign(.rounded)
        )
        .navigationSubtitle(
            Text("signer.onboarding.hero.title")
                .fontDesign(.rounded)
        )
        .toolbarTitleDisplayMode(.large)
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
                // security-sensitive flow for importing existing secrets.
                importFeedbackTrigger += 1
                onImportWallet()
            } label: {
                Text("signer.onboarding.action.import_wallet")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .sensoryFeedback(
                .impact(weight: .medium, intensity: 0.8),
                trigger: importFeedbackTrigger
            )

            Button {
                // Haptic intent: a lighter impact distinguishes the start of
                // a new-wallet creation flow from importing existing secrets.
                createFeedbackTrigger += 1
                onCreateWallet()
            } label: {
                Text("signer.onboarding.action.create_wallet")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .sensoryFeedback(
                .impact(weight: .light, intensity: 0.7),
                trigger: createFeedbackTrigger
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
