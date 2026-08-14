import SwiftUI

struct PasscodeSetupView: View {
    @State private var pendingPasscode = ""
    @State private var isShowingConfirmation = false

    private let onPasscodeConfirmed: (String) -> Void

    init(onPasscodeConfirmed: @escaping (String) -> Void = { _ in }) {
        self.onPasscodeConfirmed = onPasscodeConfirmed
    }

    var body: some View {
        PasscodeEntryScreen(mode: .creation) { passcode in
            pendingPasscode = passcode
            isShowingConfirmation = true
        }
        .navigationDestination(isPresented: $isShowingConfirmation) {
            PasscodeEntryScreen(
                mode: .confirmation(expectedPasscode: pendingPasscode)
            ) { confirmedPasscode in
                onPasscodeConfirmed(confirmedPasscode)
                pendingPasscode = ""
            }
        }
        .onChange(of: isShowingConfirmation) { _, isShowing in
            if !isShowing {
                pendingPasscode = ""
            }
        }
    }
}

private struct PasscodeEntryScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var passcode = ""
    @State private var showsMismatch = false
    @State private var confirmationSucceeded = false
    @State private var advanceFeedbackTrigger = 0
    @State private var successFeedbackTrigger = 0
    @State private var errorFeedbackTrigger = 0

    @FocusState private var isPasscodeFieldFocused: Bool

    let mode: PasscodeEntryMode
    let onSubmit: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ProgressView(value: mode.progressValue) {
                    Text(mode.progressKey)
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.rounded)
                }
                .tint(Color.accentColor)

                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: mode.symbolName)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    Text(mode.titleKey)
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(.primary)

                    Text(mode.bodyKey)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if confirmationSucceeded {
                        Label(
                            "passcode.confirmation.success",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.headline)
                        .fontDesign(.rounded)
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        SecureField("passcode.field.placeholder", text: $passcode)
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .focused($isPasscodeFieldFocused)
                            .accessibilityLabel(Text("passcode.field.accessibility.label"))
                            .accessibilityHint(Text("passcode.field.accessibility.hint"))

                        if showsMismatch {
                            Label(
                                "passcode.error.mismatch",
                                systemImage: "exclamationmark.circle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Text("passcode.field.guidance")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.25),
                    value: showsMismatch
                )
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.3),
                    value: confirmationSucceeded
                )

                Label {
                    Text("passcode.security.note")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Button(action: submit) {
                if confirmationSucceeded {
                    Text("passcode.action.matched")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(mode.actionKey)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isEntryComplete || confirmationSucceeded)
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("passcode.keyboard.done") {
                    isPasscodeFieldFocused = false
                }
            }
        }
        .task {
            await Task.yield()
            isPasscodeFieldFocused = true
        }
        .onChange(of: passcode) { _, newValue in
            let normalizedValue = normalizedPasscode(from: newValue)

            if normalizedValue != newValue {
                passcode = normalizedValue
            }

            if showsMismatch && !normalizedValue.isEmpty {
                showsMismatch = false
            }
        }
        .sensoryFeedback(
            .impact(weight: .medium, intensity: 0.75),
            trigger: advanceFeedbackTrigger
        )
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .sensoryFeedback(.error, trigger: errorFeedbackTrigger)
    }

    private var isEntryComplete: Bool {
        passcode.count == 6
    }

    private func normalizedPasscode(from value: String) -> String {
        value
            .compactMap { character in
                guard let digit = character.wholeNumberValue,
                      (0...9).contains(digit) else {
                    return nil
                }

                return String(digit)
            }
            .prefix(6)
            .joined()
    }

    private func submit() {
        guard isEntryComplete else {
            return
        }

        switch mode {
        case .creation:
            // Haptic intent: a medium impact marks accepting the first entry
            // and moving into the structurally separate confirmation step.
            let createdPasscode = passcode
            passcode = ""
            advanceFeedbackTrigger += 1
            isPasscodeFieldFocused = false
            onSubmit(createdPasscode)

        case let .confirmation(expectedPasscode):
            guard passcode == expectedPasscode else {
                // Haptic intent: error feedback accompanies the visible
                // mismatch and the cleared field, never ordinary typing.
                passcode = ""
                showsMismatch = true
                errorFeedbackTrigger += 1
                isPasscodeFieldFocused = true
                return
            }

            // Haptic intent: success means only that both entries match. It
            // does not imply that storage or wallet encryption has completed.
            let confirmedPasscode = passcode
            passcode = ""
            confirmationSucceeded = true
            successFeedbackTrigger += 1
            isPasscodeFieldFocused = false
            onSubmit(confirmedPasscode)
        }
    }
}

private enum PasscodeEntryMode {
    case creation
    case confirmation(expectedPasscode: String)

    var progressValue: Double {
        switch self {
        case .creation:
            0.5
        case .confirmation:
            1
        }
    }

    var progressKey: LocalizedStringKey {
        switch self {
        case .creation:
            "passcode.progress.set"
        case .confirmation:
            "passcode.progress.confirm"
        }
    }

    var symbolName: String {
        switch self {
        case .creation:
            "lock.badge.plus"
        case .confirmation:
            "checkmark.shield"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .creation:
            "passcode.set.title"
        case .confirmation:
            "passcode.confirm.title"
        }
    }

    var bodyKey: LocalizedStringKey {
        switch self {
        case .creation:
            "passcode.set.body"
        case .confirmation:
            "passcode.confirm.body"
        }
    }

    var actionKey: LocalizedStringKey {
        switch self {
        case .creation:
            "passcode.action.continue"
        case .confirmation:
            "passcode.action.confirm"
        }
    }
}

#Preview {
    NavigationStack {
        PasscodeSetupView()
    }
    .preferredColorScheme(.light)
}

#Preview {
    NavigationStack {
        PasscodeSetupView()
    }
    .environment(\.layoutDirection, .rightToLeft)
    .preferredColorScheme(.light)
}
