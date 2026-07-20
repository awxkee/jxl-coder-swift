import Foundation
import XCTest
import JxlCoder

final class JpegTranscodingTests: XCTestCase {
    func testDefaultAPIReconstructsOriginalJPEG() throws {
        let jpeg = Self.jpegFixture

        let jxl = try JXLCoder.transcode(jpegData: jpeg)
        let reconstructed = try JXLCoder.inverse(jxlData: jxl)

        XCTAssertFalse(jxl.isEmpty)
        XCTAssertEqual(reconstructed, jpeg)
    }

    func testEffortAndThreadOptionsReconstructOriginalJPEG() throws {
        let jpeg = Self.jpegFixture

        for effort in [1, 7, 9] {
            let jxl = try JXLCoder.transcode(
                jpegData: jpeg,
                effort: effort,
                threads: 1
            )
            let reconstructed = try JXLCoder.inverse(
                jxlData: jxl,
                threads: 1
            )
            XCTAssertEqual(reconstructed, jpeg, "effort \(effort)")
        }
    }

    func testConcurrentRoundTripsAreIndependent() {
        let finished = expectation(description: "concurrent round trips")
        finished.expectedFulfillmentCount = 4

        for effort in [1, 3, 7, 9] {
            DispatchQueue.global(qos: .userInitiated).async {
                defer { finished.fulfill() }
                do {
                    let jxl = try JXLCoder.transcode(
                        jpegData: Self.jpegFixture,
                        effort: effort,
                        threads: 2
                    )
                    let reconstructed = try JXLCoder.inverse(
                        jxlData: jxl,
                        threads: 2
                    )
                    XCTAssertEqual(reconstructed, Self.jpegFixture)
                } catch {
                    XCTFail("effort \(effort) failed: \(error)")
                }
            }
        }

        wait(for: [finished], timeout: 30)
    }

    func testInvalidOptionsAndInputThrow() throws {
        let jpeg = Self.jpegFixture

        XCTAssertThrowsError(
            try JXLCoder.transcode(jpegData: jpeg, effort: 0, threads: 1)
        )
        XCTAssertThrowsError(
            try JXLCoder.transcode(jpegData: jpeg, effort: 10, threads: 1)
        )
        XCTAssertThrowsError(
            try JXLCoder.transcode(jpegData: jpeg, effort: 7, threads: -1)
        )
        XCTAssertThrowsError(
            try JXLCoder.transcode(jpegData: jpeg, effort: 7, threads: 257)
        )
        XCTAssertThrowsError(
            try JXLCoder.inverse(jxlData: Data([0, 1, 2]), threads: 1)
        )
    }

    private static let jpegFixture = Data(
        base64Encoded: jpegBase64,
        options: .ignoreUnknownCharacters
    )!

    private static let jpegBase64 = """
    /9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwg
    IyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo
    KCgoKCgoKCgoKCgoKCj/wAARCAAIAAgDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAH/xAAXEAEAAwAAAAAAAAAA
    AAAAAAAAF2Oh/8QAFAEBAAAAAAAAAAAAAAAAAAAABf/EABkRAAIDAQAAAAAAAAAAAAAAAABRAwQUFf/aAAwDAQACEQMRAD8A
    sa04AF6VhiWGFH//2Q==
    """
}
