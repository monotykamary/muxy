import Foundation
import Testing

@testable import Muxy

@Suite("PiUsageParser")
struct PiUsageParserTests {
    @Test("parses daily usage from session files")
    func parsesDailyUsage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.writeSession(lines: [
            fixture.headerLine(cwd: "/project"),
            fixture.assistantLine(cost: 0.01, input: 100, output: 200, totalTokens: 300),
            fixture.assistantLine(cost: 0.02, input: 150, output: 250, totalTokens: 400),
        ])

        let usage = PiUsageParser.parseDailyUsage(
            from: fixture.sessionsDirectoryPath,
            calendar: fixture.calendar,
            now: fixture.now
        )

        #expect(usage.cost == 0.03)
        #expect(usage.inputTokens == 250)
        #expect(usage.outputTokens == 450)
        #expect(usage.totalTokens == 700)
    }

    @Test("ignores non-assistant messages")
    func ignoresNonAssistantMessages() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.writeSession(lines: [
            fixture.headerLine(cwd: "/project"),
            fixture.userLine(text: "Hello"),
            fixture.toolResultLine(toolName: "bash"),
        ])

        let usage = PiUsageParser.parseDailyUsage(
            from: fixture.sessionsDirectoryPath,
            calendar: fixture.calendar,
            now: fixture.now
        )

        #expect(usage.cost == 0)
        #expect(usage.totalTokens == 0)
    }

    @Test("skips files not modified today")
    func skipsOldFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.writeSession(lines: [
            fixture.headerLine(cwd: "/project"),
            fixture.assistantLine(cost: 0.05, input: 500, output: 500, totalTokens: 1000),
        ])

        let yesterday = fixture.calendar.date(byAdding: .day, value: -1, to: fixture.now)!
        let usage = PiUsageParser.parseDailyUsage(
            from: fixture.sessionsDirectoryPath,
            calendar: fixture.calendar,
            now: yesterday
        )

        #expect(usage.cost == 0)
        #expect(usage.totalTokens == 0)
    }

    @Test("returns zero usage for empty directory")
    func emptyDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let usage = PiUsageParser.parseDailyUsage(
            from: fixture.sessionsDirectoryPath,
            calendar: fixture.calendar,
            now: fixture.now
        )

        #expect(usage.cost == 0)
        #expect(usage.totalTokens == 0)
    }

    @Test("returns zero usage for nonexistent directory")
    func nonexistentDirectory() {
        let usage = PiUsageParser.parseDailyUsage(
            from: "/nonexistent/path/sessions"
        )

        #expect(usage.cost == 0)
        #expect(usage.totalTokens == 0)
    }

    @Test("aggregates across multiple session files")
    func aggregatesMultipleFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.writeSession(
            inSubdirectory: "project-a",
            fileName: "session-a.jsonl",
            lines: [
                fixture.headerLine(cwd: "/project-a"),
                fixture.assistantLine(cost: 0.01, input: 100, output: 100, totalTokens: 200),
            ]
        )

        try fixture.writeSession(
            inSubdirectory: "project-b",
            fileName: "session-b.jsonl",
            lines: [
                fixture.headerLine(cwd: "/project-b"),
                fixture.assistantLine(cost: 0.02, input: 200, output: 200, totalTokens: 400),
            ]
        )

        let usage = PiUsageParser.parseDailyUsage(
            from: fixture.sessionsDirectoryPath,
            calendar: fixture.calendar,
            now: fixture.now
        )

        #expect(usage.cost == 0.03)
        #expect(usage.totalTokens == 600)
    }

    @Test("buildMetricRows creates daily cost row when cost > 0")
    func costRow() {
        let usage = PiUsageParser.DailyUsage(
            cost: 1.23,
            inputTokens: 1000,
            outputTokens: 500,
            totalTokens: 1500
        )

        let rows = PiUsageParser.buildMetricRows(from: usage)

        #expect(rows.count == 2)
        #expect(rows[0].label == "Daily cost")
        #expect(rows[0].detail == "US$1.23")
        #expect(rows[0].resetDate != nil)
        #expect(rows[1].label == "Daily tokens")
        #expect(rows[1].detail == "1500 tokens")
    }

    @Test("buildMetricRows returns empty when no usage")
    func noUsageRows() {
        let usage = PiUsageParser.DailyUsage(
            cost: 0,
            inputTokens: 0,
            outputTokens: 0,
            totalTokens: 0
        )

        let rows = PiUsageParser.buildMetricRows(from: usage)
        #expect(rows.isEmpty)
    }

    @Test("buildMetricRows includes only cost row when tokens are zero")
    func costOnlyRow() {
        let usage = PiUsageParser.DailyUsage(
            cost: 0.50,
            inputTokens: 0,
            outputTokens: 0,
            totalTokens: 0
        )

        let rows = PiUsageParser.buildMetricRows(from: usage)
        #expect(rows.count == 1)
        #expect(rows[0].label == "Daily cost")
    }

    private struct Fixture {
        let rootURL: URL
        let sessionsDirectoryURL: URL
        let sessionsDirectoryPath: String
        let calendar: Calendar
        let now: Date

        init() throws {
            rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("PiUsageParserTests-\(UUID().uuidString)", isDirectory: true)
            sessionsDirectoryURL = rootURL.appendingPathComponent("sessions", isDirectory: true)
            sessionsDirectoryPath = sessionsDirectoryURL.path
            calendar = Calendar(identifier: .gregorian)
            now = Date()

            try FileManager.default.createDirectory(
                at: sessionsDirectoryURL,
                withIntermediateDirectories: true
            )
        }

        func writeSession(
            inSubdirectory subdirectory: String? = nil,
            fileName: String = "session.jsonl",
            lines: [String]
        ) throws {
            let dirURL: URL
            if let subdirectory {
                dirURL = sessionsDirectoryURL.appendingPathComponent(subdirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            } else {
                dirURL = sessionsDirectoryURL
            }

            let fileURL = dirURL.appendingPathComponent(fileName)
            let content = lines.joined(separator: "\n")
            try Data(content.utf8).write(to: fileURL, options: .atomic)
        }

        func headerLine(cwd: String) -> String {
            """
            {"type":"session","version":3,"id":"\(UUID().uuidString)","timestamp":"\(ISO8601DateFormatter().string(from: now))","cwd":"\(cwd)"}
            """
        }

        func assistantLine(cost: Double, input: Int, output: Int, totalTokens: Int) -> String {
            """
            {"type":"message","id":"\(UUID().uuidString)","parentId":null,"timestamp":"\(ISO8601DateFormatter().string(from: now))","message":{"role":"assistant","content":[{"type":"text","text":"hello"}],"usage":{"input":\(input),"output":\(output),"cacheRead":0,"cacheWrite":0,"totalTokens":\(totalTokens),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":\(cost)}},"stopReason":"stop"}}
            """
        }

        func userLine(text: String) -> String {
            """
            {"type":"message","id":"\(UUID().uuidString)","parentId":null,"timestamp":"\(ISO8601DateFormatter().string(from: now))","message":{"role":"user","content":"\(text)"}}
            """
        }

        func toolResultLine(toolName: String) -> String {
            """
            {"type":"message","id":"\(UUID().uuidString)","parentId":null,"timestamp":"\(ISO8601DateFormatter().string(from: now))","message":{"role":"toolResult","toolCallId":"call_1","toolName":"\(toolName)","content":[{"type":"text","text":"output"}],"isError":false}}
            """
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }
}
