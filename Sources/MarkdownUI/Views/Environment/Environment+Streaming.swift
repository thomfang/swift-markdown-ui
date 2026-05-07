import SwiftUI

extension View {
  /// Marks the Markdown subtree as currently being streamed.
  ///
  /// When enabled, code blocks skip syntax highlighting and render plain text,
  /// avoiding the cost of re-running the syntax highlighter on every token.
  /// Set to `false` once streaming completes to restore highlighting.
  public func markdownStreaming(_ enabled: Bool) -> some View {
    self.environment(\.markdownStreaming, enabled)
  }
}

extension EnvironmentValues {
  var markdownStreaming: Bool {
    get { self[MarkdownStreamingKey.self] }
    set { self[MarkdownStreamingKey.self] = newValue }
  }
}

private struct MarkdownStreamingKey: EnvironmentKey {
  static let defaultValue: Bool = false
}
