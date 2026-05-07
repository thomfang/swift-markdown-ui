import SwiftUI

struct CodeBlockView: View {
  @Environment(\.theme.codeBlock) private var codeBlock
  @Environment(\.codeSyntaxHighlighter) private var codeSyntaxHighlighter
  @Environment(\.markdownStreaming) private var streaming

  private let fenceInfo: String?
  private let content: String

  init(fenceInfo: String?, content: String) {
    self.fenceInfo = fenceInfo
    self.content = content.hasSuffix("\n") ? String(content.dropLast()) : content
  }

  var body: some View {
    self.codeBlock.makeBody(
      configuration: .init(
        language: self.fenceInfo,
        content: self.content,
        label: .init(self.label)
      )
    )
  }

  private var label: some View {
    // 流式中跳过语法高亮，避免每个 token 触发 Splash 全量 tokenize
    let text: Text = self.streaming
      ? Text(self.content)
      : self.codeSyntaxHighlighter.highlightCode(self.content, language: self.fenceInfo)
    return text
      .textStyleFont()
      .textStyleForegroundColor()
  }
}
