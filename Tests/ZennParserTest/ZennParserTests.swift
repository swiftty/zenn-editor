import XCTest
@testable import ZennParser

private func XCTAssertEqual<T, U>(
    _ input: (T, U), _ expected: (T, U),
    file: StaticString = #filePath,
    line: UInt = #line
) where T: Equatable, U: Equatable {
    XCTAssertEqual(input.0, expected.0, file: file, line: line)
    XCTAssertEqual(input.1, expected.1, file: file, line: line)
}

final class ZennParserTests: XCTestCase {
    func test() throws {
        let input = """
         ### aa


        #######        bb
            c ##  dd
        """
        var parser = Parser(.init(input))

        func check(_ token: Lexer.Lexeme) -> (String, RawTokenKind) {
            (String(syntaxText: token.tokenText), token.tokenKind)
        }
        func next() -> (String, RawTokenKind) {
            check(parser.lexemes.advance())
        }

        XCTAssertEqual(check(parser.currentToken) , (" ", .space))
        XCTAssertEqual(next() , ("### ", .heading))
        XCTAssertEqual(next() , ("aa", .text))
        XCTAssertEqual(next() , ("\n\n\n", .linebreak))
        XCTAssertEqual(next() , ("#######", .text))
        XCTAssertEqual(next() , ("        ", .space))
        XCTAssertEqual(next() , ("bb", .text))
        XCTAssertEqual(next() , ("\n", .linebreak))
        XCTAssertEqual(next() , ("    ", .space))
        XCTAssertEqual(next() , ("c", .text))
        XCTAssertEqual(next() , (" ", .space))
        XCTAssertEqual(next() , ("##", .text))
        XCTAssertEqual(next() , ("  ", .space))
        XCTAssertEqual(next() , ("dd", .text))
        XCTAssertEqual(next() , ("", .eof))
    }
}
