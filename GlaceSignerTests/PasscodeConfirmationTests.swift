import Testing
#if SWIFT_PACKAGE
@testable import GlaceSignerCore
#else
@testable import GlaceSigner
#endif

struct PasscodeConfirmationTests {
    @Test
    func retainsTheExactPasscodeSnapshotIncludingLeadingZeroes() {
        var pendingPasscode = "012345"
        let confirmation = PasscodeConfirmation(
            expectedPasscode: pendingPasscode
        )
        pendingPasscode = "999999"

        #expect(confirmation.matches("012345"))
        #expect(!confirmation.matches(pendingPasscode))
    }

    @Test
    func rejectsDifferentAndEmptyPasscodes() {
        let confirmation = PasscodeConfirmation(
            expectedPasscode: "123456"
        )

        #expect(!confirmation.matches("123457"))
        #expect(!confirmation.matches(""))
    }
}
