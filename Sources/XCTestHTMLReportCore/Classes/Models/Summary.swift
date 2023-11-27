//
//  Summary.swift
//  XCTestHTMLReport
//
//  Created by Titouan van Belle on 21.07.17.
//  Copyright © 2017 Tito. All rights reserved.
//

import Foundation
import XCResultKit

public struct Summary {
    let runs: [Run]
    let resultFiles: [ResultFile]

    public enum RenderingMode {
        case inline
        case linking
    }

    public init(
        resultPaths: [String],
        renderingMode: RenderingMode,
        downsizeImagesEnabled: Bool,
        downsizeScaleFactor: CGFloat
    ) {
        var runs: [Run] = []
        var resultFiles: [ResultFile] = []

        for resultPath in resultPaths {
            Logger.step("Parsing \(resultPath)")
            let url = URL(fileURLWithPath: resultPath)
            let resultFile = ResultFile(url: url)
            resultFiles.append(resultFile)
            guard let invocationRecord = resultFile.getInvocationRecord() else {
                Logger.warning("Can't find invocation record for : \(resultPath)")
                break
            }
            let resultRuns = invocationRecord.actions.compactMap {
                Run(
                    action: $0,
                    file: resultFile,
                    renderingMode: renderingMode,
                    downsizeImagesEnabled: downsizeImagesEnabled,
                    downsizeScaleFactor: downsizeScaleFactor
                )
            }
            runs.append(contentsOf: resultRuns)
        }
        self.runs = runs
        self.resultFiles = resultFiles
    }

    /// Generate HTML report
    /// - Returns: Generated HTML report string
    public func generatedHtmlReport() -> String {
        html
    }

    /// Generate JUnit report
    /// - Returns: Generated JUnit XML report string
    public func generatedJunitReport(includeRunDestinationInfo: Bool) -> String {
        junit(includeRunDestinationInfo: includeRunDestinationInfo).xmlString
    }

    /// Delete all unattached files in runs
    public func deleteUnattachedFiles() {
        Logger.substep("Deleting unattached files..")
        var deletedFilesCount = 0
        deletedFilesCount = removeUnattachedFiles(runs: runs)
        Logger.substep("Deleted \(deletedFilesCount) unattached files")
    }

    public func generatedJsonReport() -> String {
        let jsonStrings: [String] = resultFiles.compactMap { resultFile in
            guard let jsonData = resultFile.exportJson() else {
                return nil
            }
            return String(data: jsonData, encoding: .utf8)
        }

        // TODO: The result files may be encoded directly as an array instead of concatenating raw output
        return "[\(jsonStrings.joined(separator: ","))]"
    }

    public struct FailedSnapshotTest: Codable {
        public let id: String
        public let mimeType: String?
        public let referenceImage: Data?
        public let failureImage: Data?
        public let diffImage: Data?
    }

    public struct TestResult: Codable {
        public let id: String
        public let filePath: String?
        public let lineNumber: Int?
        public let message: String?
        public let status: String
        public let duration: TimeInterval
    }

    public func getFailingTests() -> [TestResult] {
        getTests().filter { $0.status == "Failure" }
    }

    public func getTests() -> [TestResult] {
        runs.first?.allTests
            .compactMap { $0 as? TestCase }
            .map {
                TestResult(
                    id: $0.identifier,
                    filePath: $0.filePath,
                    lineNumber: $0.lineNumber,
                    message: $0.message,
                    status: $0.status.rawValue,
                    duration: $0.duration
                )
            } ?? []
    }

    public func getFailingSnapshotTests() -> [FailedSnapshotTest] {
        runs.first?.allTests
            .filter { $0.status == .failure }
            .flatMap { test -> [FailedSnapshotTest] in
                let screenshots = test.allAttachments.filter(\.isScreenshot)
                let reference = screenshots.first { $0.name?.rawValue == "reference" } ?? screenshots.first

                guard let reference else { return [] }

                var references = screenshots.filter { $0.name?.rawValue == "reference" }
                var failures = screenshots.filter { $0.name?.rawValue == "failure" }
                var differences = screenshots.filter { $0.name?.rawValue == "difference" }

                // On macOS there are no names like reference, failure or difference. We need to rely on the order.
                if references.isEmpty {
                    references = screenshots.enumerated().filter { index, _ in index % 3 == 0 }.map(\.element)
                    failures = screenshots.enumerated().filter { index, _ in index % 3 == 1 }.map(\.element)
                    differences = screenshots.enumerated().filter { index, _ in index % 3 == 2 }.map(\.element)
                }

                guard
                    references.count == failures.count,
                    failures.count == differences.count
                else { return [] }

                let snapshotsCount = references.count

                return (0..<snapshotsCount).map {
                    FailedSnapshotTest(
                        id: snapshotsCount == 1 ? test.identifier : "\(test.identifier)_\($0 + 1)",
                        mimeType: reference.type.mimeType,
                        referenceImage: references[$0].getData(),
                        failureImage: failures[$0].getData(),
                        diffImage: differences[$0].getData()
                    )
                }
            } ?? []
    }
}

extension Attachment {
    func getData() -> Data? {
        if case .data(let data) = content {
            return data
        }

        return nil
    }
}

extension [Attachment] {
    func getData(with name: String) -> Data? {
        let content = first { $0.name?.rawValue == name && $0.isScreenshot }?
            .content

        if case .data(let data) = content {
            return data
        }

        return nil
    }
}

extension Summary: HTML {
    var htmlTemplate: String {
        HTMLTemplates.index
    }

    var htmlPlaceholderValues: [String: String] {
        let resultClass: String
        if runs.contains(where: { $0.status == .failure }) {
            resultClass = "failure"
        } else if runs.contains(where: { $0.status == .success }) {
            resultClass = "success"
        } else {
            resultClass = "skip"
        }
        return [
            "DEVICES": runs.map(\.runDestination.html).joined(),
            "RESULT_CLASS": resultClass,
            "RUNS": runs.map(\.html).joined()
        ]
    }
}

extension Summary: JUnitRepresentable {
    func junit(includeRunDestinationInfo: Bool) -> JUnitReport {
        JUnitReport(summary: self, includeRunDestinationInfo: includeRunDestinationInfo)
    }
}

extension Summary: ContainingAttachment {
    var allAttachments: [Attachment] {
        runs.map(\.allAttachments).reduce([], +)
    }
}
