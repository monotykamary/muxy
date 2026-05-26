import Foundation
import Testing

@testable import Muxy

@Suite("PiProvider")
struct PiProviderTests {
    private let provider = PiProvider()

    @Test("id returns pi")
    func id() {
        #expect(provider.id == "pi")
    }

    @Test("displayName returns Pi")
    func displayName() {
        #expect(provider.displayName == "Pi")
    }

    @Test("socketTypeKey returns pi")
    func socketTypeKey() {
        #expect(provider.socketTypeKey == "pi")
    }

    @Test("iconName returns pi")
    func iconName() {
        #expect(provider.iconName == "pi")
    }

    @Test("executableNames contains pi")
    func executableNames() {
        #expect(provider.executableNames == ["pi"])
    }

    @Test("hookScriptName returns muxy-pi-extension")
    func hookScriptName() {
        #expect(provider.hookScriptName == "muxy-pi-extension")
    }

    @Test("settingsKey is derived from id")
    func settingsKey() {
        #expect(provider.settingsKey == "muxy.notifications.provider.pi.enabled")
    }

    @Test("isEnabled stores and retrieves value via UserDefaults")
    func isEnabledStorage() {
        let key = provider.settingsKey
        let defaults = UserDefaults.standard

        defaults.removeObject(forKey: key)
        #expect(defaults.bool(forKey: key, fallback: true) == true)

        provider.isEnabled = false
        #expect(provider.isEnabled == false)

        provider.isEnabled = true
        #expect(provider.isEnabled == true)

        defaults.removeObject(forKey: key)
    }

    @Test("install creates extension file and registers settings")
    func installCreatesFileAndRegistersSettings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let provider = fixture.provider()

        try provider.install(hookScriptPath: "")

        let destinationURL = fixture.homeURL
            .appendingPathComponent(".pi/agent/extensions/muxy-notify.ts")
        let installedData = try Data(contentsOf: destinationURL)
        let sourceData = try Data(contentsOf: fixture.sourceURL)
        #expect(installedData == sourceData)

        let settings = try fixture.readSettings()
        let extensions = try #require(settings["extensions"] as? [String])
        #expect(extensions == [destinationURL.path])
        #expect(FileManager.default.fileExists(atPath: fixture.settingsURL.path + ".muxy-backup"))
    }

    @Test("install is idempotent when extension is already current")
    func installIsIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let provider = fixture.provider()

        try provider.install(hookScriptPath: "")
        try provider.install(hookScriptPath: "")

        let settings = try fixture.readSettings()
        let extensions = try #require(settings["extensions"] as? [String])
        #expect(extensions.count == 1)
    }

    @Test("uninstall removes extension file and unregisters settings")
    func uninstallRemovesFileAndUnregistersSettings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let provider = fixture.provider()

        try provider.install(hookScriptPath: "")
        try provider.uninstall()

        let destinationPath = fixture.homeURL
            .appendingPathComponent(".pi/agent/extensions/muxy-notify.ts")
            .path
        #expect(!FileManager.default.fileExists(atPath: destinationPath))

        let settings = try fixture.readSettings()
        #expect(settings["extensions"] == nil)
    }

    @Test("uninstall does nothing when file does not exist")
    func uninstallNoFile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.provider().uninstall()
    }

    @Test("isToolInstalled checks common paths")
    func isToolInstalledFromCommonPath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let executableURL = fixture.homeURL.appendingPathComponent(".local/bin/pi")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: FilePermissions.executable],
            ofItemAtPath: executableURL.path
        )

        #expect(fixture.provider().isToolInstalled())
    }

    @Test("isToolInstalled checks PATH entries")
    func isToolInstalledFromPath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let binURL = fixture.rootURL.appendingPathComponent("npm/bin")
        let executableURL = binURL.appendingPathComponent("pi")
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        try Data().write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: FilePermissions.executable],
            ofItemAtPath: executableURL.path
        )

        #expect(fixture.provider(pathEnvironment: binURL.path).isToolInstalled())
    }

    @Test("fetchUsageSnapshot returns unavailable when session directory does not exist")
    func fetchUsageSnapshotNoDirectory() async {
        let provider = PiProvider(
            homeDirectory: "/nonexistent-home-\(UUID().uuidString)",
            pathEnvironment: "",
            resourceURL: { _, _ in nil },
            sessionDirectory: "/nonexistent-sessions-\(UUID().uuidString)"
        )

        let snapshot = await provider.fetchUsageSnapshot()
        #expect(snapshot.state == .unavailable(message: "Open Pi to see usage"))
    }

    @Test("fetchUsageSnapshot returns unavailable when no usage today")
    func fetchUsageSnapshotNoUsage() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let sessionsDir = fixture.homeURL.appendingPathComponent(".pi/agent/sessions")
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let provider = fixture.provider()
        let snapshot = await provider.fetchUsageSnapshot()
        #expect(snapshot.state == .unavailable(message: "No usage today"))
    }

    @Test("fetchUsageSnapshot returns available with usage rows")
    func fetchUsageSnapshotWithUsage() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let sessionsDir = fixture.homeURL.appendingPathComponent(".pi/agent/sessions")
        let projectDir = sessionsDir.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let sessionJSONL = """
        {"type":"session","version":3,"id":"abc","timestamp":"2026-01-01T00:00:00Z","cwd":"/project"}
        {"type":"message","id":"m1","parentId":null,"timestamp":"2026-01-01T00:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input":100,"output":200,"cacheRead":0,"cacheWrite":0,"totalTokens":300,"cost":{"input":0.001,"output":0.003,"cacheRead":0,"cacheWrite":0,"total":0.004}},"stopReason":"stop"}}
        """
        try Data(sessionJSONL.utf8).write(
            to: projectDir.appendingPathComponent("session.jsonl"),
            options: .atomic
        )

        let provider = fixture.provider()
        let snapshot = await provider.fetchUsageSnapshot()

        guard case .available = snapshot.state else {
            Issue.record("Expected available state, got \(snapshot.state)")
            return
        }
        #expect(snapshot.rows.count == 2)
        #expect(snapshot.rows[0].label == "Daily cost")
        #expect(snapshot.rows[1].label == "Daily tokens")
    }

    @Test("install throws when resource is missing")
    func installThrowsWhenResourceMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let provider = PiProvider(
            homeDirectory: fixture.homeURL.path,
            pathEnvironment: "",
            resourceURL: { _, _ in nil },
            sessionDirectory: fixture.homeURL.appendingPathComponent(".pi/agent/sessions").path
        )

        #expect(throws: PiProviderError.bundleResourceNotFound) {
            try provider.install(hookScriptPath: "")
        }
    }

    private struct Fixture {
        let rootURL: URL
        let homeURL: URL
        let sourceURL: URL
        let settingsURL: URL

        init() throws {
            rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PiProviderTests-\(UUID().uuidString)", isDirectory: true)
            homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
            sourceURL = rootURL.appendingPathComponent("muxy-pi-extension.ts")
            settingsURL = homeURL.appendingPathComponent(".pi/agent/settings.json")

            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("extension source".utf8).write(to: sourceURL)
            let settingsData = try JSONSerialization.data(
                withJSONObject: ["extensions": []],
                options: [.prettyPrinted, .sortedKeys]
            )
            try settingsData.write(to: settingsURL)
        }

        func provider(pathEnvironment: String = "") -> PiProvider {
            PiProvider(
                homeDirectory: homeURL.path,
                pathEnvironment: pathEnvironment,
                resourceURL: { _, _ in sourceURL },
                sessionDirectory: homeURL.appendingPathComponent(".pi/agent/sessions").path
            )
        }

        func readSettings() throws -> [String: Any] {
            let data = try Data(contentsOf: settingsURL)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }
}
