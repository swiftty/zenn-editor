import Foundation

struct LinebreakTokenizer: LexicalTokenizer {
    var initialLetter: SyntaxText.Element? { .init(ascii: letter) }

    private let letter: Unicode.Scalar

    init(letter: Unicode.Scalar) {
        self.letter = letter
    }

    func lex(on cursor: inout Lexer.Cursor) -> RawTokenKind? {
        assert(cursor.previous == letter)
        cursor.advance(while: { $0 == letter })
        return .linebreak
    }
}

struct SpaceTokeninzer: LexicalTokenizer {
    var initialLetter: SyntaxText.Element? { .init(ascii: " ") }

    func lex(on cursor: inout Lexer.Cursor) -> RawTokenKind? {
        assert(cursor.previous == " ")
        cursor.advance(while: { $0 == " " })
        return .space
    }
}

struct HeadingTokenizer: LexicalTokenizer {
    var initialLetter: SyntaxText.Element? { .init(ascii: "#") }
    var block: Bool { true }

    func lex(on cursor: inout Lexer.Cursor) -> RawTokenKind? {
        assert(cursor.previous == "#")

        var clone = cursor
        var length = 1
        defer { cursor = clone }

        clone.advance(while: { $0 == "#" })
        length += cursor.distance(to: clone)

        if length > 6 {
            return nil
        }

        clone.advance(while: { $0 == " " })

        return .heading
    }
}

struct DividerTokenizer: LexicalTokenizer {
    var initialLetter: SyntaxText.Element? { .init(ascii: "-") }
    var block: Bool { true }

    func lex(on cursor: inout Lexer.Cursor) -> RawTokenKind? {
        assert(cursor.previous == "-")

        var clone = cursor
        var length = 1

        clone.advance(while: { $0 == "-" })
        length += cursor.distance(to: clone)
        cursor = clone

        if length < 3 {
            return nil
        }

        clone.advance(while: { $0 == " " })
        cursor = clone
        guard clone.advance()?.isNewline ?? false else {
            return nil
        }

        return .divider
    }
}

extension SyntaxText.Element {
    var isEmptyElement: Bool {
        self == " " || self == "\0" || isNewline
    }

    var isNewline: Bool {
        self == "\n" || self == "\r"
    }
}
