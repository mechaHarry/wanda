import Foundation
import XCTest

final class ReleaseScriptTests: XCTestCase {
    func testReleaseScriptHelpDocumentsSignedTagAndVersionedZipFlow() throws {
        let output = try runReleaseScript("--help")

        XCTAssertTrue(output.contains("signed git tag"))
        XCTAssertTrue(output.contains("VERSION"))
        XCTAssertTrue(output.contains("v<VERSION>"))
        XCTAssertTrue(output.contains("versioned zip"))
        XCTAssertTrue(output.contains("GITHUB_TOKEN"))
    }

    func testReleaseScriptBuildsTagAndAssetNamesFromVersionFile() throws {
        let script = try String(contentsOfFile: "release.sh", encoding: .utf8)

        XCTAssertTrue(script.contains(#"VERSION_FILE="${ROOT_DIR}/VERSION""#))
        XCTAssertTrue(script.contains(#"TAG_NAME="v${VERSION}""#))
        XCTAssertTrue(script.contains(#"RELEASE_NAME="${APP_NAME} ${VERSION}""#))
        XCTAssertTrue(script.contains(#"ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macos-${ARCH_LABEL}.zip""#))
    }

    func testReleaseScriptSignsTagAndUploadsVersionedAssets() throws {
        let script = try String(contentsOfFile: "release.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("git tag -s"))
        XCTAssertTrue(script.contains("git tag -v"))
        XCTAssertTrue(script.contains(#""generate_release_notes": True"#))
        XCTAssertTrue(script.contains(#"upload_asset "${ZIP_PATH}" "application/zip""#))
        XCTAssertTrue(script.contains(#"upload_asset "${SHA_PATH}" "text/plain""#))
    }

    func testReleaseScriptOmitsAppleDoubleSidecarsFromZip() throws {
        let script = try String(contentsOfFile: "release.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("ditto -c -k --norsrc --noextattr --keepParent"))
    }

    private func runReleaseScript(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["release.sh"] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output
    }
}
