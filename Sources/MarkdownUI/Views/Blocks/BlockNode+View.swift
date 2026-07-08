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

    @State private var blockMargins: [Int: BlockMargin] = [:]

    var body: some View {
        VStack(alignment: self.textAlignment.alignment.horizontal, spacing: 0) {
            ForEach(nodeList) { nodeModel in
                Group {
                    if blockEquatableDisabled {
                        // 关闭 EquatableView:让 .textRenderer 这类环境驱动的重绘(打字机动画)能传到内部 Text。
                        BlockNodeView(model: nodeModel)
                    } else {
                        EquatableView(content: BlockNodeView(model: nodeModel))
                    }
                }
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
