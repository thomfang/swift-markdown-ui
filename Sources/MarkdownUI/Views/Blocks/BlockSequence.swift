import SwiftUI

struct ElementView<Element: Equatable, Content: View>: View, Equatable {
    
    static func == (lhs: ElementView<Element, Content>, rhs: ElementView<Element, Content>) -> Bool {
        return rhs.element == lhs.element && lhs.index == rhs.index
    }
    let index: Int
    let element: Element
    @ViewBuilder
    let content: () -> Content
    var body: some View {
        content()
    }
}

struct BlockSequence<Data, Content>: View
where
Data: Sequence,
Data.Element: Hashable,
Content: View
{
    @Environment(\.multilineTextAlignment) private var textAlignment
    @Environment(\.tightSpacingEnabled) private var tightSpacingEnabled
    
    @State private var blockMargins: [Int: BlockMargin] = [:]
    
    private let data: [Indexed<Data.Element>]
    private let content: (Int, Data.Element) -> Content
    
    init(
        _ data: Data,
        @ViewBuilder content: @escaping (_ index: Int, _ element: Data.Element) -> Content
    ) {
        self.data = data.indexed()
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: self.textAlignment.alignment.horizontal, spacing: 0) {
            ForEach(self.data, id: \.self) { element in
                // ★onPreferenceChange 与 padding 必须挂在 ElementView 外层:ElementView 是
                //  Equatable(只比 element+index),若把依赖 blockMargins @State 的 top padding 包进它
                //  内部,首帧 blockMargins 为空算出 0 后就被判等缓存,后续 margin 更新读不到 → item 间距
                //  恒为 0、listItem 的 markdownMargin 失效。对齐 BlockListView:缓存只包块内容,间距在外。
                ElementView(index: element.index, element: element, content: {
                    self.content(element.index, element.value)
                })
                .onPreferenceChange(BlockMarginsPreference.self) { value in
                    self.blockMargins[element.hashValue] = value
                }
                .padding(.top, self.topPaddingLength(for: element) ?? 0)
            }
        }
    }
    
    private func topPaddingLength(for element: Indexed<Data.Element>) -> CGFloat? {
        guard element.index > 0 else {
            return 0
        }
        
        let topSpacing = self.blockMargins[element.hashValue]?.top
        let predecessor = self.data[element.index - 1]
        // 子列表紧贴上一行:当前块是列表(如列表项标题段落后的嵌套子列表)时,忽略前一块的下 margin。
        // 否则前块(父项标题段落)的下 margin 会经下方 max() 主导「父↔子」间距,使主题里 list 的
        // 上 margin / relativePadding 失效;此时父↔子间距改由列表自身的上 margin / relativePadding 精确控制。
        let currentIsList = (element.value as? BlockNode)?.isList ?? false
        let predecessorBottomSpacing =
        (self.tightSpacingEnabled || currentIsList) ? 0 : self.blockMargins[predecessor.hashValue]?.bottom

        return [topSpacing, predecessorBottomSpacing]
            .compactMap { $0 }
            .max()
    }
}

 extension BlockSequence where Data == [BlockNode], Content == BlockNode {
     init(_ blocks: [BlockNode]) {
         self.init(blocks) { $1 }
     }
 }

extension TextAlignment {
    var alignment: Alignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}
