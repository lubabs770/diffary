import Testing
@testable import DiffaryCore

@Suite struct ZoomTests {
    @Test func keys() {
        #expect(Zoom.step(characters: "=", command: true, otherModifiers: false) == .bigger)
        #expect(Zoom.step(characters: "+", command: true, otherModifiers: true) == .bigger)  // Cmd-Shift-=
        #expect(Zoom.step(characters: "-", command: true, otherModifiers: false) == .smaller)
        #expect(Zoom.step(characters: "0", command: true, otherModifiers: false) == .reset)
        #expect(Zoom.step(characters: "=", command: false, otherModifiers: false) == nil)
        #expect(Zoom.step(characters: "-", command: true, otherModifiers: true) == nil)
        #expect(Zoom.step(characters: "k", command: true, otherModifiers: false) == nil)
    }

    @Test func offsetClampsToValidSizes() {
        #expect(Zoom.apply(.bigger, offset: 0, base: 13) == 1)
        #expect(Zoom.apply(.smaller, offset: 0, base: 13) == -1)
        #expect(Zoom.apply(.reset, offset: 5, base: 13) == 0)
        #expect(Zoom.apply(.bigger, offset: 59, base: 13) == 59)   // 72pt max
        #expect(Zoom.apply(.smaller, offset: -7, base: 13) == -7)  // 6pt min
    }
}
