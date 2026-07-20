import Foundation
import XCTest
import JxlCoder

final class JpegTranscodingTests: XCTestCase {
    func testOriginalAPIFunctionReferencesRemainAvailable() throws {
        let transcode: (Data) throws -> Data = JXLCoder.transcode
        let inverse: (Data) throws -> Data = JXLCoder.inverse

        let jxl = try transcode(Self.jpegFixture)
        let reconstructed = try inverse(jxl)

        XCTAssertEqual(reconstructed, Self.jpegFixture)
    }

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

    func testReconstructionGrowsOutputBuffer() throws {
        let jpeg = Self.jpegFixtureWithCompressibleMetadata

        let jxl = try JXLCoder.transcode(
            jpegData: jpeg,
            effort: 7,
            threads: 1
        )
        XCTAssertGreaterThan(
            jpeg.count,
            max(jxl.count * 2, 4096),
            "fixture must exceed the reconstruction buffer's initial capacity"
        )

        let reconstructed = try JXLCoder.inverse(jxlData: jxl, threads: 1)
        XCTAssertEqual(reconstructed, jpeg)
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
            try JXLCoder.transcode(
                jpegData: Data([0, 1, 2]),
                effort: 7,
                threads: 1
            )
        )
        XCTAssertThrowsError(
            try JXLCoder.inverse(jxlData: Data([0, 1, 2]), threads: 1)
        )
    }

    private static let jpegFixtureWithCompressibleMetadata: Data = {
        let commentPayloadLength = 60_000
        let commentSegmentLength = commentPayloadLength + 2
        var jpeg = Data([0xFF, 0xD8])

        for _ in 0..<4 {
            jpeg.append(contentsOf: [
                0xFF,
                0xFE,
                UInt8(commentSegmentLength >> 8),
                UInt8(commentSegmentLength & 0xFF),
            ])
            jpeg.append(Data(repeating: 0, count: commentPayloadLength))
        }
        jpeg.append(jpegFixture.dropFirst(2))
        return jpeg
    }()

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
