import SwiftUI
import UIKit

struct SignerSetupFlowView: View {
    @StateObject private var networkMonitor = OfflineNetworkMonitor()

    @State private var path = [SignerSetupRoute]()
    @State private var draft = SignerSetupDraft()
    @State private var secretSource: SignerSecretSource?
    @State private var walletData: SignerWalletData?
    @State private var pendingPasscode = ""
    @State private var didPersistWallet = false
    @State private var flowFailure: SignerSetupValidationError?
    @State private var securityInterruptionFeedback = 0

    var body: some View {
        NavigationStack(path: $path) {
            SignerOnboardingView(
                onImportWallet: { begin(.importWallet) },
                onCreateWallet: { begin(.createWallet) }
            )
            .navigationDestination(for: SignerSetupRoute.self) { route in
                destination(for: route)
            }
        }
        .onAppear {
            networkMonitor.start()
        }
        .onChange(of: networkMonitor.status) { _, newStatus in
            respondToNetworkChange(newStatus)
        }
        .sensoryFeedback(.warning, trigger: securityInterruptionFeedback)
    }

    @ViewBuilder
    private func destination(for route: SignerSetupRoute) -> some View {
        switch route {
        case .offlineGate:
            OfflineGateView(status: networkMonitor.status) {
                advanceFromOfflineGate()
            }

        case .secretImport:
            SignerSecretImportView(draft: $draft) {
                validateImportedSecret()
            }

        case .setPasscode:
            PasscodeSetupView(mode: .creation) { passcode in
                pendingPasscode = passcode
                path.append(.confirmPasscode)
            }

        case .confirmPasscode:
            PasscodeSetupView(
                mode: .confirmation(expectedPasscode: pendingPasscode)
            ) { passcode in
                finishPasscodeSetup(passcode)
            }

        case .walletReview:
            if let walletData {
                SignerWalletReviewView(
                    walletData: walletData,
                    isNewWallet: draft.mode == .createWallet,
                    onCancel: { restart() }
                ) {
                    completeWalletReview()
                }
            } else {
                SignerSetupFailureView(error: .unexpected) {
                    restart()
                }
            }

        case .success:
            SignerSetupSuccessView(mode: draft.mode ?? .importWallet) {
                finish()
            }

        case .failure:
            SignerSetupFailureView(error: flowFailure ?? .unexpected) {
                restart()
            }
        }
    }

    private func begin(_ mode: SignerSetupMode) {
        draft.reset(for: mode)
        secretSource = nil
        walletData = nil
        pendingPasscode = ""
        didPersistWallet = false
        flowFailure = nil

        if networkMonitor.status.permitsSecretHandling {
            path.append(mode == .importWallet ? .secretImport : .setPasscode)
        } else {
            path.append(.offlineGate)
        }
    }

    private func advanceFromOfflineGate() {
        guard networkMonitor.status.permitsSecretHandling,
              path.last == .offlineGate,
              let mode = draft.mode else {
            return
        }
        path.append(mode == .importWallet ? .secretImport : .setPasscode)
    }

    private func validateImportedSecret() {
        guard networkMonitor.status.permitsSecretHandling else {
            respondToNetworkChange(networkMonitor.status)
            return
        }

        do {
            switch draft.importKind {
            case .mnemonic:
                secretSource = try BitcoinWalletEngine.importMnemonic(
                    draft.secretText,
                    passphrase: draft.passphrase,
                    network: draft.network
                )
            case .extendedPrivateKey:
                secretSource = try BitcoinWalletEngine.importExtendedPrivateKey(
                    draft.secretText,
                    standardStyle: draft.extendedKeyStyle
                )
            case .rawPrivateKey:
                secretSource = try BitcoinWalletEngine.importRawPrivateKey(
                    draft.secretText,
                    network: draft.network
                )
            case .walletImportFormat:
                secretSource = try BitcoinWalletEngine.importWalletImportFormat(
                    draft.secretText
                )
            }
            draft.validationError = nil
            draft.clearVisibleSecrets()
            path.append(.setPasscode)
        } catch let error as BIP39Error {
            switch error {
            case .unsupportedWordCount:
                draft.validationError = .mnemonicWordCount
            case .unknownWord:
                draft.validationError = .mnemonicUnknownWord
            case .invalidChecksum:
                draft.validationError = .mnemonicChecksum
            case .wordListUnavailable:
                draft.validationError = .resourceUnavailable
            }
        } catch let error as BitcoinWalletEngineError {
            switch error {
            case .invalidExtendedPrivateKey, .unsupportedExtendedPrivateKey:
                draft.validationError = .extendedPrivateKey
            case .ambiguousExtendedPrivateKey:
                draft.validationError = .extendedPrivateKeyStyle
            case .invalidPrivateKey:
                draft.validationError = .rawPrivateKey
            case .invalidWalletImportFormat:
                draft.validationError = .walletImportFormat
            case .invalidDerivation:
                draft.validationError = .derivation
            }
        } catch {
            draft.validationError = .unexpected
        }
    }

    private func finishPasscodeSetup(_ passcode: String) {
        guard networkMonitor.status.permitsSecretHandling,
              let mode = draft.mode else {
            respondToNetworkChange(networkMonitor.status)
            return
        }

        do {
            let source: SignerSecretSource
            let publicData: SignerWalletData
            switch mode {
            case .importWallet:
                guard let secretSource else {
                    throw SignerSetupFlowError.missingSecret
                }
                source = secretSource
                publicData = try BitcoinWalletEngine.publicData(
                    for: secretSource,
                    revealsRecoveryPhrase: false
                )

            case .createWallet:
                let wallet = try BitcoinWalletEngine.createWallet(
                    network: draft.network
                )
                source = wallet.0
                publicData = wallet.1
            }

            secretSource = source
            walletData = publicData
            pendingPasscode = passcode
            path.append(.walletReview)
        } catch {
            pendingPasscode = ""
            secretSource = nil
            walletData = nil
            flowFailure = .derivation
            path.append(.failure)
        }
    }

    private func completeWalletReview() {
        guard networkMonitor.status.permitsSecretHandling,
              let secretSource,
              !pendingPasscode.isEmpty else {
            respondToNetworkChange(networkMonitor.status)
            return
        }

        do {
            try SignerWalletVault.save(
                secretSource,
                passcode: pendingPasscode
            )
            pendingPasscode = ""
            self.secretSource = nil
            walletData = nil
            didPersistWallet = true
            path.append(.success)
        } catch {
            pendingPasscode = ""
            self.secretSource = nil
            walletData = nil
            flowFailure = .secureStorage
            path.append(.failure)
        }
    }

    private func respondToNetworkChange(_ status: OfflineNetworkStatus) {
        guard draft.mode != nil, !path.isEmpty else {
            return
        }

        if status.permitsSecretHandling {
            advanceFromOfflineGate()
            return
        }

        guard path.last != .offlineGate else {
            return
        }
        if didPersistWallet {
            SignerWalletVault.delete()
        }
        didPersistWallet = false
        draft.clearVisibleSecrets()
        pendingPasscode = ""
        secretSource = nil
        walletData = nil
        path = [.offlineGate]
        securityInterruptionFeedback += 1
    }

    private func restart() {
        if didPersistWallet {
            SignerWalletVault.delete()
        }
        didPersistWallet = false
        pendingPasscode = ""
        secretSource = nil
        walletData = nil
        path.removeAll()
        draft = SignerSetupDraft()
    }

    private func finish() {
        secretSource = nil
        walletData = nil
        pendingPasscode = ""
        didPersistWallet = false
        path.removeAll()
        draft = SignerSetupDraft()
    }
}

private enum SignerSetupFlowError: Error {
    case missingSecret
}

enum SignerSetupMode: Hashable, Sendable {
    case importWallet
    case createWallet
}

private enum SignerSetupRoute: Hashable {
    case offlineGate
    case secretImport
    case setPasscode
    case confirmPasscode
    case walletReview
    case success
    case failure
}

struct SignerSetupDraft {
    var mode: SignerSetupMode?
    var importKind: SignerImportKind = .mnemonic
    var secretText = ""
    var passphrase = ""
    var network: BitcoinNetwork = .mainnet
    var extendedKeyStyle: ExtendedKeyStyle?
    var revealsSecret = false
    var showsAdvancedSettings = false
    var validationError: SignerSetupValidationError?

    mutating func reset(for mode: SignerSetupMode) {
        self = SignerSetupDraft()
        self.mode = mode
    }

    mutating func clearVisibleSecrets() {
        secretText = ""
        passphrase = ""
        revealsSecret = false
    }
}

enum SignerSetupValidationError: Hashable {
    case mnemonicWordCount
    case mnemonicUnknownWord
    case mnemonicChecksum
    case extendedPrivateKey
    case extendedPrivateKeyStyle
    case rawPrivateKey
    case walletImportFormat
    case derivation
    case resourceUnavailable
    case secureStorage
    case unexpected

    var localizedKey: LocalizedStringKey {
        switch self {
        case .mnemonicWordCount: "signer.import.error.mnemonic_word_count"
        case .mnemonicUnknownWord: "signer.import.error.mnemonic_unknown_word"
        case .mnemonicChecksum: "signer.import.error.mnemonic_checksum"
        case .extendedPrivateKey: "signer.import.error.extended_private_key"
        case .extendedPrivateKeyStyle: "signer.import.error.extended_private_key_style"
        case .rawPrivateKey: "signer.import.error.raw_private_key"
        case .walletImportFormat: "signer.import.error.wif"
        case .derivation: "signer.import.error.derivation"
        case .resourceUnavailable: "signer.import.error.resource"
        case .secureStorage: "signer.import.error.secure_storage"
        case .unexpected: "signer.import.error.unexpected"
        }
    }
}

private struct OfflineGateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAdvanced = false
    @State private var warningFeedback = 0

    let status: OfflineNetworkStatus
    let onOfflineDetected: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 28)

                    Image(systemName: status.permitsSecretHandling ? "checkmark.shield" : "wifi.exclamationmark")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text(titleKey)
                            .font(.largeTitle.bold())
                            .fontDesign(.rounded)
                            .multilineTextAlignment(.center)

                        Text(bodyKey)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if status == .checking {
                        ProgressView()
                            .tint(.white)
                            .accessibilityLabel(Text("signer.offline.status.checking"))
                    } else if !status.permitsSecretHandling {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("signer.offline.instruction.airplane_mode")
                            Text("signer.offline.instruction.wifi")
                            Text("signer.offline.instruction.bluetooth")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.white.opacity(0.14), in: .rect(cornerRadius: 18))
                    }

                    Text("signer.offline.monitoring.note")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(0.9)

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: 560)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, 24)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(status.permitsSecretHandling ? Color.green : Color.red)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .onAppear {
            if !status.permitsSecretHandling, status != .checking {
                warningFeedback += 1
            }
            advanceIfPossible()
        }
        .onChange(of: status) { oldStatus, newStatus in
            if newStatus != .checking,
               !newStatus.permitsSecretHandling,
               oldStatus != newStatus {
                warningFeedback += 1
            }
            advanceIfPossible()
        }
    }

    private var titleKey: LocalizedStringKey {
        switch status {
        case .checking: "signer.offline.checking.title"
        case .offline: "signer.offline.ready.title"
        case .wifiConnected: "signer.offline.wifi.title"
        case .otherConnection: "signer.offline.other.title"
        }
    }

    private var bodyKey: LocalizedStringKey {
        switch status {
        case .checking: "signer.offline.checking.body"
        case .offline: "signer.offline.ready.body"
        case .wifiConnected: "signer.offline.wifi.body"
        case .otherConnection: "signer.offline.other.body"
        }
    }

    private func advanceIfPossible() {
        guard status.permitsSecretHandling, !hasAdvanced else {
            return
        }
        hasAdvanced = true
        if reduceMotion {
            onOfflineDetected()
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                onOfflineDetected()
            }
        }
    }
}

private struct SignerSecretImportView: View {
    @Binding var draft: SignerSetupDraft
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                Text("signer.import.title")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)

                Text("signer.import.body")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("signer.import.type.label", selection: $draft.importKind) {
                    ForEach(SignerImportKind.allCases) { kind in
                        Text(kind.titleKey).tag(kind)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("signer.import.type.section")
                    .fontDesign(.rounded)
            }

            Section {
                if draft.revealsSecret {
                    TextField(inputPlaceholderKey, text: $draft.secretText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    SecureField(inputPlaceholderKey, text: $draft.secretText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .environment(\.layoutDirection, .leftToRight)
                }

                Toggle("signer.import.show_input", isOn: $draft.revealsSecret)
            } header: {
                Text(draft.importKind.titleKey)
                    .fontDesign(.rounded)
            } footer: {
                Text(draft.importKind.helpKey)
            }

            DisclosureGroup(
                isExpanded: $draft.showsAdvancedSettings
            ) {
                if draft.importKind == .mnemonic || draft.importKind == .rawPrivateKey {
                    Picker("signer.import.network.label", selection: $draft.network) {
                        ForEach(BitcoinNetwork.allCases) { network in
                            Text(network.titleKey).tag(network)
                        }
                    }
                }

                if draft.importKind == .mnemonic {
                    SecureField(
                        "signer.import.passphrase.placeholder",
                        text: $draft.passphrase
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Text("signer.import.passphrase.note")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if draft.importKind == .extendedPrivateKey {
                    Picker(
                        "signer.import.account_style.label",
                        selection: $draft.extendedKeyStyle
                    ) {
                        Text("signer.import.account_style.unspecified")
                            .tag(nil as ExtendedKeyStyle?)
                        ForEach(ExtendedKeyStyle.allCases) { style in
                            Text(style.titleKey).tag(Optional(style))
                        }
                    }

                    Text("signer.import.account_style.note")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("signer.import.advanced.title")
                    .font(.headline)
                    .fontDesign(.rounded)
            }

            if let validationError = draft.validationError {
                Section {
                    Text(validationError.localizedKey)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Button {
                onContinue()
            } label: {
                Text("signer.import.action.continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(draft.secretText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .sensoryFeedback(.selection, trigger: draft.importKind)
        .sensoryFeedback(.error, trigger: draft.validationError)
        .onChange(of: draft.importKind) { _, _ in
            draft.clearVisibleSecrets()
            draft.extendedKeyStyle = nil
            draft.validationError = nil
        }
        .onChange(of: draft.secretText) { _, _ in
            draft.validationError = nil
        }
    }

    private var inputPlaceholderKey: LocalizedStringKey {
        switch draft.importKind {
        case .mnemonic: "signer.import.mnemonic.placeholder"
        case .extendedPrivateKey: "signer.import.xprv.placeholder"
        case .rawPrivateKey: "signer.import.private_key.placeholder"
        case .walletImportFormat: "signer.import.wif.placeholder"
        }
    }
}

private struct SignerWalletReviewView: View {
    @State private var confirmsRecoveryBackup = false
    @State private var copyFeedback = 0

    let walletData: SignerWalletData
    let isNewWallet: Bool
    let onCancel: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section {
                Text("signer.review.title")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)

                Text(isNewWallet ? "signer.review.create.body" : "signer.review.import.body")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent("signer.review.network.label") {
                    Text(walletData.network.titleKey)
                }
            } header: {
                Text("signer.review.network.section")
                    .fontDesign(.rounded)
            }

            ForEach(walletData.accounts) { account in
                Section {
                    if !account.derivationPath.isEmpty {
                        LabeledContent("signer.review.derivation.label") {
                            Text(verbatim: account.derivationPath)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    Text(verbatim: account.extendedPublicKey)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)

                    Button("signer.review.copy_public_key") {
                        UIPasteboard.general.string = account.extendedPublicKey
                        copyFeedback += 1
                    }
                } header: {
                    Text(account.style.titleKey)
                        .fontDesign(.rounded)
                }
            }

            if !walletData.singleKeyValues.isEmpty {
                Section {
                    Text("signer.review.single_key.note")
                        .foregroundStyle(.secondary)

                    ForEach(walletData.singleKeyValues) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.kind.titleKey)
                                .font(.headline)
                                .fontDesign(.rounded)
                            Text(verbatim: item.value)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("signer.review.single_key.section")
                        .fontDesign(.rounded)
                }
            }

            if let recoveryPhrase = walletData.recoveryPhrase {
                Section {
                    ForEach(
                        Array(recoveryPhrase.split(separator: " ").enumerated()),
                        id: \.offset
                    ) { index, word in
                        LabeledContent {
                            Text(verbatim: String(word))
                                .font(.body.monospaced())
                                .environment(\.layoutDirection, .leftToRight)
                        } label: {
                            Text(index + 1, format: .number)
                                .monospacedDigit()
                        }
                    }

                    Toggle(
                        "signer.review.recovery.confirm",
                        isOn: $confirmsRecoveryBackup
                    )
                } header: {
                    Text("signer.review.recovery.section")
                        .fontDesign(.rounded)
                } footer: {
                    Text("signer.review.recovery.warning")
                }
                .privacySensitive()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("signer.review.action.cancel", action: onCancel)
            }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Button {
                onComplete()
            } label: {
                Text("signer.review.action.complete")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(walletData.recoveryPhrase != nil && !confirmsRecoveryBackup)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .sensoryFeedback(
            .impact(weight: .light, intensity: 0.6),
            trigger: copyFeedback
        )
    }
}

private struct SignerSetupSuccessView: View {
    @State private var successFeedback = 0

    let mode: SignerSetupMode
    let onDone: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text("signer.success.title")
                            .font(.largeTitle.bold())
                            .fontDesign(.rounded)
                            .multilineTextAlignment(.center)

                        Text(mode == .createWallet ? "signer.success.create.body" : "signer.success.import.body")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: 560)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarBackButtonHidden(true)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Button {
                onDone()
            } label: {
                Text("signer.success.action.done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .sensoryFeedback(.success, trigger: successFeedback)
        .onAppear {
            successFeedback += 1
        }
    }
}

private struct SignerSetupFailureView: View {
    @State private var errorFeedback = 0

    let error: SignerSetupValidationError
    let onRestart: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("signer.failure.title")
                    .fontDesign(.rounded)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text(error.localizedKey)
        } actions: {
            Button("signer.failure.action.restart", action: onRestart)
        }
        .navigationBarBackButtonHidden(true)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .onAppear {
            errorFeedback += 1
        }
    }
}

private extension SignerImportKind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .mnemonic: "signer.import.type.mnemonic"
        case .extendedPrivateKey: "signer.import.type.xprv"
        case .rawPrivateKey: "signer.import.type.private_key"
        case .walletImportFormat: "signer.import.type.wif"
        }
    }

    var helpKey: LocalizedStringKey {
        switch self {
        case .mnemonic: "signer.import.help.mnemonic"
        case .extendedPrivateKey: "signer.import.help.xprv"
        case .rawPrivateKey: "signer.import.help.private_key"
        case .walletImportFormat: "signer.import.help.wif"
        }
    }
}

private extension BitcoinNetwork {
    var titleKey: LocalizedStringKey {
        switch self {
        case .mainnet: "bitcoin.network.mainnet"
        case .testnet: "bitcoin.network.testnet"
        }
    }
}

private extension ExtendedKeyStyle {
    var titleKey: LocalizedStringKey {
        switch self {
        case .legacy: "signer.review.account.legacy"
        case .nestedSegWit: "signer.review.account.nested_segwit"
        case .nativeSegWit: "signer.review.account.native_segwit"
        case .nestedMultisig: "signer.review.account.nested_multisig"
        case .nativeMultisig: "signer.review.account.native_multisig"
        case .taproot: "signer.review.account.taproot"
        }
    }
}

private extension SignerPublicValue.Kind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .publicKey: "signer.review.value.public_key"
        case .legacyAddress: "signer.review.value.legacy_address"
        case .nestedSegWitAddress: "signer.review.value.nested_segwit_address"
        case .nativeSegWitAddress: "signer.review.value.native_segwit_address"
        case .taprootAddress: "signer.review.value.taproot_address"
        }
    }
}

#Preview {
    SignerSetupFlowView()
        .preferredColorScheme(.light)
}
