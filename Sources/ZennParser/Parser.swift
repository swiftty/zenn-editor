import Foundation

extension Parser {
    public static func parse(
        source: String
    ) throws {
//        var parser = Parser(.init(source))
    }
}

public struct Parser {

    var lexemes: Lexer.LexemeSequence
    var currentToken: Lexer.Lexeme

    init(_ input: SyntaxText) {
        lexemes = Lexer.tokenize(input)
        currentToken = lexemes.advance()
    }
}
