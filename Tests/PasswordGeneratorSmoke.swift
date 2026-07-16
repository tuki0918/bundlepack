import Foundation

@main
enum PasswordGeneratorSmoke {
    private static let digits = Set("23456789")
    private static let symbols = Set("!@#$%^&*+-_=?.")
    private static let uppercase = Set("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let lowercase = Set("abcdefghijkmnopqrstuvwxyz")

    static func main() throws {
        try verify(totalLength: 16, digitCount: 4, symbolCount: 4)
        try verify(totalLength: 12, digitCount: 0, symbolCount: 0)
        try verify(totalLength: 128, digitCount: 40, symbolCount: 40)

        let clamped = BundlePackPasswordGenerator.generate(
            totalLength: 8,
            digitCount: 99,
            symbolCount: 99
        )
        try require(clamped.count == 12, "The minimum generated length was not enforced.")
        try require(clamped.contains(where: uppercase.contains), "The clamped password has no uppercase letter.")
        try require(clamped.contains(where: lowercase.contains), "The clamped password has no lowercase letter.")

        print("PASS: password generator lengths, character counts, and letter requirements")
    }

    private static func verify(totalLength: Int, digitCount: Int, symbolCount: Int) throws {
        for _ in 0..<50 {
            let password = BundlePackPasswordGenerator.generate(
                totalLength: totalLength,
                digitCount: digitCount,
                symbolCount: symbolCount
            )
            try require(password.count == totalLength, "Generated length does not match (totalLength).")
            try require(password.filter(digits.contains).count == digitCount, "Digit count does not match (digitCount).")
            try require(password.filter(symbols.contains).count == symbolCount, "Symbol count does not match (symbolCount).")
            try require(password.contains(where: uppercase.contains), "The password has no uppercase letter.")
            try require(password.contains(where: lowercase.contains), "The password has no lowercase letter.")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestError(message) }
    }

    private struct TestError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
