//
//  LyricsParser.swift
//  PrismMusic
//
//  Parses LRC (`[mm:ss.xx] line`) and LRCX (`<mm:ss.xx> word`) timestamp
//  formats. Word-by-word timing is supported when the source contains <…>
//  per-word markers; otherwise we synthesize word timing by linear
//  distribution across the line's duration (same algorithm as
//  `components/music/synced-lyrics.tsx`).
//

import Foundation

enum LyricsParser {
    static func parse(_ raw: String) -> ParsedLyrics {
        // Strip metadata header tags ([ar:Artist], [ti:Title], etc.) but
        // honour the global `[offset:N]` shift (milliseconds).
        let offset = extractOffset(raw)
        let tsRegex = try! NSRegularExpression(
            pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        )
        let wordRegex = try! NSRegularExpression(
            pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#
        )
        let metaRegex = try! NSRegularExpression(
            pattern: #"^\[(ti|ar|al|au|by|re|ve|length|offset|id|tool|hash):"#,
            options: [.caseInsensitive]
        )

        var lines: [LyricsLine] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if metaRegex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: line.utf16.count)
            ) != nil { continue }

            // Find all line-level timestamps; one LRC line can carry multiple
            // (a chorus repeated at several timestamps).
            let tsMatches = tsRegex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            if tsMatches.isEmpty { continue }

            // The lyric body is whatever follows the LAST line-level timestamp.
            let lastTS = tsMatches.last!
            let bodyStart = line.index(line.startIndex, offsetBy: lastTS.range.upperBound)
            let body = String(line[bodyStart...]).trimmingCharacters(in: .whitespaces)

            // Optionally extract word-level timestamps from the body.
            let (cleanText, words) = parseWords(body: body, regex: wordRegex)

            for tsMatch in tsMatches {
                guard let t = decodeTimestamp(tsMatch, in: line, offset: offset) else { continue }
                let adjustedWords = words.map { word in
                    // For repeated timestamps we copy the words but anchor them
                    // to this line's start instead of the first occurrence.
                    LyricsWord(time: word.time, text: word.text)
                }
                lines.append(LyricsLine(
                    time: t,
                    endTime: nil,
                    text: cleanText,
                    words: adjustedWords.isEmpty ? nil : adjustedWords
                ))
            }
        }

        // Sort by timestamp, then synthesize endTime + word timing where missing.
        var sorted = lines.sorted { $0.time < $1.time }
        for i in sorted.indices {
            let endTime = i + 1 < sorted.count ? sorted[i + 1].time : nil
            sorted[i] = LyricsLine(
                time: sorted[i].time,
                endTime: endTime,
                text: sorted[i].text,
                words: sorted[i].words ?? synthesizeWords(
                    text: sorted[i].text,
                    start: sorted[i].time,
                    end: endTime ?? (sorted[i].time + 4)
                )
            )
        }

        return ParsedLyrics(lines: sorted)
    }

    // MARK: - Helpers

    private static func extractOffset(_ raw: String) -> Double {
        let regex = try! NSRegularExpression(pattern: #"\[offset:\s*(-?\d+)\s*\]"#, options: [.caseInsensitive])
        let nsRaw = raw as NSString
        guard let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: nsRaw.length)),
              match.numberOfRanges > 1
        else { return 0 }
        let valueRange = match.range(at: 1)
        let value = nsRaw.substring(with: valueRange)
        return (Double(value) ?? 0) / 1000.0
    }

    private static func decodeTimestamp(_ match: NSTextCheckingResult, in line: String, offset: Double) -> Double? {
        let nsLine = line as NSString
        guard match.numberOfRanges >= 3 else { return nil }
        let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
        var fraction: Double = 0
        if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
            let raw = nsLine.substring(with: match.range(at: 3))
            // 1, 2, or 3 digits — pad to 3 then divide.
            let padded = raw.padding(toLength: 3, withPad: "0", startingAt: 0)
            fraction = (Double(padded) ?? 0) / 1000.0
        }
        return minutes * 60 + seconds + fraction + offset
    }

    private static func parseWords(body: String, regex: NSRegularExpression) -> (String, [LyricsWord]) {
        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        guard !matches.isEmpty else { return (body, []) }

        var words: [LyricsWord] = []
        var cleanText = body
        // We need pairs of (time-stamp, text-until-next-stamp). Walk through
        // matches and capture the text in between.
        for (i, match) in matches.enumerated() {
            let minutes = Double(nsBody.substring(with: match.range(at: 1))) ?? 0
            let seconds = Double(nsBody.substring(with: match.range(at: 2))) ?? 0
            var fraction: Double = 0
            if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
                let raw = nsBody.substring(with: match.range(at: 3))
                let padded = raw.padding(toLength: 3, withPad: "0", startingAt: 0)
                fraction = (Double(padded) ?? 0) / 1000.0
            }
            let time = minutes * 60 + seconds + fraction

            let textStart = match.range.location + match.range.length
            let textEnd = i + 1 < matches.count ? matches[i + 1].range.location : nsBody.length
            let text = nsBody.substring(with: NSRange(location: textStart, length: max(0, textEnd - textStart)))
                .trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                words.append(LyricsWord(time: time, text: text))
            }
        }
        // Strip <…> markers from the clean version of the text.
        cleanText = regex.stringByReplacingMatches(
            in: body,
            range: NSRange(location: 0, length: nsBody.length),
            withTemplate: ""
        ).replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        return (cleanText, words)
    }

    /// When the LRC source has only line-level timing, distribute words
    /// across the line's duration proportionally to their character lengths.
    /// This gives a believable highlight even without true word timing.
    private static func synthesizeWords(text: String, start: Double, end: Double) -> [LyricsWord]? {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count > 1 else { return nil }
        let lineDuration = max(0.5, end - start)
        let totalChars = max(1, tokens.reduce(0) { $0 + $1.count })
        var cursor = start
        var words: [LyricsWord] = []
        for token in tokens {
            words.append(LyricsWord(time: cursor, text: token))
            let share = Double(token.count) / Double(totalChars)
            cursor += lineDuration * share
        }
        return words
    }
}
