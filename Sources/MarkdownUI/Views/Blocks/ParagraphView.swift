import SwiftUI
 
struct ParagraphView: View {
    @Environment(\.theme.paragraph) private var paragraph
    @Environment(\.textStyle) private var textStyle

    private let content: [InlineNode]
    
    init(content: String) {
        self.init(
            content: [
                .text(content.hasSuffix("\n") ? String(content.dropLast()) : content)
            ]
        )
    }
    
    init(content: [InlineNode]) {
        self.content = content
    }

    private var attributes: AttributeContainer {
        var attributes = AttributeContainer()
        self.textStyle._collectAttributes(in: &attributes)
        return attributes
    }
    
    var body: some View {
        self.paragraph.makeBody(
            configuration: .init(
                label: .init(self.label),
                content: .init(block: .paragraph(content: self.content))
            )
        )
    }
    
    @ViewBuilder private var label: some View {
        // 段落里「整行只有一张图片」的行(由软/硬换行分隔,而非空行另起段落)应作块级图片整张渲染。
        // 否则它会留在同段被 InlineText 当行内附件(Text(Image))按原始尺寸塞入、超宽被裁 → 只显示一部分。
        // 仅当段落同时含「文字行」和「纯图片行」时才拆分;纯图片段落/纯文字段落维持原渲染(零回归)。
        let segments = Self.imageSegments(content)
        let hasImage = segments.contains { if case .image = $0 { return true } else { return false } }
        let hasInline = segments.contains { if case .inlines = $0 { return true } else { return false } }
        if hasImage, hasInline {
            TextStyleAttributesReader { attributes in
                let spacing = RelativeSize.rem(0.5).points(relativeTo: attributes.fontProperties)
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        self.segmentLabel(segment)
                    }
                }
            }
        } else {
            self.inlineLabel(content)
        }
    }

    /// 单个段落片段的视图:块级图片走 ImageView(等比缩放、整张显示),其余走原内联三选一。
    @ViewBuilder private func segmentLabel(_ segment: ParagraphSegment) -> some View {
        switch segment {
        case .image(let data):
            ImageView(data: data)
        case .inlines(let nodes):
            self.inlineLabel(nodes)
        }
    }

    /// 原有的「整段图片 / 图片流 / 内联文字」三选一,作用于一组内联节点。
    @ViewBuilder private func inlineLabel(_ nodes: [InlineNode]) -> some View {
        if let imageView = ImageView(nodes) {
            imageView
        } else if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *),
                  let imageFlow = ImageFlow(nodes)
        {
            imageFlow
        } else {
            InlineText(nodes, fontSize: attributes.fontProperties?.size ?? 16)
        }
    }
}

extension ParagraphView {
    enum ParagraphSegment {
        /// 一组内联节点(文字、行内图片、行内公式等),按原内联逻辑渲染。
        case inlines([InlineNode])
        /// 独占一行的单张图片,提升为块级图片整张渲染。
        case image(RawImageData)
    }

    /// 把段落内联节点按软/硬换行切成「行」,再把「整行只有一张图片」的行提升成 `.image`,
    /// 相邻的文字/混排行(连同其换行)合并回单个 `.inlines`(保持普通段落的换行与排版不变)。
    static func imageSegments(_ inlines: [InlineNode]) -> [ParagraphSegment] {
        // 1) 切行,保留行尾 break 以便文字行还原。
        var lines: [(nodes: [InlineNode], breakNode: InlineNode?)] = []
        var current: [InlineNode] = []
        for node in inlines {
            switch node {
            case .softBreak, .lineBreak:
                lines.append((current, node))
                current = []
            default:
                current.append(node)
            }
        }
        lines.append((current, nil))

        // 2) 行分类 + 合并。
        var segments: [ParagraphSegment] = []
        var pending: [InlineNode] = []
        func flushPending() {
            // 丢掉遗留在末尾的 break(图片前 / 段末),避免多余空行。
            while case .some(let last) = pending.last, last.isBreak {
                pending.removeLast()
            }
            if !pending.isEmpty {
                segments.append(.inlines(pending))
                pending = []
            }
        }
        for line in lines {
            if let data = Self.standaloneImageData(line.nodes) {
                flushPending()
                segments.append(.image(data))
            } else {
                pending.append(contentsOf: line.nodes)
                if let breakNode = line.breakNode {
                    pending.append(breakNode)
                }
            }
        }
        flushPending()
        return segments
    }

    /// 行内忽略纯空白文本后恰好是单张图片(或单图链接)→ 返回其图片数据,否则 nil。
    private static func standaloneImageData(_ nodes: [InlineNode]) -> RawImageData? {
        let meaningful = nodes.filter { node in
            if case let .text(text) = node, text.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
            return true
        }
        guard meaningful.count == 1 else { return nil }
        return meaningful.first?.imageData
    }
}

extension InlineNode {
    /// 是否软/硬换行节点。
    fileprivate var isBreak: Bool {
        switch self {
        case .softBreak, .lineBreak:
            return true
        default:
            return false
        }
    }
}
