import Foundation

public enum L {
    public static let isSpanish: Bool = {
        guard let first = Locale.preferredLanguages.first?.lowercased() else { return false }
        return first.hasPrefix("es")
    }()

    public static func t(_ english: String, _ spanish: String) -> String {
        isSpanish ? spanish : english
    }
}
