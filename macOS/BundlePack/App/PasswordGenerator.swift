import Foundation

enum BundlePackPasswordGenerator {
    private static let uppercaseLetters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let lowercaseLetters = Array("abcdefghijkmnopqrstuvwxyz")
    private static let digits = Array("23456789")
    private static let symbols = Array("!@#$%^&*+-_=?.")

    static func generate(totalLength: Int, digitCount: Int, symbolCount: Int) -> String {
        let length = min(max(12, totalLength), 128)
        let digitsToGenerate = min(max(0, digitCount), length - 2)
        let symbolsToGenerate = min(max(0, symbolCount), length - digitsToGenerate - 2)
        let letterCount = length - digitsToGenerate - symbolsToGenerate
        var generator = SystemRandomNumberGenerator()
        var characters: [Character] = [
            uppercaseLetters.randomElement(using: &generator)!,
            lowercaseLetters.randomElement(using: &generator)!
        ]

        let allLetters = uppercaseLetters + lowercaseLetters
        characters.append(contentsOf: (0..<max(0, letterCount - 2)).map { _ in
            allLetters.randomElement(using: &generator)!
        })
        characters.append(contentsOf: (0..<digitsToGenerate).map { _ in
            digits.randomElement(using: &generator)!
        })
        characters.append(contentsOf: (0..<symbolsToGenerate).map { _ in
            symbols.randomElement(using: &generator)!
        })
        characters.shuffle(using: &generator)
        return String(characters)
    }
}
