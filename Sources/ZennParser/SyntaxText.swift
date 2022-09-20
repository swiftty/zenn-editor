import Foundation

public struct SyntaxText {
    public struct Element: Hashable {
        var rawValue: UInt8

        var isASCII: Bool {
            rawValue <= 127
        }
    }

    private enum Storage {
        class Root {
            let buffer: UnsafeBufferPointer<UInt8>

            init(buffer: UnsafeBufferPointer<UInt8>) {
                self.buffer = buffer
            }

            deinit {
                buffer.deallocate()
            }
        }

        case string(Root)
        case buffer(UnsafeBufferPointer<UInt8>, parent: Root? = nil)

        var buffer: UnsafeBufferPointer<UInt8> {
            switch self {
            case .string(let root): return root.buffer
            case .buffer(let buffer, _): return buffer
            }
        }

        private var parent: Root? {
            switch self {
            case .string(let root): return root
            case .buffer: return nil
            }
        }

        init(string: String) {
            let utf8 = string.utf8
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: utf8.count)
            _ = buffer.initialize(from: utf8)
            self = .string(.init(buffer: .init(buffer)))
        }

        func new(offset: Int, count: Int) -> Self {
            .buffer(.init(start: buffer.baseAddress?.advanced(by: offset),
                          count: count),
                    parent: parent)
        }
    }

    private var buffer: UnsafeBufferPointer<UInt8> {
        storage.buffer
    }

    private var storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    private init(baseAddress: UnsafePointer<UInt8>?, count: Int) {
        assert(count == 0 || baseAddress != nil,
               "If count is not zero, base address must be exist")
        self.init(storage: .buffer(.init(start: baseAddress, count: count)))
    }

    public init() {
        self.init(baseAddress: nil, count: 0)
    }

    public init(_ string: StaticString) {
        self.init(baseAddress: string.utf8Start, count: string.utf8CodeUnitCount)
    }

    public init(_ string: String) {
        self.init(storage: .init(string: string))
    }

    public init(_ string: SyntaxText, offset: Int = 0, count: Int) {
        self.init(storage: string.storage.new(offset: offset, count: count))
    }

    public init(rebasing slice: SubSequence) {
        self.init(slice.base, offset: slice.startIndex, count: slice.count)
    }

    public var count: Int {
        buffer.count
    }

    public var isEmpty: Bool {
        buffer.isEmpty
    }

    var pointer: UnsafePointer<UInt8> {
        buffer.baseAddress!
    }

    func distance(to other: Self) -> Int {
        pointer.distance(to: other.pointer)
    }

    mutating func advance() -> Element? {
        var new = self[...]
        guard let c = new.popFirst() else { return nil }
        self = .init(rebasing: new)
        return c
    }

    mutating func advanceAsUnicodeScalar() -> (Unicode.Scalar, last: Element)? {
        var new = self[...]
        guard let c = new.popFirst() else { return nil }
        let len = c.isASCII ? 1 : (~c.rawValue).leadingZeroBitCount
        var result: (Unicode.Scalar, last: Element)?
        switch len {
        case 1: result = (.init(c.rawValue), c)
        case 2: result = decodeUTF8(c, new.popFirst())
        case 3: result = decodeUTF8(c, new.popFirst(), new.popFirst())
        case 4: result = decodeUTF8(c, new.popFirst(), new.popFirst(), new.popFirst())
        default: fatalError()
        }

        if result != nil {
            self = .init(rebasing: new)
        }
        return result
    }
}

// MARK: -
extension SyntaxText: RandomAccessCollection {
    public typealias Index = Int
    public typealias SubSequence = Slice<SyntaxText>

    public var startIndex: Int { buffer.startIndex }
    public var endIndex: Int { buffer.endIndex }

    public subscript(position: Int) -> Element {
        .init(rawValue: buffer[position])
    }
}

// MARK: -
extension SyntaxText: CustomDebugStringConvertible {
    public var debugDescription: String {
        #"SyntaxText("\#(String(syntaxText: self))")"#
    }

    fileprivate var asString: String {
        if isEmpty {
            return ""
        } else if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            return .init(unsafeUninitializedCapacity: count) { strBuffer in
                strBuffer.initialize(from: buffer).1
            }
        } else {
            return buffer.withMemoryRebound(to: CChar.self) {
                $0.baseAddress.map(String.init(cString:))
            } ?? ""
        }
    }
}

extension String {
    public init(syntaxText: SyntaxText) {
        self = syntaxText.asString
    }
}

extension SyntaxText.Element {
    init(ascii: Unicode.Scalar) {
        self.init(rawValue: UInt8(ascii: ascii))
    }

    static func == (lhs: Self, rhs: Unicode.Scalar) -> Bool {
        lhs == .init(ascii: rhs)
    }
}

func ~= (lhs: Unicode.Scalar, rhs: SyntaxText.Element?) -> Bool {
    guard let rhs else { return false }
    return rhs == lhs
}

// MARK: -
extension SyntaxText: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.buffer.count == rhs.buffer.count else { return false }

        guard let lBase = lhs.buffer.baseAddress, let rBase = rhs.buffer.baseAddress else {
            // If either `baseAddress` is `nil`, both are empty so returns `true`.
            return true
        }
        // We don't do `lhs.baseAddress == rhs.baseAddress` shortcut, because in
        // SwiftSyntax use cases, comparing the same SyntaxText instances is
        // extremely rare, and checking it causes extra branch.
        // The most common usage is comparing parsed text with a static text e.g.
        // `token.text == "func"`. In such cases `compareMemory`(`memcmp`) is
        // optimzed to a `cmp` or similar opcode if either operand is a short static
        // text. So the same-baseAddress shortcut doesn't give us a huge performance
        // boost even if they actually refer the same memory.
        return compareMemory(lBase, rBase, lhs.count)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bytes: .init(buffer))
    }
}

// MARK: - private
private func compareMemory(
  _ s1: UnsafePointer<UInt8>, _ s2: UnsafePointer<UInt8>, _ count: Int
) -> Bool {
    assert(count >= 0)
#if canImport(Darwin)
    return Darwin.memcmp(s1, s2, count) == 0
#elseif canImport(Glibc)
    return Glibc.memcmp(s1, s2, count) == 0
#else
    return UnsafeBufferPointer(start: s1, count: count)
        .elementsEqual(UnsafeBufferPointer(start: s2, count: count))
#endif
}

private func decodeUTF8(
    _ x: SyntaxText.Element,
    _ y: SyntaxText.Element?
) -> (Unicode.Scalar, last: SyntaxText.Element)? {
    guard let y else { return nil }
    let x = UInt32(x.rawValue)
    let value = ((x & 0b0001_1111) &<< 6) | _continuationPayload(y)
    return Unicode.Scalar(value).map { ($0, y) }
}

private func decodeUTF8(
    _ x: SyntaxText.Element,
    _ y: SyntaxText.Element?,
    _ z: SyntaxText.Element?
) -> (Unicode.Scalar, last: SyntaxText.Element)? {
    guard let y, let z else { return nil }
    let x = UInt32(x.rawValue)
    let value = ((x & 0b0000_1111) &<< 12)
              | (_continuationPayload(y) &<< 6)
              | _continuationPayload(z)
    return Unicode.Scalar(value).map { ($0, z) }
}

private func decodeUTF8(
    _ x: SyntaxText.Element,
    _ y: SyntaxText.Element?,
    _ z: SyntaxText.Element?,
    _ w: SyntaxText.Element?
) -> (Unicode.Scalar, last: SyntaxText.Element)? {
    guard let y, let z, let w else { return nil }
    let x = UInt32(x.rawValue)
    let value = ((x & 0b0000_1111) &<< 18)
              | (_continuationPayload(y) &<< 12)
              | (_continuationPayload(z) &<< 6)
              | _continuationPayload(w)
    return Unicode.Scalar(value).map { ($0, w) }
}

private func _continuationPayload(_ v: SyntaxText.Element) -> UInt32 {
    UInt32(v.rawValue & 0x3f)
}
