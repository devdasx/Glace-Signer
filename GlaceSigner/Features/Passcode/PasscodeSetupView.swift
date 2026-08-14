import SwiftUI

struct PasscodeSetupView: View {
    let mode: PasscodeEntryMode
    let showsPreviousMismatch: Bool
    let onMismatch: () -> Void
    let onSubmit: (String) -> Void

    init(
        mode: PasscodeEntryMode = .creation,
        showsPreviousMismatch: Bool = false,
        onMismatch: @escaping () -> Void = {},
        onSubmit: @escaping (String) -> Void = { _ in }
    ) {
        self.mode = mode
        self.showsPreviousMismatch = showsPreviousMismatch
        self.onMismatch = onMismatch
        self.onSubmit = onSubmit
    }

    var body: some View {
        PasscodeEntryScreen(
            mode: mode,
            showsPreviousMismatch: showsPreviousMismatch,
            onMismatch: onMismatch,
            onSubmit: onSubmit
        )
            .environment(\.layoutDirection, .leftToRight)
    }
}

private struct PasscodeEntryScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var passcode = ""
    @State private var showsMismatch = false
    @State private var confirmationSucceeded = false
    @State private var isProcessing = false
    @State private var advanceFeedbackTrigger = 0
    @State private var successFeedbackTrigger = 0
    @State private var errorFeedbackTrigger = 0
    @State private var completionTask: Task<Void, Never>?

    let mode: PasscodeEntryMode
    let showsPreviousMismatch: Bool
    let onMismatch: () -> Void
    let onSubmit: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let usesCompactVerticalRhythm =
                geometry.size.height < 700 || dynamicTypeSize.isAccessibilitySize
            let keypadWidth = min(max(geometry.size.width - 32, 0), 360)
            let keySpacing: CGFloat = keypadWidth < 300 ? 12 : 16
            let keyDiameter = min(
                max((keypadWidth - (keySpacing * 2)) / 3, 56),
                84
            )

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 10) {
                            Text(mode.titleKey)
                                .font(.largeTitle.bold())
                                .fontDesign(.rounded)
                                .foregroundStyle(.primary)

                            Text(mode.bodyKey)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        passcodeStatus
                            .padding(.top, usesCompactVerticalRhythm ? 20 : 28)
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 16)
                    .padding(.top, usesCompactVerticalRhythm ? 16 : 28)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                if !confirmationSucceeded {
                    keypad(
                        keyDiameter: keyDiameter,
                        spacing: keySpacing
                    )
                    .frame(maxWidth: keypadWidth)
                    .padding(.top, usesCompactVerticalRhythm ? 8 : 12)
                    .padding(.bottom, usesCompactVerticalRhythm ? 4 : 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            completionTask?.cancel()
            completionTask = nil
        }
        .sensoryFeedback(
            .impact(weight: .medium, intensity: 0.75),
            trigger: advanceFeedbackTrigger
        )
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .sensoryFeedback(.error, trigger: errorFeedbackTrigger)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var passcodeStatus: some View {
        VStack(spacing: 12) {
            if confirmationSucceeded {
                Text("passcode.confirmation.success")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                HStack(spacing: 16) {
                    ForEach(0..<6, id: \.self) { index in
                        Image(
                            systemName: index < passcode.count
                                ? "circle.fill"
                                : "circle"
                        )
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            index < passcode.count
                                ? AnyShapeStyle(.primary)
                                : AnyShapeStyle(.tertiary)
                        )
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(entryStatusKey))

                if displaysMismatch {
                    Text("passcode.error.mismatch")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.25),
            value: passcode.count
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.25),
            value: displaysMismatch
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.3),
            value: confirmationSucceeded
        )
    }

    private func keypad(
        keyDiameter: CGFloat,
        spacing: CGFloat
    ) -> some View {
        VStack(spacing: spacing) {
            ForEach(PasscodeKey.rows.indices, id: \.self) { rowIndex in
                HStack(spacing: spacing) {
                    ForEach(PasscodeKey.rows[rowIndex]) { key in
                        digitButton(key, diameter: keyDiameter)
                    }
                }
            }

            HStack(spacing: spacing) {
                Color.clear
                    .frame(width: keyDiameter, height: keyDiameter)
                    .accessibilityHidden(true)

                digitButton(.zero, diameter: keyDiameter)

                Button(action: deleteLastDigit) {
                    Image(systemName: "delete.left")
                        .font(.title3.weight(.regular))
                        .foregroundStyle(.primary)
                        .frame(width: keyDiameter, height: keyDiameter)
                }
                .buttonStyle(.plain)
                .opacity(passcode.isEmpty ? 0 : 1)
                .disabled(passcode.isEmpty || isProcessing)
                .accessibilityLabel(Text("passcode.keypad.delete"))
            }
        }
    }

    private func digitButton(
        _ key: PasscodeKey,
        diameter: CGFloat
    ) -> some View {
        Button {
            enterDigit(key.digit)
        } label: {
            VStack(spacing: 0) {
                Text(verbatim: key.digit)
                    .font(.largeTitle.monospacedDigit().weight(.regular))

                if !dynamicTypeSize.isAccessibilitySize {
                    Text(verbatim: key.letters.isEmpty ? " " : key.letters)
                        .font(.caption2.weight(.medium))
                        .tracking(1.5)
                        .opacity(key.letters.isEmpty ? 0 : 1)
                }
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(isProcessing)
        .accessibilityLabel(Text(verbatim: key.digit))
        .accessibilityHint(Text("passcode.keypad.digit.hint"))
    }

    private var entryStatusKey: LocalizedStringKey {
        if passcode.isEmpty {
            "passcode.entry.status.empty"
        } else if passcode.count == 6 {
            "passcode.entry.status.complete"
        } else {
            "passcode.entry.status.partial"
        }
    }

    private var displaysMismatch: Bool {
        showsMismatch || showsPreviousMismatch
    }

    private func enterDigit(_ digit: String) {
        guard !isProcessing, passcode.count < 6 else {
            return
        }

        showsMismatch = false
        passcode.append(digit)

        guard passcode.count == 6 else {
            return
        }

        isProcessing = true
        let completedPasscode = passcode
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            if reduceMotion {
                await Task.yield()
            } else {
                try? await Task.sleep(for: .milliseconds(160))
            }

            guard !Task.isCancelled else {
                return
            }

            complete(completedPasscode)
        }
    }

    private func deleteLastDigit() {
        guard !isProcessing, !passcode.isEmpty else {
            return
        }

        showsMismatch = false
        passcode.removeLast()
    }

    private func complete(_ completedPasscode: String) {
        switch mode {
        case .creation:
            // Haptic intent: a medium impact marks automatic advancement
            // after the complete first passcode has been entered.
            passcode = ""
            isProcessing = false
            advanceFeedbackTrigger += 1
            onSubmit(completedPasscode)

        case let .confirmation(confirmation):
            guard confirmation.matches(completedPasscode) else {
                // Haptic intent: error feedback accompanies the visible
                // mismatch before returning to create a fresh passcode.
                passcode = ""
                showsMismatch = true
                errorFeedbackTrigger += 1
                completionTask = Task { @MainActor in
                    if reduceMotion {
                        await Task.yield()
                    } else {
                        try? await Task.sleep(for: .milliseconds(250))
                    }

                    guard !Task.isCancelled else {
                        return
                    }
                    isProcessing = false
                    onMismatch()
                }
                return
            }

            // Haptic intent: success means only that both passcode entries
            // match; it does not imply persistence or encryption completed.
            passcode = ""
            isProcessing = false
            confirmationSucceeded = true
            successFeedbackTrigger += 1
            completionTask = Task { @MainActor in
                if reduceMotion {
                    await Task.yield()
                } else {
                    try? await Task.sleep(for: .milliseconds(300))
                }

                guard !Task.isCancelled else {
                    return
                }
                onSubmit(completedPasscode)
            }
        }
    }
}

enum PasscodeEntryMode {
    case creation
    case confirmation(PasscodeConfirmation)

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
}

private struct PasscodeKey: Identifiable {
    let digit: String
    let letters: String

    var id: String {
        digit
    }

    static let rows = [
        [
            PasscodeKey(digit: "1", letters: ""),
            PasscodeKey(digit: "2", letters: "ABC"),
            PasscodeKey(digit: "3", letters: "DEF")
        ],
        [
            PasscodeKey(digit: "4", letters: "GHI"),
            PasscodeKey(digit: "5", letters: "JKL"),
            PasscodeKey(digit: "6", letters: "MNO")
        ],
        [
            PasscodeKey(digit: "7", letters: "PQRS"),
            PasscodeKey(digit: "8", letters: "TUV"),
            PasscodeKey(digit: "9", letters: "WXYZ")
        ]
    ]

    static let zero = PasscodeKey(digit: "0", letters: "")
}

#Preview {
    NavigationStack {
        PasscodeSetupView(mode: .creation)
    }
    .preferredColorScheme(.light)
}
