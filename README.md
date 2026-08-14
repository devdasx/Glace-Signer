# Glace Signer: Offline Bitcoin Signer - BTC

Glace Signer is the offline signing half of a two-application, Bitcoin-only wallet for native iOS. It is designed for a separate iPhone or iPad that remains disconnected while importing protected signing material, reviewing transactions, and producing Bitcoin signatures.

Its independent companion is [Glace: Bitcoin Wallet - BTC](https://github.com/devdasx/Glace), the watch-only app that handles public wallet data and future network activity without ever receiving a seed phrase or private key. The repositories, application targets, bundle identifiers, and security responsibilities remain independent.

## Project status

Glace Signer is in early design and development. This repository currently contains only its native onboarding experience. Recovery phrase, WIF, raw private-key, extended-private-key, descriptor, secure-storage, PSBT transport, transaction review, and signing features have not been implemented yet. No release or usable signer is available. Do not enter real secrets into this project or use any unofficial artifact to secure real funds.

## Visual identity

<img src="Brand/GlaceSignerBrandMark.svg" alt="Glace Signer brand mark: a black open geometric G without a background" width="144">

Glace Signer uses exactly the same background-free, open geometric `G` as the watch-only app, making the pair immediately recognizable as one Bitcoin wallet. Its mark is black in light appearance and follows the system foreground color in dark appearance for legibility, while the watch-only mark remains blue. The background-free [brand-mark master](Brand/GlaceSignerBrandMark.svg) is rendered directly in onboarding, while the opaque [app-icon master](Brand/GlaceSignerAppIcon.svg) satisfies the iOS application-icon requirements.

## How the two apps complement each other

The planned workflow preserves an explicit air gap:

1. Glace imports public wallet data, monitors Bitcoin, and prepares an unsigned Partially Signed Bitcoin Transaction (PSBT).
2. The unsigned PSBT is transferred manually to Glace Signer without transferring any seed phrase or private key.
3. Glace Signer independently displays the transaction for human review and signs it while offline.
4. Only the signed result is returned to Glace, which verifies it before any network broadcast.

Interoperability will use standardized Bitcoin PSBT data, with BIP174 and BIP370 compatibility evaluated and tested before implementation. The air-gap encoding and transport have not been selected or implemented yet; neither app currently exchanges transaction data.

## Core principles

- Bitcoin only, with comprehensive support planned for established address, script, key, wallet-policy, and derivation standards, including BIP32, BIP39, BIP44, BIP49, BIP84, and BIP86.
- A strict offline boundary: the signer does not monitor balances, contact Bitcoin peers or services, or broadcast transactions.
- Native iOS 26 interfaces built with current Apple frameworks and Swift APIs.
- Localization-ready UI with English source strings first, native LTR/RTL behavior, adaptive iPhone/iPad layouts, Dynamic Type, and complete light/dark appearance support.
- Deliberate, restrained interaction design with meaningful animation, accessibility, and semantic haptic feedback.
- Public source history and a verifiable release process designed to connect future binaries to exact source revisions, build inputs, signatures, provenance, and checksums.

## Development build

The current project is generated and verified with:

- Xcode 26.6 (`17F113`)
- Apple Swift 6.3.3
- XcodeGen 2.45.4
- iOS 26.0 deployment target

Generate and build the project from a clean checkout:

```sh
xcodegen generate --spec project.yml
xcodebuild -project GlaceSigner.xcodeproj -scheme GlaceSigner -destination 'generic/platform=iOS Simulator' build
```

The app currently has no third-party runtime dependencies and contains no networking implementation. Simulator builds verify compilation and layout behavior; the meaning and physical feel of haptic feedback must also be checked on supported hardware before release.

## Security

Glace Signer is intended for a device kept permanently disconnected from Wi-Fi, cellular, Bluetooth, and other communication paths before any signing secret is imported. iOS software cannot prove that every radio or physical channel is disabled, so the user and release process must enforce and verify the offline environment.

Future secret support is planned for applicable Bitcoin material such as BIP39 recovery phrases, WIF or valid raw private keys, and BIP32 extended private keys. Every format requires explicit validation, secure lifecycle design, published test vectors, independent review, and zero unintended network or logging exposure before it can be considered implemented.

No software can honestly guarantee absolute safety. Future Glace Signer releases must state exactly what was verified, publish the available verification evidence, and disclose residual risks and any Apple-controlled build or distribution steps that cannot be reproduced independently.
