import Foundation

struct PasscodeConfirmation: Hashable, Sendable {
    private let id = UUID()
    private let expectedPasscode: String

    init(expectedPasscode: String) {
        self.expectedPasscode = expectedPasscode
    }

    func matches(_ enteredPasscode: String) -> Bool {
        enteredPasscode == expectedPasscode
    }

    static func == (
        lhs: PasscodeConfirmation,
        rhs: PasscodeConfirmation
    ) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
