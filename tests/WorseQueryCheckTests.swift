import Foundation

@main
struct WorseQueryCheckTests {
    static let denied = MGPermissionInspection(readable: true, writable: false,
        validPlist: true, detail: "denied", writeOpenDenied: true)
    static let available = MGPermissionInspection(readable: true, writable: true,
        validPlist: true, detail: "available")
    static let unknown = MGPermissionInspection(readable: false, writable: false,
        validPlist: false, detail: "unknown")

    static func scenario(_ name: String, group: Bool = true, preparation: String? = nil,
                         states: [MGPermissionInspection], handles: [Int64],
                         expectedModes: [Bool], expectedReleases: [Int64], passed: Bool) {
        var remainingStates = states
        var remainingHandles = handles
        var modes: [Bool] = []
        var releases: [Int64] = []
        var messages: [String] = []
        var preparations = 0
        let result = checkMGWorseQueryRoutes(
            hasAppGroup: group,
            prepare: { preparations += 1; return preparation },
            inspect: {
                precondition(!remainingStates.isEmpty, "Unexpected inspection: \(name)")
                return remainingStates.removeFirst()
            },
            query: { alternate in
                precondition(!remainingHandles.isEmpty, "Unexpected query: \(name)")
                modes.append(alternate)
                return remainingHandles.removeFirst()
            },
            release: { releases.append($0) },
            record: { messages.append($0) }
        )
        precondition(result == passed, name)
        precondition(modes == expectedModes, name)
        precondition(releases == expectedReleases, name)
        precondition(remainingStates.isEmpty && remainingHandles.isEmpty, name)
        precondition(preparations == (preparation == nil ? modes.count : 1), name)
        for handle in handles where handle < 0 {
            precondition(messages.contains { $0.contains("返回值 \(handle)") }, name)
        }
        print("PASS: \(name)")
    }

    static func main() throws {
        scenario("standard mode releases its handle before success",
            states: [denied, available, denied], handles: [42],
            expectedModes: [false], expectedReleases: [42], passed: true)
        scenario("handle zero is valid and released",
            states: [denied, available, denied], handles: [0],
            expectedModes: [false], expectedReleases: [0], passed: true)
        scenario("fallback runs after explicit standard denial",
            states: [denied, denied, denied, available, denied], handles: [-6, 43],
            expectedModes: [false, true], expectedReleases: [43], passed: true)
        scenario("both modes denied",
            states: [denied, denied, denied, denied, denied], handles: [-5, -6],
            expectedModes: [false, true], expectedReleases: [], passed: false)
        scenario("successful query with denied file is not a pass and is released",
            states: [denied, denied, denied, denied, denied], handles: [44, -6],
            expectedModes: [false, true], expectedReleases: [44], passed: false)
        scenario("failed query cannot pass on unrelated accessible state",
            states: [denied, available, denied, denied, denied], handles: [-1, -6],
            expectedModes: [false, true], expectedReleases: [], passed: false)
        scenario("unreleased permission stops fallback",
            states: [denied, available, available], handles: [45],
            expectedModes: [false], expectedReleases: [45], passed: false)
        scenario("unknown post-release state stops fallback",
            states: [denied, available, unknown], handles: [46],
            expectedModes: [false], expectedReleases: [46], passed: false)
        scenario("unknown file state still releases a valid handle",
            states: [denied, unknown, denied, denied, denied], handles: [47, -6],
            expectedModes: [false, true], expectedReleases: [47], passed: false)
        scenario("already writable baseline is not attributed to the query",
            states: [available], handles: [],
            expectedModes: [], expectedReleases: [], passed: false)
        scenario("unknown baseline does not query",
            states: [unknown], handles: [],
            expectedModes: [], expectedReleases: [], passed: false)
        scenario("missing App Group does not inspect or query", group: false,
            states: [], handles: [], expectedModes: [], expectedReleases: [], passed: false)
        scenario("unsafe cache stops before any query", preparation: "cache is not empty",
            states: [denied], handles: [], expectedModes: [], expectedReleases: [], passed: false)

        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        precondition(prepareMGCheckCaches(at: root) == nil)
        let library = root.appendingPathComponent("Library")
        let caches = library.appendingPathComponent("Caches")
        let sentinel = caches.appendingPathComponent("keep.txt")
        let bytes = Data("existing cache must survive".utf8)
        try bytes.write(to: sentinel)
        precondition(prepareMGCheckCaches(at: root) != nil)
        let kept = try Data(contentsOf: sentinel)
        precondition(kept == bytes)
        print("PASS: nonempty cache is rejected without changing its contents")

        let outside = root.appendingPathComponent("outside")
        try files.moveItem(at: caches, to: outside)
        try files.createSymbolicLink(at: caches, withDestinationURL: outside)
        precondition(prepareMGCheckCaches(at: root) != nil)
        let keptViaLink = try Data(contentsOf: outside.appendingPathComponent("keep.txt"))
        precondition(keptViaLink == bytes)
        print("PASS: cache symlink is rejected and its target is unchanged")
        try files.removeItem(at: caches)
        try files.removeItem(at: library)
        try files.createSymbolicLink(at: library, withDestinationURL: outside)
        precondition(prepareMGCheckCaches(at: root) != nil)
        precondition(!files.fileExists(atPath: outside.appendingPathComponent("Caches").path))
        print("PASS: Library symlink is rejected before creating a child")
        print("Mocks and temporary fixtures only; no iOS exploit or system-cache writes were executed.")
    }
}
