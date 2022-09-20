import Foundation

public protocol LexicalTokenizer {
    var initialLetter: SyntaxText.Element? { get }
    var block: Bool { get }

    func lex(on cursor: inout Lexer.Cursor) -> RawTokenKind?
}

extension LexicalTokenizer {
    public var block: Bool { false }
}

public struct Lexer {
    public struct Lexeme {
        public var tokenKind: RawTokenKind
        public var isAtStartOfLine: Bool
        var start: SyntaxText
        public var leadingTriviaLength: Int
        public var textLength: Int
        public var trailingTriviaLength: Int

        public init(
            tokenKind: RawTokenKind,
            isAtStartOfLine: Bool,
            start: SyntaxText,
            leadingTriviaLength: Int,
            textLength: Int,
            trailingTriviaLength: Int
        ) {
            self.tokenKind = tokenKind
            self.isAtStartOfLine = isAtStartOfLine
            self.start = start
            self.leadingTriviaLength = leadingTriviaLength
            self.textLength = textLength
            self.trailingTriviaLength = trailingTriviaLength
        }

        public var tokenText: SyntaxText {
            .init(start, count: textLength)
        }
    }
}

extension Lexer {
    public struct LexemeSequence: IteratorProtocol {
        private var cursor: Cursor
        private var nextToken: Lexeme
        private var consumedFirstTokenAtLine = false

        fileprivate init(start: Cursor) {
            self.cursor = start
            self.nextToken = cursor.nextToken(with: false)
        }

        public mutating func next() -> Lexeme? {
            advance()
        }

        mutating func advance() -> Lexeme {
            defer {
                func test(_ t: RawTokenKind) -> Bool {
                    t == .linebreak || t == .space
                }

                nextToken = cursor.isAtEndOfFile
                    ? .empty(with: cursor)
                    : cursor.nextToken(with: consumedFirstTokenAtLine)
                consumedFirstTokenAtLine = nextToken.tokenKind == .linebreak
                    ? false
                    : consumedFirstTokenAtLine || test(nextToken.tokenKind)
            }
            return nextToken
        }

        func peek() -> Lexeme {
            nextToken
        }
    }

    public static func tokenize(_ input: SyntaxText) -> LexemeSequence {
        let start = Cursor(
            input: input,
            previous: .init(rawValue: .init(ascii: "\0")),
            tokenizers: [
                LinebreakTokenizer(letter: "\n"),
                LinebreakTokenizer(letter: "\r"),
                SpaceTokeninzer(),
                HeadingTokenizer()
            ]
        )
        return LexemeSequence(start: start)
    }
}

extension Lexer {
    public struct Cursor {
        var input: SyntaxText
        var previous: SyntaxText.Element
        var tokenizers: [SyntaxText.Element?: [any LexicalTokenizer]]

        init(
            input: SyntaxText,
            previous: SyntaxText.Element,
            tokenizers: [any LexicalTokenizer]
        ) {
            self.input = input
            self.previous = previous
            self.tokenizers = tokenizers.reduce(into: [:]) {
                $0[$1.initialLetter, default: []].append($1)
            }
        }

        func distance(to other: Self) -> Int {
            input.distance(to: other.input)
        }

        func peek(at offset: Int = 0) -> SyntaxText.Element {
            assert(!isAtEndOfFile)
            assert(offset >= 0)
            assert(offset < input.count)
            return input[offset]
        }

        var isAtEndOfFile: Bool {
            input.isEmpty
        }

        var isAtStartOfFile: Bool {
            previous == "\0" && !input.isEmpty
        }

        mutating func advance() -> SyntaxText.Element? {
            guard let c = input.advance() else { return nil }
            previous = c
            return c
        }

        mutating func advance(while predicate: (Unicode.Scalar) -> Bool) {
            var next = self
            while !next.isAtEndOfFile, let c = next.advanceAsUnicodeScalar(), predicate(c) {
                self = next
            }
        }

        private mutating func advanceAsUnicodeScalar() -> Unicode.Scalar? {
            guard let (s, c) = input.advanceAsUnicodeScalar() else { return nil }
            previous = c
            return s
        }
    }
}

extension Lexer.Cursor {
    mutating func nextToken(with consumedFirstTokenAtLine: Bool) -> Lexer.Lexeme {
        let start = self
        let kind = lex(with: consumedFirstTokenAtLine)

        let token = Lexer.Lexeme(
            tokenKind: kind,
            isAtStartOfLine: false,
            start: start.input,
            leadingTriviaLength: 0,
            textLength: start.distance(to: self),
            trailingTriviaLength: 0
        )

        return token
    }

    private mutating func lex(with consumedFirstTokenAtLine: Bool) -> RawTokenKind {
        if let kind = _lex(with: consumedFirstTokenAtLine) {
            return kind
        }

        func test(_ t: RawTokenKind?) -> Bool {
            t == nil || t == .text
        }

        var start = self
        while test(start._lex(with: consumedFirstTokenAtLine)) {
            self = start
        }
        return .text
    }

    private mutating func _lex(with consumedFirstTokenAtLine: Bool) -> RawTokenKind? {
        guard let char = advance() else { return .eof }

        for tokenizer in tokenizers[char] ?? tokenizers[nil] ?? [] {
            if tokenizer.block && consumedFirstTokenAtLine {
                continue
            }
            if let kind = tokenizer.lex(on: &self) {
                return kind
            }
        }
        return nil
    }
}

// MARK: -
private extension Lexer.Lexeme {
    static func empty(with cursor: Lexer.Cursor) -> Self {
        self.init(
            tokenKind: .eof,
            isAtStartOfLine: false,
            start: cursor.input,
            leadingTriviaLength: 0,
            textLength: 0,
            trailingTriviaLength: 0
        )
    }
}
