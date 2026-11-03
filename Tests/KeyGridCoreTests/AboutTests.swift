import Foundation   // Tests only, to read README.md. KeyGridCore itself imports no framework.
import Testing
@testable import KeyGridCore

@Suite struct VersionText {
    @Test func shortAndBuild() {
        #expect(About.versionText(short: "0.4.0", build: "1") == "0.4.0 (1)")
    }

    @Test func missingBuildIsLeftOut() {
        #expect(About.versionText(short: "0.4.0", build: nil) == "0.4.0")
        #expect(About.versionText(short: "0.4.0", build: " ") == "0.4.0")
    }

    @Test func missingVersionIsSaidSo() {
        #expect(About.versionText(short: nil, build: "1") == "unknown version")
        #expect(About.versionText(short: "", build: nil) == "unknown version")
    }

    @Test func whitespaceIsTrimmed() {
        #expect(About.versionText(short: " 0.4.0\n", build: " 7 ") == "0.4.0 (7)")
    }
}

@Suite struct SignatureText {
    @Test func aCertificateIsNamed() {
        #expect(About.signatureText(identity: "My Signing Cert") == "Signed by My Signing Cert.")
    }

    @Test func noCertificateIsAdHoc() {
        let adHoc = "Signed ad hoc: the Accessibility grant is lost on every rebuild."
        #expect(About.signatureText(identity: nil) == adHoc)
        #expect(About.signatureText(identity: "  ") == adHoc)
    }
}

/// README.md is the master copy of the description and the promises; the
/// About window shows the words in `About`. Both are compared with runs of
/// whitespace collapsed to one space (the README wraps lines) and
/// backticks removed (the README quotes the config path in code).
@Suite struct ReadmeIsTheMaster {
    static let readme: String = {
        // Tests/KeyGridCoreTests/AboutTests.swift → the repository root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = (try? String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)) ?? ""
        return Self.normalized(text)
    }()

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    @Test func readmeWasFound() {
        #expect(Self.readme.hasPrefix("# \(About.name)"))
    }

    @Test func descriptionIsTheReadmesFirstSentence() {
        #expect(Self.readme.contains(Self.normalized(About.description)))
    }

    @Test func promisesAreTheReadmesList() {
        #expect(About.promises.count == 4)
        for promise in About.promises {
            #expect(Self.readme.contains("- " + Self.normalized(promise)), "\(promise)")
        }
    }

    @Test func repositoryIsNamedInTheReadme() {
        #expect(Self.readme.contains(About.repository))
    }
}
