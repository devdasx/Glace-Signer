import SwiftUI

struct SignerWalletCreationMethodView: View {
    let validationError: SignerSetupValidationError?
    let onRandomWallet: () -> Void
    let onDiceEntropy: () -> Void

    var body: some View {
        Form {
            Section {
                Button {
                    onRandomWallet()
                } label: {
                    Text("signer.create.method.random.action")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                VStack(alignment: .leading, spacing: 20) {
                    Text("signer.create.method.body")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("signer.create.method.random.section")
                        .fontDesign(.rounded)
                }
            } footer: {
                Text("signer.create.method.random.note")
            }

            Section {
                Button {
                    onDiceEntropy()
                } label: {
                    Text("signer.create.method.dice.action")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("signer.create.method.dice.section")
                    .fontDesign(.rounded)
            } footer: {
                Text("signer.create.method.dice.note")
            }

            if let validationError {
                Section {
                    Text(validationError.localizedKey)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(
            Text("signer.create.method.title")
                .fontDesign(.rounded)
        )
        .toolbarTitleDisplayMode(.large)
    }
}

struct SignerDiceEntropyView: View {
    @Binding var rolls: [UInt8]
    @Binding var validationError: SignerSetupValidationError?

    @State private var showsClearConfirmation = false
    @State private var clearWarningFeedback = 0
    @State private var undoFeedback = 0
    @State private var completionFeedback = 0

    let onGenerate: () -> Void

    var body: some View {
        Form {
            Section {
                Text("signer.create.dice.security.body")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                VStack(alignment: .leading, spacing: 20) {
                    Text("signer.create.dice.body")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("signer.create.dice.security.section")
                        .fontDesign(.rounded)
                }
            }

            Section {
                ProgressView(
                    value: Double(progress.entropyBitCount),
                    total: Double(DiceEntropy.requiredEntropyBitCount)
                ) {
                    Text("signer.create.dice.progress.label")
                } currentValueLabel: {
                    Text(progress.entropyBitCount, format: .number)
                }

                LabeledContent("signer.create.dice.rolls.label") {
                    Text(progress.recordedRollCount, format: .number)
                }

                LabeledContent("signer.create.dice.accepted_pairs.label") {
                    Text(progress.acceptedPairCount, format: .number)
                }

                LabeledContent("signer.create.dice.rejected_pairs.label") {
                    Text(progress.rejectedPairCount, format: .number)
                }

                if progress.isComplete {
                    Text("signer.create.dice.ready")
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("signer.create.dice.progress.section")
                    .fontDesign(.rounded)
            } footer: {
                Text("signer.create.dice.progress.note")
            }

            Section {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        rollButton(1)
                        rollButton(2)
                        rollButton(3)
                    }
                    GridRow {
                        rollButton(4)
                        rollButton(5)
                        rollButton(6)
                    }
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text("signer.create.dice.input.section")
                    .fontDesign(.rounded)
            } footer: {
                Text("signer.create.dice.input.note")
            }

            Section {
                if rolls.isEmpty {
                    Text("signer.create.dice.sequence.empty")
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: rollSequence)
                        .font(.body.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.layoutDirection, .leftToRight)
                        .privacySensitive()
                }

                HStack(spacing: 16) {
                    Button("signer.create.dice.action.undo") {
                        undoLastRoll()
                    }
                    .disabled(rolls.isEmpty)

                    Spacer()

                    Button(
                        "signer.create.dice.action.clear",
                        role: .destructive
                    ) {
                        clearWarningFeedback += 1
                        showsClearConfirmation = true
                    }
                    .disabled(rolls.isEmpty)
                }
                .buttonStyle(.borderless)
            } header: {
                Text("signer.create.dice.sequence.section")
                    .fontDesign(.rounded)
            } footer: {
                Text("signer.create.dice.sequence.note")
            }

            if let validationError {
                Section {
                    Text(validationError.localizedKey)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(
            Text("signer.create.dice.title")
                .fontDesign(.rounded)
        )
        .toolbarTitleDisplayMode(.large)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Button {
                onGenerate()
            } label: {
                Text("signer.create.dice.action.generate")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!progress.isComplete)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .confirmationDialog(
            "signer.create.dice.clear.title",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "signer.create.dice.clear.confirm",
                role: .destructive
            ) {
                rolls.removeAll(keepingCapacity: false)
                validationError = nil
            }
            Button(
                "signer.create.dice.clear.cancel",
                role: .cancel
            ) {}
        } message: {
            Text("signer.create.dice.clear.body")
        }
        .sensoryFeedback(.warning, trigger: clearWarningFeedback)
        .sensoryFeedback(.selection, trigger: undoFeedback)
        .sensoryFeedback(.success, trigger: completionFeedback)
        .onChange(of: progress.isComplete) { wasComplete, isComplete in
            if !wasComplete, isComplete {
                completionFeedback += 1
            }
        }
    }

    private var progress: DiceEntropyProgress {
        (try? DiceEntropy.progress(for: rolls)) ?? DiceEntropyProgress(
            recordedRollCount: rolls.count,
            entropyBitCount: 0,
            acceptedPairCount: 0,
            rejectedPairCount: 0,
            entropy: nil
        )
    }

    private var rollSequence: String {
        rolls.map(String.init).joined(separator: " ")
    }

    private func rollButton(_ roll: UInt8) -> some View {
        Button {
            guard !progress.isComplete else {
                return
            }
            rolls.append(roll)
            validationError = nil
        } label: {
            Text(Int(roll), format: .number)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(progress.isComplete)
        .accessibilityHint(Text("signer.create.dice.roll.hint"))
    }

    private func undoLastRoll() {
        guard !rolls.isEmpty else {
            return
        }
        rolls.removeLast()
        validationError = nil
        undoFeedback += 1
    }
}

#Preview("Creation Method") {
    NavigationStack {
        SignerWalletCreationMethodView(
            validationError: nil,
            onRandomWallet: {},
            onDiceEntropy: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dice Entropy · RTL") {
    NavigationStack {
        SignerDiceEntropyView(
            rolls: .constant([1, 2, 3, 4, 5, 6]),
            validationError: .constant(nil),
            onGenerate: {}
        )
    }
    .environment(\.layoutDirection, .rightToLeft)
    .preferredColorScheme(.light)
}
