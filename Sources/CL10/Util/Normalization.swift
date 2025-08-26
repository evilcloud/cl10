import Foundation

struct Normalizer {
    static func normalize(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "[\n\r\t ]+$", with: "", options: .regularExpression)
        return out
    }

    static func isBlank(_ s: String) -> Bool {
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func firstLine(_ s: String) -> String {
        return s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(
            String.init) ?? ""
    }

    static func byteCount(_ s: String) -> Int { s.lengthOfBytes(using: .utf8) }

    static func humanBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n)B" }
        if n < 1024 * 1024 { return String(format: "%.1fKB", Double(n) / 1024.0) }
        return String(format: "%.1fMB", Double(n) / (1024.0 * 1024.0))
    }

    static func escapePreview(_ s: String, maxLen: Int = 120) -> String {
        var t = s.replacingOccurrences(of: "\t", with: " ")
        t = t.replacingOccurrences(of: "\"", with: "\\\"")
        if t.count > maxLen { t = String(t.prefix(maxLen - 1)) + "…" }
        return t
    }
}
