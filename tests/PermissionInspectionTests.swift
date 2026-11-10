import Foundation
import Darwin

@main
struct PermissionInspectionTests {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let file = directory.appendingPathComponent("cache.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CacheExtra": ["example": true], "CacheData": Data(repeating: 0, count: 512)
        ], format: .binary, options: 0)
        try data.write(to: file)
        let valid = inspectMGPermissions(at: file)
        precondition(valid.passed && !valid.writeOpenDenied, valid.detail)
        let afterValid = try Data(contentsOf: file)
        precondition(afterValid == data, "Inspection mutated valid file")
        print("PASS: valid fixture opens O_RDWR and bytes remain unchanged")

        precondition(chmod(file.path, 0o444) == 0)
        if geteuid() != 0 {
            let readOnly = inspectMGPermissions(at: file)
            precondition(readOnly.readable && readOnly.validPlist && !readOnly.writable && !readOnly.passed && readOnly.writeOpenDenied)
            print("PASS: read-only fixture cannot be reported writable")
        } else { throw NSError(domain: "TestsMustNotRunAsRoot", code: 1) }
        precondition(chmod(file.path, 0o600) == 0)

        let link = directory.appendingPathComponent("symlink.plist")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)
        precondition(!inspectMGPermissions(at: link).passed)
        let afterLink = try Data(contentsOf: file)
        precondition(afterLink == data)
        print("PASS: symlink rejected without modifying target")

        let missing = directory.appendingPathComponent("missing.plist")
        precondition(!inspectMGPermissions(at: missing).passed)
        precondition(!fm.fileExists(atPath: missing.path))
        print("PASS: missing file rejected and not created")

        try Data("not a plist".utf8).write(to: file)
        let invalid = inspectMGPermissions(at: file)
        precondition(invalid.readable && !invalid.validPlist && !invalid.passed && !invalid.writeOpenDenied)
        let unchanged = try Data(contentsOf: file)
        precondition(unchanged == Data("not a plist".utf8))
        print("PASS: malformed fixture rejected and unchanged")

        precondition(!inspectMGPermissions(at: directory).passed)
        print("PASS: directory rejected")
        print("These macOS fixture checks do not test iOS sandbox access or unlock Apple Intelligence.")
    }
}
