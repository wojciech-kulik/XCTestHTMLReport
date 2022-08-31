import class Foundation.Bundle
import SwiftSoup
import XCTest

final class CliTests: XCTestCase {
    var testResultsUrl: URL? {
        Bundle.testBundle
            .url(forResource: "TestResults", withExtension: "xcresult")
    }

    func testNoArgs() throws {
        let (status, maybeStdOut, maybeStdErr) = try xchtmlreportCmd(args: [])

        XCTAssertEqual(status, 1)
        XCTAssertEqual(maybeStdErr?.isEmpty, true)
        let stdOut = try XCTUnwrap(maybeStdOut)
        XCTAssertContains(stdOut, "Error: Argument -r is required")
    }

    func testAttachmentsExist() throws {
        let testResultsUrl = try XCTUnwrap(testResultsUrl)
        let document = try parseReportDocument(xchtmlreportArgs: ["-r", testResultsUrl.path])
        let reportDir = testResultsUrl.deletingLastPathComponent()

        try XCTContext.runActivity(named: "Image attachments exist") { _ in
            let imgTags = try document.select("img.screenshot, img.screenshot-flow")
            XCTAssertFalse(imgTags.isEmpty())

            try imgTags.forEach { img in
                let src = try img.attr("src")
                XCTAssertContains(src, ".xcresult/")
                let attachmentUrl = try XCTUnwrap(URL(string: src, relativeTo: reportDir))
                XCTAssertNoThrow(try attachmentUrl.checkResourceIsReachable())
            }
        }

        try XCTContext.runActivity(named: "Other attachments exist", block: { _ in
            let spanTags = try document.select("span.icon.preview-icon")
            XCTAssertFalse(spanTags.isEmpty())

            try spanTags.forEach { span in
                let onClick = try span.attr("onclick")
                guard onClick.starts(with: "showText") else {
                    return
                }

                let data = try span.attr("data")
                XCTAssertContains(data, ".xcresult/")
                let attachmentUrl = try XCTUnwrap(URL(string: data, relativeTo: reportDir))
                XCTAssertNoThrow(try attachmentUrl.checkResourceIsReachable())
            }
        })
    }
}