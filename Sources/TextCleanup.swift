import Foundation

enum TextCleanup {
    static func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", options: []
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// man -P cat encodes bold as "X\bX" and underline as "_\bX". Dropping each
    /// backspace with its preceding character collapses both to plain text.
    static func stripOverstrike(_ text: String) -> String {
        var output: [Character] = []
        output.reserveCapacity(min(text.count, 262144))
        for character in text {
            if character == "\u{08}" {
                if !output.isEmpty { output.removeLast() }
            } else {
                output.append(character)
            }
        }
        return String(output)
    }

    static func cleaned(_ raw: String) -> String {
        stripOverstrike(stripANSI(raw))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func trimEnd(_ line: String) -> String {
        var characters = Array(line)
        while let last = characters.last, last == " " || last == "\t" {
            characters.removeLast()
        }
        return String(characters)
    }

    static func normalize(_ raw: String, maxLines: Int = 80, maxChars: Int = 8192) -> String {
        let lines = cleaned(raw)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimEnd(String($0)) }

        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty && collapsed.last == "" { continue }
            collapsed.append(line)
        }
        while collapsed.first == "" { collapsed.removeFirst() }
        while collapsed.last == "" { collapsed.removeLast() }

        if collapsed.count > 1,
           collapsed[0].count > 200,
           collapsed.dropFirst().contains(where: { !$0.isEmpty }) {
            collapsed.removeFirst()
        }

        var limited: [String] = []
        var used = 0
        for line in collapsed {
            if limited.count >= maxLines { break }
            if used + line.count + 1 > maxChars { break }
            limited.append(line)
            used += line.count + 1
        }
        if limited.count < collapsed.count { limited.append("[用法已截断]") }
        return limited.joined(separator: "\n")
    }

    static func looksLikeUsage(_ text: String) -> Bool {
        let visible = text
            .replacingOccurrences(of: "[用法已截断]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return visible.count >= 20
    }

    static func description(from text: String) -> String {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.count < 12 || line.hasPrefix("-") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("usage") || lower.hasPrefix("synopsis")
                || lower.hasPrefix("options") || lower.hasPrefix("name")
                || lower.hasPrefix("copyright") || lower.hasPrefix("see also") { continue }
            // man page banners ("FOO(8)   System Manager's Manual") and ALL-CAPS
            // section headers are formatting, not prose.
            if line.count < 130 && lower.contains("manual") { continue }
            if line.count < 40 && line == line.uppercased()
                && line.rangeOfCharacter(from: .letters) != nil { continue }
            if line.split(separator: " ").count < 3 { continue }
            if line.count > 160 { return String(line.prefix(159)) + "…" }
            return line
        }
        return ""
    }

    /// `whatis foo` prints "foo(8) - one line summary". Used as a description
    /// fallback when neither --help nor man produced usable text.
    static func whatisDescription(from raw: String, tool: String) -> String {
        let lines = cleaned(raw)
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let preferred = lines.first { $0.lowercased().hasPrefix(tool.lowercased() + "(") }
            ?? lines.first
            ?? ""
        guard let dash = preferred.range(of: " - ") else { return "" }
        let value = String(preferred[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard value.count >= 8 else { return "" }
        return value.count > 160 ? String(value.prefix(159)) + "…" : value
    }

    static func manExamples(from rawText: String) -> String {
        let lines = cleaned(rawText)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimEnd(String($0)) }
        let stopHeaders: Set<String> = [
            "SEE ALSO", "AUTHORS", "BUGS", "HISTORY", "NOTES", "OPTIONS",
            "FILES", "EXIT STATUS", "ENVIRONMENT", "STANDARDS", "CAVEATS",
            "DIAGNOSTICS", "COMPATIBILITY", "ERRORS", "COPYRIGHT", "NAME"
        ]

        guard let start = lines.firstIndex(where: {
            let upper = $0.trimmingCharacters(in: .whitespaces).uppercased()
            return upper == "EXAMPLES" || upper == "EXAMPLE" || upper == "EXAMPLES:"
        }) else { return "" }

        var collected: [String] = []
        var index = start
        while index < lines.count, collected.count < 60 {
            if index > start {
                let header = lines[index].trimmingCharacters(in: .whitespaces).uppercased()
                if stopHeaders.contains(header) { break }
            }
            collected.append(lines[index])
            index += 1
        }
        while collected.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            collected.removeFirst()
        }
        while collected.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            collected.removeLast()
        }
        return collected.joined(separator: "\n")
    }
}
