import SwiftUI

 extension BlockNode: View {
     var body: some View {
         Group {
             switch self {
             case .blockquote(let children):
                 BlockquoteView(children: children)
             case .bulletedList(let isTight, let items):
                 BulletedListView(isTight: isTight, items: items)
             case .numberedList(let isTight, let start, let items):
                 NumberedListView(isTight: isTight, start: start, items: items)
             case .taskList(let isTight, let items):
                 TaskListView(isTight: isTight, items: items)
             case .codeBlock(let fenceInfo, let content):
                 CodeBlockView(fenceInfo: fenceInfo, content: content)
             case .htmlBlock(let content):
                 ParagraphView(content: content)
             case .paragraph(let content):
                 ParagraphView(content: content)
             case .heading(let level, let content):
                 HeadingView(level: level, content: content)
             case .table(let columnAlignments, let rows):
                 if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                     TableView(columnAlignments: columnAlignments, rows: rows)
                 }
             case .thematicBreak:
                 ThematicBreakView()
             }
         }
     }
 }

// MARK: - BlockListView
struct BlockListView: View {
    private let nodeList: [BlockNodeModel]
    
    init(nodes: [BlockNode]) {
      nodeList = nodes.enumerated().map {
          BlockNodeModel(index: $0, node: $1)
      }
    }
    
    @Environment(\.multilineTextAlignment) private var textAlignment
    @Environment(\.tightSpacingEnabled) private var tightSpacingEnabled
    @Environment(\.markdownBlockEquatableDisabled) private var blockEquatableDisabled
    @Environment(\.markdownTypewriterRevealed) private var typewriterRevealed
    @Environment(\.markdownTypewriterLeafOffset) private var baseLeafOffset

    @State private var blockMargins: [Int: BlockMargin] = [:]
    // 打字机顺序揭示:激活时给每个顶层块设「块起始 glyph 偏移」,使多块共用一个 revealed 时按阅读顺序
    // 逐块揭示(否则各块都从 revealed-0 起 → 同时揭示)。按 nodes 记忆化,仅内容变化才重算,逐帧命中缓存。
    @State private var offsetMemo = BlockTypewriterOffsetMemo()

    var body: some View {
        let leafOffsets = self.resolvedLeafOffsets()
        return VStack(alignment: self.textAlignment.alignment.horizontal, spacing: 0) {
            ForEach(nodeList) { nodeModel in
                Group {
                    if blockEquatableDisabled {
                        // 关闭 EquatableView:让 .textRenderer 这类环境驱动的重绘(打字机动画)能传到内部 Text。
                        BlockNodeView(model: nodeModel)
                    } else {
                        EquatableView(content: BlockNodeView(model: nodeModel))
                    }
                }
                // 顺序揭示:把本块起始偏移叠加到继承基准,传给块内 InlineText(revealed - leafOffset)。
                .markdownTypewriterLeafOffset(self.leafOffset(leafOffsets, index: nodeModel.index))
                .onPreferenceChange(BlockMarginsPreference.self) { value in
                    self.blockMargins[nodeModel.hashValue] = value
                }
                // margin 未知(块首现、preference 尚未上报)时回退 0 而非 16,与 BlockSequence 对齐。
                // 用 16 会让新块首帧撑出 16pt、下一帧回填真实 margin(多数 < 16)→ 内容「向上跳」;
                // 用 0 则新块首帧贴紧、下一帧只向下展开到真实 margin,与流式增长方向一致,消除向上跳。
                // 最终布局不变(margin 上报后即为真实值);仅影响首帧那一瞬的过渡方向。
                .padding(.top, self.topPaddingLength(for: nodeModel) ?? 0)
            }
        }
    }

    /// 揭示激活时返回每个顶层块的起始 glyph 偏移(与 app 侧 revealed = 整段 renderPlainText().count 同坐标);
    /// 未激活(revealed==nil)返回空 → leafOffset 保持继承基准(零副作用、零 cmark 开销)。
    private func resolvedLeafOffsets() -> [Int] {
        guard self.typewriterRevealed != nil else { return [] }
        let nodes = self.nodeList.map(\.node)
        if self.offsetMemo.nodes != nodes {
            self.offsetMemo.nodes = nodes
            self.offsetMemo.offsets = Self.computeLeafOffsets(nodes)
        }
        return self.offsetMemo.offsets
    }

    /// offset_i = 整段 plaintext 长度 − blocks[i...] 的 plaintext 长度 = 块 i 在整段中的起始字符索引。
    /// 用后缀差而非前缀和:精确落在整段坐标(块间分隔符归入前缀),避免逐块累积漂移。
    private static func computeLeafOffsets(_ nodes: [BlockNode]) -> [Int] {
        guard !nodes.isEmpty else { return [] }
        let whole = nodes.renderPlainText().count
        var offsets: [Int] = []
        offsets.reserveCapacity(nodes.count)
        for i in nodes.indices {
            let suffix = Array(nodes[i...]).renderPlainText().count
            offsets.append(whole - suffix)
        }
        return offsets
    }

    /// 激活时叠加到继承的 baseLeafOffset(支持嵌套);未激活或越界回退 baseLeafOffset(无副作用)。
    private func leafOffset(_ offsets: [Int], index: Int) -> Int {
        guard index < offsets.count else { return self.baseLeafOffset }
        return self.baseLeafOffset + offsets[index]
    }
    
    private func topPaddingLength(for nodeModel: BlockNodeModel) -> CGFloat? {
        guard nodeModel.index > 0 else {
            return 0
        }
        
        let topSpacing = self.blockMargins[nodeModel.hashValue]?.top
        let predecessor = self.nodeList[nodeModel.index - 1]
        let predecessorBottomSpacing =
        self.tightSpacingEnabled ? 0 : self.blockMargins[predecessor.hashValue]?.bottom
        
        return [topSpacing, predecessorBottomSpacing]
            .compactMap { $0 }
            .max()
    }
}

// MARK: - General Block
class BlockNodeModel: ObservableObject, Hashable, Identifiable {
    let index: Int
    let node: BlockNode
    
    init(index: Int, node: BlockNode) {
        self.index = index
        self.node = node
    }
    
    static func == (lhs: BlockNodeModel, rhs: BlockNodeModel) -> Bool {
        return lhs.node == rhs.node
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.node)
    }
    
    var id: Int {
        index
    }
}

/// BlockListView 打字机顺序揭示 offset 的记忆化(引用型:body 内按 nodes 变化同步重算,不触发视图失效)。
private final class BlockTypewriterOffsetMemo {
    var nodes: [BlockNode]?
    var offsets: [Int] = []
}

struct BlockNodeView: View {
    let model: BlockNodeModel
    
    var body: some View {
        model.node
    }
}

extension BlockNodeView: Equatable {
    static func == (lhs: BlockNodeView, rhs: BlockNodeView) -> Bool {
        return lhs.model.node == rhs.model.node
    }
}
