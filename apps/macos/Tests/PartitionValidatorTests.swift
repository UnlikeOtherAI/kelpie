import XCTest
@testable import Kelpie

/// Mirrors `packages/shared/tests/partition.test.ts`. The two validators must
/// agree on the verdict *and* on the reason, so these cases are deliberately
/// the same ones the TypeScript suite asserts.
final class PartitionValidatorTests: XCTestCase {
    // MARK: - Accepted

    func testAcceptsOrdinaryIdentifiers() {
        for value in ["a", "1", "_1", "sam.eng-lead", "morgan.product", "A-B_C.D", "..a"] {
            XCTAssertNil(PartitionValidator.validate(value), "expected \"\(value)\" to be valid")
            XCTAssertTrue(PartitionValidator.isValid(value))
        }
    }

    func testAcceptsStringsThatMerelyResembleReservedOnes() {
        for value in ["Default1", "defaults", "default-sam", "sam.default", "ephemeral", "ephemeralx-thing"] {
            XCTAssertNil(PartitionValidator.validate(value), "expected \"\(value)\" to be valid")
        }
    }

    func testAcceptsExactlyMaxLength() {
        XCTAssertNil(PartitionValidator.validate(String(repeating: "a", count: PartitionValidator.maxLength)))
    }

    func testAcceptsWhenOnlyTheLastCharacterIsAlphanumeric() {
        let value = String(repeating: ".", count: PartitionValidator.maxLength - 1) + "z"
        XCTAssertNil(PartitionValidator.validate(value))
    }

    // MARK: - Charset and length

    func testRejectsEmptyString() {
        XCTAssertEqual(PartitionValidator.validate(""), PartitionValidator.Failure.charsetOrLength)
    }

    func testRejectsOneOverMaxLength() {
        let value = String(repeating: "a", count: PartitionValidator.maxLength + 1)
        XCTAssertEqual(PartitionValidator.validate(value), PartitionValidator.Failure.charsetOrLength)
    }

    func testRejectsDisallowedASCII() {
        for value in ["sam eng", "sam/eng", "sam\\eng", "sam:eng", "sam@eng", "sam%2e", "sam\neng", "sam\tent"] {
            XCTAssertEqual(PartitionValidator.validate(value), PartitionValidator.Failure.charsetOrLength, "expected \"\(value)\" rejected")
        }
    }

    func testRejectsNonASCII() {
        for value in ["caf\u{00e9}", "sam-\u{1F642}", "\u{30b5}\u{30e0}", "sam\u{0301}", "\u{ff11}23"] {
            XCTAssertEqual(PartitionValidator.validate(value), PartitionValidator.Failure.charsetOrLength, "expected \"\(value)\" rejected")
        }
    }

    // MARK: - Alphanumeric requirement

    func testRejectsStringsWithNoLetterOrDigit() {
        for value in ["-", "_", "-_.", "._-.", "..."] {
            XCTAssertEqual(PartitionValidator.validate(value), PartitionValidator.Failure.noAlnum, "expected \"\(value)\" rejected")
        }
    }

    func testRejectsMaxLengthOfDots() {
        let value = String(repeating: ".", count: PartitionValidator.maxLength)
        XCTAssertEqual(PartitionValidator.validate(value), PartitionValidator.Failure.noAlnum)
    }

    // MARK: - Reserved words

    func testRejectsDefaultCaseInsensitively() {
        for value in ["default", "Default", "DEFAULT", "DeFaUlT"] {
            XCTAssertEqual(PartitionValidator.validate(value), PartitionValidator.Failure.reserved, "expected \"\(value)\" rejected")
        }
    }

    func testRejectsTraversalNamesViaTheAlphanumericRule() {
        // The alphanumeric check runs before the reserved-word list, so these
        // report `.noAlnum`. The list still carries them so the rule survives
        // any future charset change. The TypeScript validator does the same.
        XCTAssertEqual(PartitionValidator.validate("."), PartitionValidator.Failure.noAlnum)
        XCTAssertEqual(PartitionValidator.validate(".."), PartitionValidator.Failure.noAlnum)
        XCTAssertFalse(PartitionValidator.isValid("."))
        XCTAssertFalse(PartitionValidator.isValid(".."))
    }

    // MARK: - Reserved prefix

    func testRejectsReservedPrefix() {
        XCTAssertEqual(PartitionValidator.validate("ephemeral-sam"), PartitionValidator.Failure.reservedPrefix)
        XCTAssertEqual(PartitionValidator.validate(PartitionValidator.reservedPrefix), PartitionValidator.Failure.reservedPrefix)
    }

    func testReservedPrefixIsCaseSensitive() {
        // Android only ever writes the lowercase prefix, and every platform
        // mirror compares case-sensitively. Keep them identical.
        XCTAssertNil(PartitionValidator.validate("Ephemeral-sam"))
        XCTAssertNil(PartitionValidator.validate("EPHEMERAL-sam"))
    }

    func testReservedPrefixOnlyMattersAtTheStart() {
        XCTAssertNil(PartitionValidator.validate("sam-ephemeral-1"))
    }

    // MARK: - Ordering

    func testCharsetIsReportedBeforeReserved() {
        let value = "default" + String(repeating: "x", count: PartitionValidator.maxLength)
        XCTAssertEqual(PartitionValidator.validate(value), PartitionValidator.Failure.charsetOrLength)
    }

    // MARK: - Reason strings

    func testFailureRawValuesMatchTheSharedContract() {
        XCTAssertEqual(PartitionValidator.Failure.charsetOrLength.rawValue, "charset-or-length")
        XCTAssertEqual(PartitionValidator.Failure.noAlnum.rawValue, "no-alnum")
        XCTAssertEqual(PartitionValidator.Failure.reserved.rawValue, "reserved")
        XCTAssertEqual(PartitionValidator.Failure.reservedPrefix.rawValue, "reserved-prefix")
    }

    func testEveryFailureHasAMessage() {
        for failure in [
            PartitionValidator.Failure.charsetOrLength,
            .noAlnum,
            .reserved,
            .reservedPrefix
        ] {
            XCTAssertFalse(failure.message.isEmpty)
        }
    }

    func testBoundsMatchTheSharedContract() {
        XCTAssertEqual(PartitionValidator.maxLength, 128)
        XCTAssertEqual(PartitionValidator.maxNameLength, 200)
        XCTAssertEqual(PartitionValidator.reservedPrefix, "ephemeral-")
    }
}
