import XCTest

/// 모든 언어의 Localizable.strings가 영어와 같은 키를 갖는지 확인한다.
final class LocalizationResourcesTests: XCTestCase {
    private var resourcesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    private func strings(at lproj: URL) throws -> [String: String] {
        let data = try Data(contentsOf: lproj.appendingPathComponent("Localizable.strings"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    func testEveryLanguageHasTheSameKeysAsEnglish() throws {
        let dirs = try FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        let english = try strings(at: resourcesURL.appendingPathComponent("en.lproj"))
        XCTAssertGreaterThan(dirs.count, 1)
        for dir in dirs {
            let table = try strings(at: dir)
            XCTAssertEqual(Set(table.keys), Set(english.keys), dir.lastPathComponent)
            for (key, value) in table {
                XCTAssertFalse(value.isEmpty, "\(dir.lastPathComponent): \(key)")
                // 서식 지정자 개수가 원문과 같아야 한다.
                XCTAssertEqual(value.components(separatedBy: "%@").count,
                               key.components(separatedBy: "%@").count, "\(dir.lastPathComponent): \(key)")
            }
        }
    }

    /// 코드에서 쓰는 L("...") 키가 모두 번역 파일에 있는지 확인한다.
    func testEveryKeyUsedInCodeExists() throws {
        let sources = resourcesURL.deletingLastPathComponent().appendingPathComponent("Sources/DisplayToggle")
        let english = try strings(at: resourcesURL.appendingPathComponent("en.lproj"))
        let regex = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)""#)
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(m.range(at: 1), in: text)!])
                XCTAssertNotNil(english[key], "\(file.lastPathComponent): missing key \(key)")
            }
        }
    }
}
