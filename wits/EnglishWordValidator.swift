import UIKit

enum EnglishWordValidator {
    static func isValidWord(_ word: String, length: Int? = nil, acceptedWords: Set<String> = []) -> Bool {
        let text = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        if let length, text.count != length { return false }
        guard text.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else { return false }
        if acceptedWords.contains(text) { return true }

        let checker = UITextChecker()
        let range = NSRange(location: 0, length: text.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: text,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en_US"
        )
        return misspelled.location == NSNotFound
    }
}
