import Foundation

/// A protocol that represents any Markdown content.
public protocol MarkdownContentProtocol {
  var _markdownContent: MarkdownContent { get }
}

/// A Markdown content value.
///
/// A Markdown content value consists of a sequence of blocks – structural elements like paragraphs, blockquotes, lists,
/// headings, thematic breaks, and code blocks. Some blocks, like blockquotes and list items, contain other blocks; others,
/// like headings and paragraphs, have inline text, links, emphasized text, etc.
///
/// You can create a Markdown content value by passing a Markdown-formatted string to ``init(_:)``.
///
/// ```swift
/// let content = MarkdownContent("You can try **CommonMark** [here](https://spec.commonmark.org/dingus/).")
/// ```
///
/// Alternatively, you can build a Markdown content value using a domain-specific language for blocks and inline text.
///
/// ```swift
/// let content = MarkdownContent {
///   Paragraph {
///     "You can try "
///     Strong("CommonMark")
///     SoftBreak()
///     InlineLink("here", destination: URL(string: "https://spec.commonmark.org/dingus/")!)
///     "."
///   }
/// }
/// ```
///
/// Once you have created a Markdown content value, you can display it using a ``Markdown`` view.
///
/// ```swift
/// var body: some View {
///   Markdown(self.content)
/// }
/// ```
///
/// A Markdown view also offers initializers that take a Markdown-formatted string ``Markdown/init(_:baseURL:imageBaseURL:)-63py1``,
/// or a Markdown content builder ``Markdown/init(baseURL:imageBaseURL:content:)``, so you don't need to create a
/// Markdown content value before displaying it.
///
/// ```swift
/// var body: some View {
///   VStack {
///     Markdown("You can try **CommonMark** [here](https://spec.commonmark.org/dingus/).")
///     Markdown {
///       Paragraph {
///         "You can try "
///         Strong("CommonMark")
///         SoftBreak()
///         InlineLink("here", destination: URL(string: "https://spec.commonmark.org/dingus/")!)
///         "."
///       }
///     }
///   }
/// }
/// ```
public struct MarkdownContent: Equatable, MarkdownContentProtocol {
  /// Returns a Markdown content value with the sum of the contents of all the container blocks
  /// present in this content.
  ///
  /// You can use this property to access the contents of a blockquote or a list. Returns `nil` if
  /// there are no container blocks.
  public var childContent: MarkdownContent? {
    let children = self.blocks.map(\.children).flatMap { $0 }
    return children.isEmpty ? nil : .init(blocks: children)
  }

  public var _markdownContent: MarkdownContent { self }
  let blocks: [BlockNode]

  init(blocks: [BlockNode] = []) {
    self.blocks = blocks
  }

  init(block: BlockNode) {
    self.init(blocks: [block])
  }

  init(_ components: [MarkdownContentProtocol]) {
    self.init(blocks: components.map(\._markdownContent).flatMap(\.blocks))
  }

  /// Creates a Markdown content value from a Markdown-formatted string.
  /// - Parameter markdown: A Markdown-formatted string.
  public init(_ markdown: String) {
    self.init(blocks: .init(markdown: markdown))
  }

  /// Creates a Markdown content value composed of any number of blocks.
  /// - Parameter content: A Markdown content builder that returns the blocks that form the Markdown content.
  public init(@MarkdownContentBuilder content: () -> MarkdownContent) {
    self.init(blocks: content().blocks)
  }

  /// Renders this Markdown content value as a Markdown-formatted text.
  public func renderMarkdown() -> String {
    let result = self.blocks.renderMarkdown()
    return result.hasSuffix("\n") ? String(result.dropLast()) : result
  }

  /// Renders this Markdown content value as plain text.
  public func renderPlainText() -> String {
    let result = self.blocks.renderPlainText()
    return result.hasSuffix("\n") ? String(result.dropLast()) : result
  }

  /// Renders this Markdown content value as HTML code.
  public func renderHTML() -> String {
    self.blocks.renderHTML()
  }
}

extension MarkdownContent {
  /// 把内容按顶层块逐个拆成独立的 `MarkdownContent`,每个都可单独用 `Markdown(_:)` 渲染。
  /// 用于流式渲染:把已完成的块与最后一个未定块分开,前者冻结、只重渲后者。
  public var topLevelBlocks: [MarkdownContent] {
    self.blocks.map { MarkdownContent(block: $0) }
  }

  /// 把一组顶层块内容合并成单个 `MarkdownContent`。
  /// 合并后由同一个 `Markdown(_:)` 渲染,块间距与原文整体渲染保持一致。
  public init(merging contents: [MarkdownContent]) {
    self.init(blocks: contents.flatMap(\.blocks))
  }

  /// 当且仅当本内容是单个 code block(供流式判定末块类型)。
  /// 注意:cmark 把 fenced 与 indented code block 同归为 `.codeBlock`,且对未闭合围栏也产出 codeBlock;
  /// "是否 fenced、是否已闭合"无法从此处区分,需由调用方对原文做围栏扫描判断。
  public var isCodeBlock: Bool {
    guard self.blocks.count == 1, case .codeBlock = self.blocks[0] else { return false }
    return true
  }
}
