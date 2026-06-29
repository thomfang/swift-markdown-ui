import SwiftUI

extension InlineText {
    enum NodeType: Hashable {
        case latexBlock(content: String)
        case other([InlineNode])
    }
    
    enum ImageNodeType: Hashable {
        case latexBlock(content: String)
        case image(InlineNode)
    }
}

struct InlineText: View {
    @Environment(\.inlineImageProvider) private var inlineImageProvider
    @Environment(\.baseURL) private var baseURL
    @Environment(\.imageBaseURL) private var imageBaseURL
    @Environment(\.softBreakMode) private var softBreakMode
    @Environment(\.paragraphLineSpacing) private var paragraphLineSpacing
    @Environment(\.theme) private var theme
    @Environment(\.textStyle) private var textStyle
    @Environment(\.markdownTypewriterRevealed) private var typewriterRevealed

    @State private var latexImages: [String: (Image, CGSize)]
    @State private var inlineImages: [String: Image] = [:]
    @State private var loadInlineImageTasks: [String: Task<Void, Never>] = [:]
    
    private let inlines: [InlineNode]
    
    init(_ inlines: [InlineNode], fontSize: CGFloat) {
        self.inlines = inlines
        _latexImages = State<[String : (Image, CGSize)]>(initialValue: InlineText.latexCacheImages(inlines: inlines, fontSize: fontSize))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: paragraphLineSpacing) {
            let items = separateLatexFormulaBlock
            ForEach(0..<items.count, id: \.self) { index in
                let nodeType = items[index]
                switch nodeType {
                case .latexBlock(let content):
                    LatexView(content: content)
                case .other(let inlines):
                    TextStyleAttributesReader { attributes in
                        let text = inlines.renderText(
                            baseURL: self.baseURL,
                            textStyles: .init(
                                code: self.theme.code,
                                emphasis: self.theme.emphasis,
                                strong: self.theme.strong,
                                strikethrough: self.theme.strikethrough,
                                link: self.theme.link
                            ),
                            images: self.inlineImages,
                            latexImages: self.latexImages,
                            softBreakMode: self.softBreakMode,
                            attributes: attributes,
                            linkTextBuilder: self.theme.siderLinkTextBuilder
                        )
                        // 打字机:直接把 TextRenderer 套在叶子 Text 上(套在容器上传不进来)。
                        self.typewriterRendered(text)
                    }
                    .lineSpacing(paragraphLineSpacing)
                }
            }
        }
        .task(id: self.inlines) {
            Task {
                await loadInlineLatexImages()
            }
            Task {
                await loadInlineImages()
            }
        }
    }
    
    /// 给叶子 Text 套打字机渲染器(仅当环境里设了 revealed 且 iOS 18+);否则原样返回。
    @ViewBuilder
    private func typewriterRendered(_ text: Text) -> some View {
        if #available(iOS 18.0, *), let revealed = self.typewriterRevealed {
            text.textRenderer(TypewriterTextRenderer(revealed: revealed))
        } else {
            text
        }
    }

    private func loadInlineLatexImages() async {
        let cacheKeys = InlineText.latexCacheImages(inlines: inlines, fontSize: fontSize).keys
        let currentKeys = latexImages.keys
        Set(currentKeys).subtracting(cacheKeys).forEach { key in
            latexImages.removeValue(forKey: key)
        }
        let loadImages = InlineText.loadImages(inlines: inlines)
        loadImages.forEach { imageNodeType in
            if case .latexBlock(let content) = imageNodeType {
                if latexImages[content] == nil && SVGCache.shared.canKey(key: content) {
                    if let image = SVGCache.shared.read(key: content, fontSize: fontSize) {
                        latexImages[content] = (Image(uiImage: image), image.size)
                    } else {
                        if loadInlineImageTasks[content] == nil {
                            let task = Task {
                                do {
                                    let image = try await LatexRenderer.image(with: content, fontSize: fontSize)
                                    latexImages[content] = (Image(uiImage: image), image.size)
                                } catch let error {
                                    debugPrint(error)
                                }
                                loadInlineImageTasks.removeValue(forKey: content)
                            }
                            loadInlineImageTasks[content] = task
                        }
                    }
                }
            }
        }
    }
    
    private func loadInlineImages() async {
        InlineText.loadImages(inlines: inlines).forEach { imageNodeType in
            if case .image(let inlineNode) = imageNodeType, let imageInfo = inlineNode.imageData {
                if inlineImages[imageInfo.source] == nil {
                    if loadInlineImageTasks[imageInfo.source] == nil {
                        let task = Task {
                            guard let url = URL.markdownImageURL(source: imageInfo.source, relativeTo: self.imageBaseURL) else {
                                return
                            }
                            do {
                                let image = try await self.inlineImageProvider.image(with: url, label: imageInfo.alt)
                                inlineImages[imageInfo.source] = image
                            } catch let error {
                                debugPrint(error)
                            }
                            loadInlineImageTasks.removeValue(forKey: imageInfo.source)
                        }
                        loadInlineImageTasks[imageInfo.source] = task
                    }
                }
            }
        }
    }
}

extension InlineText {
    
    private var attributes: AttributeContainer {
      var attributes = AttributeContainer()
      self.textStyle._collectAttributes(in: &attributes)
      return attributes
    }
    
    var fontSize: CGFloat {
        attributes.fontProperties?.size ?? 16
    }
    
    var separateLatexFormulaBlock: [InlineText.NodeType] {
        var items: [InlineNode] = []
        var alls: [InlineText.NodeType] = []
        inlines.forEach { inlineNode in
            if case .latex(_, let array) = inlineNode {
                array.forEach { latexNode in
                    switch latexNode {
                    case .text(let text):
                        items.append(InlineNode.text(text))
                    case .latex(let content, let isBlock):
                        if isBlock {
                            if items.isEmpty == false {
                                alls.append(.other(items))
                                items.removeAll()
                            }
                            alls.append(.latexBlock(content: content))
                        } else {
                            items.append(InlineNode.latex(rawContent: content, [LatexNode.latex(content: content, isBlock: isBlock)]))
                        }
                    }
                }
            } else {
                if case .lineBreak = inlineNode {
                    if items.isEmpty == false {
                        alls.append(.other(items))
                        items.removeAll()
                    }
//                    alls.append(.other([inlineNode]))
                } else {
                    items.append(inlineNode)
                }
            }
        }
        if items.isEmpty == false {
            alls.append(.other(items))
        }
        return alls
    }
}

extension InlineText {
    
    static func loadImages(inlines: [InlineNode]) -> [ImageNodeType] {
        var loadImages: [ImageNodeType] = []
        inlines.forEach { inlineNode in
            switch inlineNode {
            case .image:
                loadImages.append(.image(inlineNode))
            case .latex(_, let array):
                array.forEach { latexNode in
                    if case .latex(let content, let isBlock) = latexNode {
                        if isBlock == false {
                            loadImages.append(.latexBlock(content: content))
                        }
                    }
                }
            case .strong(let children):
                let nodes = InlineText.loadImages(inlines: children)
                if nodes.isEmpty == false {
                    loadImages.append(contentsOf: nodes)
                }
            case .strikethrough(let children):
                let nodes = InlineText.loadImages(inlines: children)
                if nodes.isEmpty == false {
                    loadImages.append(contentsOf: nodes)
                }
            case .emphasis(let children):
                let nodes = InlineText.loadImages(inlines: children)
                if nodes.isEmpty == false {
                    loadImages.append(contentsOf: nodes)
                }
            default: break
            }
        }
        return loadImages
    }
    
    static func latexCacheImages(inlines: [InlineNode], fontSize: CGFloat) -> [String: (Image, CGSize)] {
        var latexImages: [String: (Image, CGSize)] = [:]
        loadImages(inlines: inlines).forEach { obj in
            if case .latexBlock(let content) = obj {
                if let image = SVGCache.shared.read(key: content, fontSize: fontSize) {
                    latexImages[content] = (Image(uiImage: image), image.size)
                }
            }
        }
        return latexImages
    }
}

/// 打字机 TextRenderer:按 revealed(已揭示字数,连续 Double)顺序揭示每个 glyph(RunSlice),
/// 跨越边界处 1 字宽软淡入;始终占满布局尺寸(只是后段不画),不改变文本高度。
@available(iOS 18.0, *)
struct TypewriterTextRenderer: TextRenderer, Animatable {
    var revealed: Double
    var animatableData: Double {
        get { revealed }
        set { revealed = newValue }
    }

    /// 尾部渐隐宽度(glyph 数):靠近 revealed 的这一批字做淡入,越宽淡入越明显。
    private static let fadeWidth: Double = 12
    /// 渐入时的上浮距离(pt)。
    private static let rise: Double = 6

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let slices = layout.flatMap { line in line.flatMap { run in run } }
        guard !slices.isEmpty else { return }
        for (index, slice) in slices.enumerated() {
            // 每个字的淡入进度:在 revealed 之前 fadeWidth 个字范围内从 0→1。
            let progress = (revealed - Double(index)) / Self.fadeWidth
            let opacity = min(max(progress, 0), 1)
            guard opacity > 0 else { continue }
            var sliceContext = context
            sliceContext.opacity = opacity
            // 淡入同时轻微上浮(未完全显示时下移,显示完归位)。
            sliceContext.translateBy(x: 0, y: (1 - opacity) * Self.rise)
            sliceContext.draw(slice)
        }
    }
}

