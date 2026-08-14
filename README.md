# Glace Signer: Offline Bitcoin Signer - BTC

Glace Signer is the offline signing half of a two-application, Bitcoin-mainnet-only wallet for native iOS. It is designed for a separate iPhone or iPad that remains disconnected while creating or importing protected signing material. Transaction review and signing remain future work.

Its independent companion is [Glace: Bitcoin Wallet - BTC](https://github.com/devdasx/Glace), the watch-only app that handles public wallet data and future network activity without ever receiving a seed phrase or private key. The repositories, application targets, bundle identifiers, and security responsibilities remain independent.

## Project status

Glace Signer is in early development. The repository now implements the complete first-time wallet setup slice for both onboarding choices:

- Continuous active-network-path monitoring before and throughout secret handling, with a blocking red warning screen for Wi-Fi or any other detected connection.
- Native large navigation titles and subtitles remain in the app bar and collapse with scrolling instead of occupying form or list rows.
- Mainnet-only import of checksum-valid English BIP39 recovery phrases, supported BIP32/SLIP-132 extended private keys, raw 32-byte secp256k1 private keys, and compressed or uncompressed WIF; testnet material is rejected.
- Advanced Settings appears only for recovery-phrase imports and contains only the optional BIP39 passphrase. Required wallet-standard selection for an ambiguous `xprv` remains visible in the main import form.
- Creation of a cryptographically random 24-word English BIP39 wallet while the active-path monitor reports offline.
- Separate Set Passcode and Confirm Passcode screens with a six-digit, LTR, ASCII keypad; a mismatch clears both entries and returns to Set Passcode.
- Local BIP32 account derivation and public review for BIP44 `xpub`, BIP49 `ypub`, BIP84 `zpub`, and BIP86 `xpub` data. Account-level standard `xprv` imports require an explicit standard instead of guessing; single-key imports show their matching mainnet public key and addresses.
- Recovery-word review and explicit backup confirmation for newly created wallets.
- AES-GCM protection derived from the confirmed passcode and this-device-only Keychain persistence, followed by a success screen.

PSBT transport, transaction decoding, human transaction review, policy enforcement, signature production, wallet unlocking, migration, backup restoration, and release distribution are not implemented yet. There is no production release or independently audited signer. Do not enter real secrets into this project or use an unofficial artifact to secure real funds.

## Debug-only network override

Debug builds expose a Wi-Fi icon in the native app bar on the opening screen and throughout setup for development on connected devices. Enabling it requires an explicit destructive warning, changes it to a persistent red Wi-Fi-disabled symbol, and makes every setup decision receive an effective offline state regardless of the actual Wi-Fi or other network path. Disabling it immediately restores the real monitor and interrupts an active secret flow when a connection is present.

The control, state, and bypass branch are guarded by `#if DEBUG`; Release builds always use the real `NWPathMonitor` result. The override is never persisted or enabled by default. Never create or enter a real wallet while using it.

## Visual identity

<img src="Brand/GlaceSignerBrandMark.svg" alt="Glace Signer brand mark: a black open geometric G without a background" width="144">

Glace Signer uses exactly the same background-free, open geometric `G` as the watch-only app, making the pair immediately recognizable as one Bitcoin wallet. Its mark is black, while the watch-only mark is blue. Both applications intentionally stay in native iOS light appearance. The background-free [brand-mark master](Brand/GlaceSignerBrandMark.svg) is rendered directly in onboarding, while the opaque [app-icon master](Brand/GlaceSignerAppIcon.svg) satisfies the iOS application-icon requirements.

## How the two apps complement each other

The planned workflow preserves an explicit air gap:

1. Glace imports public wallet data, monitors Bitcoin, and prepares an unsigned Partially Signed Bitcoin Transaction (PSBT).
2. The unsigned PSBT is transferred manually to Glace Signer without transferring any seed phrase or private key.
3. Glace Signer independently displays the transaction for human review and signs it while offline.
4. Only the signed result is returned to Glace, which verifies it before any network broadcast.

Interoperability will use standardized Bitcoin PSBT data, with BIP174 and BIP370 compatibility evaluated and tested before implementation. The air-gap encoding and transport have not been selected or implemented yet; neither app currently exchanges transaction data.

## Core principles

- Bitcoin mainnet only, with comprehensive support planned for established address, script, key, wallet-policy, and derivation standards, including BIP32, BIP39, BIP44, BIP49, BIP84, and BIP86. Testnet, signet, and regtest data are outside the product scope.
- A strict offline boundary: the signer does not monitor balances, contact Bitcoin peers or services, or broadcast transactions.
- Native iOS 26 interfaces built only with Apple UI frameworks and current Swift APIs. Reviewed external packages may be used only below the interface for Bitcoin or security-critical core work.
- Localization-ready UI with English source strings first, native LTR/RTL behavior, adaptive iPhone/iPad layouts, Dynamic Type, and a deliberate native light-only appearance.
- Apple system typography throughout, with the native rounded San Francisco design reserved for titles and headings.
- Deliberate, restrained interaction design with meaningful animation, accessibility, and semantic haptic feedback.
- Public source history and a verifiable release process designed to connect future binaries to exact source revisions, build inputs, signatures, provenance, and checksums.

## Development build

The current project is generated and verified with:

- Xcode 26.6 (`17F113`)
- Apple Swift 6.3.3
- XcodeGen 2.45.4
- iOS 26.0 deployment target

The reproducible core-test manifest and Xcode project pin these non-UI dependencies exactly:

- `swift-secp256k1` 0.23.2 for secp256k1 public/private-key validation, BIP32 child derivation, and Taproot key tweaks.
- `RIPEMD160` 1.0.0 for Bitcoin HASH160 construction.

Neither dependency provides app UI or a runtime network client. Both `Package.resolved` files record the resolved upstream revisions. The bundled 2,048-word English BIP39 list comes from the public Bitcoin BIPs repository at commit `60f5b33b0a7be3cf09b933d97b78071d684db7d1`.

Run the deterministic Bitcoin and encrypted-vault checks without Simulator:

```sh
swift test
swift test -c release
```

Generate the Xcode project and compile the app plus its iOS unit-test target for a generic device:

```sh
xcodegen generate --spec project.yml
xcodebuild -project GlaceSigner.xcodeproj -scheme GlaceSigner -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

The host suite currently executes thirteen focused checks covering exact passcode confirmation; published BIP39, BIP32, BIP86, HASH160, and legacy-address vectors; malformed mnemonic and Base58 rejection; ambiguous account-key standards; explicit testnet WIF and extended-key rejection; wrong-passcode authenticated-decryption failure; and the Debug/Release network-isolation policy. The Xcode command performs a compile-only generic iOS build without booting Simulator. Runtime layout and interaction validation remains with the project owner, and haptic timing must be checked on supported physical hardware before release.

## Security

Glace Signer is intended for a device kept permanently disconnected from Wi-Fi, cellular, Bluetooth, wired adapters, and other communication paths before any signing secret is created or imported. The current `NWPathMonitor` gate detects active network paths and immediately clears in-memory setup state if a path reappears before completion. Public iOS APIs cannot prove that every radio is physically disabled or detect every possible side channel, so the user and release process must still enforce and verify Airplane Mode, Wi-Fi, Bluetooth, accessories, and the surrounding environment.

The current vault uses PBKDF2-HMAC-SHA512 with 210,000 rounds, a random salt, AES-GCM authenticated encryption, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It does not store the passcode. Swift `String` and `Data` do not provide a complete guarantee that every temporary secret copy is immediately zeroized, and this implementation and its six-digit passcode threat model have not received an independent security audit. The source contains no intentional secret logging or secret clipboard action.

Published test vectors and a clean build are evidence for the tested behavior, not proof that secret lifecycle, dependency code, the toolchain, the device, or the final signed binary is safe for funds. A future release process must add independent review, reproducible unsigned-artifact comparison, entitlement and signature inspection, checksums, provenance, and precise documentation of Apple-controlled transformations.

No software can honestly guarantee absolute safety. Future Glace Signer releases must state exactly what was verified, publish the available verification evidence, and disclose residual risks and any Apple-controlled build or distribution steps that cannot be reproduced independently.
