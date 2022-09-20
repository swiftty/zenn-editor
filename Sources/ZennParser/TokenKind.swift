import Foundation

public enum RawTokenKind: Equatable {
    case eof
    case linebreak
    case space

    case heading
    case text
}
