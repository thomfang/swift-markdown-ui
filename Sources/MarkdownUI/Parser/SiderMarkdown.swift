//
//  SiderMarkdown.swift
//  swift-markdown-ui
//
//  Created by Avery on 2025/2/21.
//

import Foundation

public enum SiderMarkdown {
    public static let siderLinkPrefix = "@_"
    
    public static let siderSerialPrefix = "&_"
    
    public static let referenceScheme = "reference"
    public static let relatedScheme = "related"
}

extension SiderMarkdown {
    static func preprocessMarkdown(_ text: String) -> String {
        var result = LatexParser.preprocess(in: text)
        // 首先，替换序号链接的情况 [^1](http://...) -> [sider_1](http://...)
        replaceSerialLink(&result)
        // 然后，替换自由序号的情况 [^1] -> [1](reference://)
        replaceSerialNumberToLink(&result)
        // 把 [text](url with space) 这类 destination 含空格的情况编码成 %20
        // CommonMark bare destination 不允许空格，否则 cmark 会放弃 link/image 解析
        // 例如 LLM 生成的 ![image](/var/mobile/Library/Mobile Documents/...)
        result = encodeSpacesInLinkDestinations(result)
        return result
    }

    private static let linkDestinationRegex: NSRegularExpression? = {
        // 捕获 1：`[text](` 或 `![alt](` 前缀
        // 捕获 2：destination + 可选 title（不含 ) 与换行）
        // 捕获 3：闭合 `)`
        let pattern = #"(!?\[[^\]\n]*\]\()([^)\n]+?)(\))"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static func encodeSpacesInLinkDestinations(_ text: String) -> String {
        guard let regex = linkDestinationRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let prefixRange = Range(match.range(at: 1), in: text),
                  let destRange = Range(match.range(at: 2), in: text),
                  let suffixRange = Range(match.range(at: 3), in: text)
            else { continue }

            result.append(contentsOf: text[cursor..<fullRange.lowerBound])
            result.append(contentsOf: text[prefixRange])

            // destination + 可选 title：识别 ` "title"` / ` 'title'` 部分，仅编码 URL 段空格
            let raw = text[destRange]
            let (urlPart, titlePart) = splitDestinationAndTitle(raw)
            result.append(urlPart.replacingOccurrences(of: " ", with: "%20"))
            result.append(titlePart)

            result.append(contentsOf: text[suffixRange])
            cursor = fullRange.upperBound
        }
        result.append(contentsOf: text[cursor..<text.endIndex])
        return result
    }

    /// 把 raw 拆成 (url, title)。title 形如 ` "..."` / ` '...'`，没有则 title 为空串。
    /// 启发式：从右向左找 quote，匹配上 ` <quote>` 的开 quote 就视为 title 起始。
    private static func splitDestinationAndTitle(_ raw: Substring) -> (String, String) {
        let s = String(raw)
        guard let lastQuoteIdx = s.lastIndex(where: { $0 == "\"" || $0 == "'" }) else {
            return (s, "")
        }
        let quote = s[lastQuoteIdx]
        var i = s.index(before: lastQuoteIdx)
        while i > s.startIndex {
            let prev = s.index(before: i)
            if s[i] == quote, prev >= s.startIndex, s[prev] == " " {
                let url = String(s[s.startIndex..<prev])
                let title = String(s[prev..<s.endIndex])
                return (url, title)
            }
            i = s.index(before: i)
        }
        return (s, "")
    }
    
    private static let replaceSerialLinkRegular: NSRegularExpression? = {
        let options: NSRegularExpression.Options = [.caseInsensitive]
        let pattern = #"(?:(?:【\^|【C_|\^【)(\d{1,2})】|(?:\[\^|\[C_|\^\[)(\d{1,2})\])(?=\(.+\:\/\/.+)"#
        return try? NSRegularExpression(pattern: pattern, options: options)
    }()
    
    private static var replaceSerialNumberToLinkRegular: NSRegularExpression? = {
        let options: NSRegularExpression.Options = [.caseInsensitive]
        let pattern = #"(?:【\^|【C_|\^【)(\d+)】|(?:\[\^|\[C_|\^\[)(\d+)\]|\[(\^\d+(?:,\^\d+)*)\]|\[ref:(\s?\d+(?:,\s?\d+)*)\]"#
        return try? NSRegularExpression(pattern: pattern, options: options)
    }()

    
    private static func replaceSerialLink(_ markdown: inout String) {
        guard let regex = replaceSerialLinkRegular else {
            assertionFailure("正则表达式不正确")
            return
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        markdown = regex.stringByReplacingMatches(in: markdown, range: range, withTemplate: "[\(siderLinkPrefix)$1$2]")
    }
    
    private static func replaceSerialNumberToLink(_ markdown: inout String) {
        guard let regex = replaceSerialNumberToLinkRegular else {
            assertionFailure("正则表达式不正确")
            return
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        markdown = regex.stringByReplacingMatches(in: markdown, range: range, withTemplate: "[\(siderSerialPrefix)$1$2$3$4](\(referenceScheme)://serial)")
    }
}
