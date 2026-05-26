import Foundation

enum PiUsageParser {
    struct DailyUsage: Equatable {
        let cost: Double
        let inputTokens: Double
        let outputTokens: Double
        let totalTokens: Double
    }

    static func parseDailyUsage(
        from sessionDirectory: String,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DailyUsage {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: sessionDirectory, isDirectory: true),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return DailyUsage(cost: 0, inputTokens: 0, outputTokens: 0, totalTokens: 0)
        }

        var totalCost: Double = 0
        var totalInput: Double = 0
        var totalOutput: Double = 0
        var totalTokens: Double = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  calendar.isDate(modDate, inSameDayAs: now)
            else {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            content.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      entry["type"] as? String == "message",
                      let message = entry["message"] as? [String: Any],
                      message["role"] as? String == "assistant",
                      let usage = message["usage"] as? [String: Any]
                else {
                    return
                }

                if let cost = usage["cost"] as? [String: Any] {
                    totalCost += cost["total"] as? Double ?? 0
                }

                totalInput += usage["input"] as? Double ?? 0
                totalOutput += usage["output"] as? Double ?? 0
                totalTokens += usage["totalTokens"] as? Double ?? 0
            }
        }

        return DailyUsage(
            cost: totalCost,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            totalTokens: totalTokens
        )
    }

    static func buildMetricRows(
        from usage: DailyUsage,
        now: Date = Date()
    ) -> [AIUsageMetricRow] {
        var rows: [AIUsageMetricRow] = []

        let resetDate = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )

        if usage.cost > 0 {
            rows.append(
                AIUsageMetricRow(
                    label: "Daily cost",
                    percent: nil,
                    resetDate: resetDate,
                    detail: AIUsageParserSupport.currencyDetail(amount: usage.cost)
                )
            )
        }

        if usage.totalTokens > 0 {
            let formatted = AIUsageParserSupport.formatNumber(usage.totalTokens)
            rows.append(
                AIUsageMetricRow(
                    label: "Daily tokens",
                    percent: nil,
                    resetDate: resetDate,
                    detail: "\(formatted) tokens"
                )
            )
        }

        return rows
    }
}
