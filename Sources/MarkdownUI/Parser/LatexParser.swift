//
//  File.swift
//  swift-markdown-ui
//
//  Created by 唐海 on 10/31/24.
//

import Foundation

public struct LatexParser {
    let range: Range<String.Index>
    let tag: Substring
}

extension LatexParser {
    
    func isBlock(parser: LatexParser, text: String) -> Bool {
        let latex = text[self.range.upperBound..<parser.range.lowerBound]
        let bool = self.range.lowerBound == text.startIndex && parser.range.upperBound == text.endIndex
        return bool || latex.count > 40
    }
    
    func pairing(parser: LatexParser) -> Bool {
        if self.tag == "$$" && parser.tag == "$$" {
            return true
        }
        if self.tag == "$" && parser.tag == "$" {
            return true
        }
        if self.tag == "\\(" && parser.tag == "\\)" {
            return true
        }
        if self.tag == "\\[" && parser.tag == "\\]" {
            return true
        }
        return false
    }
}

extension LatexParser {
    
    static let latexSpecialCharacters: CharacterSet = {
        return CharacterSet(charactersIn: "{}[]+-*=<>∈∉∋∌∏∑−∓∔∕∗√∝∞∧∨∩∪∫∬∭∮∯∰∱∲∳ℵℏℑℜ℘ℓ∂∇")
    }()

    static let combinedCharacterSet: CharacterSet = {
        return CharacterSet.letters.union(CharacterSet.decimalDigits).union(latexSpecialCharacters)
    }()
    
    static func containsLatexSpecialCharacters(in string: String) -> Bool {
        return string.rangeOfCharacter(from: latexSpecialCharacters) != nil
    }
    
    static var findLatexRegular: NSRegularExpression?
    static var findSpecialCharacter: NSRegularExpression?
    // 定义一个函数来查找特殊字符的范围
    static func findLatexRanges(in text: String) -> [Range<String.Index>] {
        do {
            
            if findLatexRegular == nil {
                // 使用原始字符串定义正则表达式模式
                let pattern = #"\$\$"#
                // 编译正则表达式
                findLatexRegular = try NSRegularExpression(pattern: pattern)
            }
            
            guard let regex = findLatexRegular else { return [] }
           
            
            // 将整个字符串的范围转换为 NSRange
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            
            // 查找所有匹配项
            let matches = regex.matches(in: text, options: [], range: nsRange)
            
            // 将 NSRange 转换为 Range<String.Index>
            return matches.compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                return range
            }
        } catch {
            print("正则表达式错误: \(error)")
            return []
        }
    }
    
    // 定义一个函数来查找特殊字符的范围
    static func findSpecialCharacterRanges(in text: String) -> [Range<String.Index>] {
        do {
            if findSpecialCharacter == nil {
                // 使用原始字符串定义正则表达式模式
                let pattern = #"\$\$|\$|\\\(|\\\)|\\\[|\\\]"#
                // 编译正则表达式
                findSpecialCharacter = try NSRegularExpression(pattern: pattern)
            }
            guard let regex = findSpecialCharacter else { return [] }
            
            // 将整个字符串的范围转换为 NSRange
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            
            // 查找所有匹配项
            let matches = regex.matches(in: text, options: [], range: nsRange)
            
            // 将 NSRange 转换为 Range<String.Index>
            return matches.compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                return range
            }
        } catch {
            print("正则表达式错误: \(error)")
            return []
        }
    }
    
    /// 扫描 fenced code block 与 inline code 的字符范围。
    /// preprocess 时这些范围内的 $/$$/\(/\[ 标记不应被识别为 LaTeX 公式。
    /// 例如 JS 模板字符串里的 `${var}` 会被错认为 inline math `$...$`。
    private static func findCodeRanges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        let chars = Array(text)
        let n = chars.count
        var i = 0

        func indexAt(_ offset: Int) -> String.Index {
            text.index(text.startIndex, offsetBy: offset)
        }

        while i < n {
            let atLineStart = (i == 0) || chars[i - 1] == "\n"

            // 1. Fenced code block: ``` 或 ~~~，至少 3 个，行首允许 0~3 个前导空格
            if atLineStart {
                var j = i
                var leadingSpaces = 0
                while j < n, chars[j] == " ", leadingSpaces < 3 {
                    j += 1
                    leadingSpaces += 1
                }
                if j < n, chars[j] == "`" || chars[j] == "~" {
                    let fenceChar = chars[j]
                    var fenceLen = 0
                    while j + fenceLen < n, chars[j + fenceLen] == fenceChar {
                        fenceLen += 1
                    }
                    if fenceLen >= 3 {
                        let codeStart = j
                        // 跳过开 fence 所在行
                        var lineEnd = j + fenceLen
                        while lineEnd < n, chars[lineEnd] != "\n" { lineEnd += 1 }

                        // 从下一行开始找匹配的关闭 fence（同字符、长度 >= 开 fence）
                        var k = lineEnd
                        if k < n { k += 1 }
                        var codeEnd = n
                        while k < n {
                            var ks = k
                            var sc = 0
                            while ks < n, chars[ks] == " ", sc < 3 {
                                ks += 1
                                sc += 1
                            }
                            if ks < n, chars[ks] == fenceChar {
                                var cl = 0
                                while ks + cl < n, chars[ks + cl] == fenceChar { cl += 1 }
                                if cl >= fenceLen {
                                    codeEnd = ks + cl
                                    break
                                }
                            }
                            // 跳到下一行
                            while k < n, chars[k] != "\n" { k += 1 }
                            if k < n { k += 1 }
                        }

                        result.append(indexAt(codeStart)..<indexAt(codeEnd))
                        i = codeEnd
                        continue
                    }
                }
            }

            // 2. Inline code: 反引号串配对（开/关串长度必须相同）
            if chars[i] == "`" {
                var openLen = 0
                while i + openLen < n, chars[i + openLen] == "`" { openLen += 1 }
                let openStart = i
                var k = i + openLen
                var matched = false
                while k < n {
                    if chars[k] == "`" {
                        var cl = 0
                        while k + cl < n, chars[k + cl] == "`" { cl += 1 }
                        if cl == openLen {
                            result.append(indexAt(openStart)..<indexAt(k + cl))
                            i = k + cl
                            matched = true
                            break
                        } else {
                            k += cl
                        }
                    } else {
                        k += 1
                    }
                }
                if !matched {
                    // 没找到匹配关闭串，按普通文本处理
                    i += openLen
                }
                continue
            }

            i += 1
        }

        return result
    }

    /// 预处理公式中的换行符，避免被识别为多个段落
    /// - Parameter text: 需要处理的字符
    static func preprocess(in text: String) -> String {
        let codeRanges = findCodeRanges(in: text)
        // 过滤掉落在 fenced code block / inline code 内的 $/$$/\(/\[ 标记
        // 否则像 JS 模板字符串 `${var}` 会被错当 inline math 编码
        let ranges = findSpecialCharacterRanges(in: text).filter { range in
            !codeRanges.contains(where: { $0.contains(range.lowerBound) })
        }
        var nextRange: Range<String.Index>?
        var parsers: [(LatexParser, LatexParser)] = []
        for (index, range) in ranges.enumerated() {
            // 如果当前范围属于被包含在一个公式中就跳过
            if let nextRange = nextRange, nextRange.upperBound > range.lowerBound {
                continue
            }
            let tag = text[range]
            let item = LatexParser(range: range, tag: tag)
            if index < ranges.count {
                // 寻找下一个匹配的标记
                for laterIndex in (index+1)..<ranges.count {
                    let laterRange = ranges[laterIndex]
                    let tag = text[laterRange]
                    let later = LatexParser(range: laterRange, tag: tag)
                    if item.pairing(parser: later) {
                        let latexRange = item.range.upperBound..<later.range.lowerBound
                        let latex = text[latexRange]
                        var valid = true
                        if item.tag == "$" {
                            valid = LatexValidator.isMathFormula(String(latex))
                        }
                        if valid {
                            parsers.append((item, later))
                            nextRange = later.range
                        } else {
                            nextRange = item.range
                        }
                        if valid == false {
                            debugPrint("valid=\(latex)")
                        }
                        break
                    }
                }
            }
        }
        if parsers.isEmpty == false {
            var text = text
            parsers.reversed().forEach { (head, last) in
                let latexRange = head.range.upperBound..<last.range.lowerBound
                let latex = text[latexRange]
                if head.tag != "$$" {
                    text.replaceSubrange(last.range, with: "$$")
                }
                var newLatex = String(latex)
                if let value = newLatex.data(using: .utf8)?.base64EncodedString() {
                    newLatex = value
                }
                text.replaceSubrange(latexRange, with: newLatex)
                if head.tag != "$$" {
                    text.replaceSubrange(head.range, with: "$$")
                }
            }
            return text
        } else {
            return text
        }
    }
    
    public static func removeNewLinePlaceholder(text: String) -> String {
        if let data = Data(base64Encoded: text) {
            return String(data: data, encoding: .utf8) ?? text
        } else {
            return text
        }
    }
}
