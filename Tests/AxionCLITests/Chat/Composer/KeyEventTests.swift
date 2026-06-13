import Darwin
import Foundation
import Testing
@testable import AxionCLI

@Suite("KeyEvent")
struct KeyEventTests {

    @Test("printable 相等性")
    func printableEquality() {
        #expect(KeyEvent.printable("a") == KeyEvent.printable("a"))
        #expect(KeyEvent.printable("a") != KeyEvent.printable("b"))
    }

    @Test("ctrl 相等性")
    func ctrlEquality() {
        #expect(KeyEvent.ctrl("r") == KeyEvent.ctrl("r"))
        #expect(KeyEvent.ctrl("r") != KeyEvent.ctrl("g"))
    }

    @Test("unknown 相等性")
    func unknownEquality() {
        #expect(KeyEvent.unknown([0x1B, 0x5B]) == KeyEvent.unknown([0x1B, 0x5B]))
        #expect(KeyEvent.unknown([0x1B]) != KeyEvent.unknown([0x1B, 0x5B]))
    }

    @Test("不同 case 不等")
    func differentCasesNotEqual() {
        #expect(KeyEvent.enter != KeyEvent.escape)
        #expect(KeyEvent.up != KeyEvent.down)
        #expect(KeyEvent.bracketPasteStart != KeyEvent.bracketPasteEnd)
    }

    @Test("home/end 相等性")
    func homeEndEquality() {
        #expect(KeyEvent.home == KeyEvent.home)
        #expect(KeyEvent.end == KeyEvent.end)
        #expect(KeyEvent.home != KeyEvent.end)
        #expect(KeyEvent.home != KeyEvent.up)
        #expect(KeyEvent.end != KeyEvent.down)
    }
}

@Suite("KeyEventReader.utf8CharLength")
struct UTF8CharLengthTests {

    @Test("ASCII 字符 1 字节")
    func asciiOneByte() {
        #expect(KeyEventReader.utf8CharLength(0x41) == 1) // 'A'
        #expect(KeyEventReader.utf8CharLength(0x7E) == 1) // '~'
    }

    @Test("2 字节 UTF-8（0xC0-0xDF）")
    func twoByteUTF8() {
        #expect(KeyEventReader.utf8CharLength(0xC0) == 2)
        #expect(KeyEventReader.utf8CharLength(0xDF) == 2)
    }

    @Test("3 字节 UTF-8（0xE0-0xEF，中文在此范围）")
    func threeByteUTF8() {
        #expect(KeyEventReader.utf8CharLength(0xE4) == 3) // 中文字符首字节常见值
        #expect(KeyEventReader.utf8CharLength(0xEF) == 3)
    }

    @Test("4 字节 UTF-8（0xF0-0xF7，emoji 在此范围）")
    func fourByteUTF8() {
        #expect(KeyEventReader.utf8CharLength(0xF0) == 4)
        #expect(KeyEventReader.utf8CharLength(0xF4) == 4)
    }
}

@Suite("KeyEventReader escape parsing")
struct KeyEventReaderEscapeParsingTests {
    @Test("standalone Esc returns escape without waiting for another byte")
    func standaloneEscapeReturnsWithoutWaiting() throws {
        var fds = [Int32](repeating: 0, count: 2)
        #expect(pipe(&fds) == 0)
        defer {
            close(fds[0])
            close(fds[1])
        }

        var escape: UInt8 = 0x1B
        #expect(write(fds[1], &escape, 1) == 1)

        let reader = KeyEventReader(original: termios(), inputFD: fds[0], storedTermios: false)
        let start = Date()
        #expect(reader.readNext() == .escape)
        #expect(Date().timeIntervalSince(start) < 0.2)
    }

    @Test("CSI arrow sequence still parses as directional key")
    func csiArrowSequenceParsesAsDirection() throws {
        var fds = [Int32](repeating: 0, count: 2)
        #expect(pipe(&fds) == 0)
        defer {
            close(fds[0])
            close(fds[1])
        }

        let bytes: [UInt8] = [0x1B, 0x5B, 0x41]
        let bytesWritten = bytes.withUnsafeBytes { buffer in
            write(fds[1], buffer.baseAddress, buffer.count)
        }
        #expect(bytesWritten == bytes.count)

        let reader = KeyEventReader(original: termios(), inputFD: fds[0], storedTermios: false)
        #expect(reader.readNext() == .up)
    }
}
