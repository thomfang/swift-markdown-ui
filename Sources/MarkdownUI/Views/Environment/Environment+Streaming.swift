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

extension View {
  /// Disables the per-block `EquatableView` wrapping inside the block list.
  ///
  /// By default each top-level block is wrapped in an `EquatableView` keyed by its
  /// node content, so an unchanged block is never re-rendered. That caching also
  /// blocks environment-driven redraws (e.g. an animating `.textRenderer`) from
  /// reaching the cached text. Enable this on a subtree that needs to animate its
  /// text via a renderer (such as a typewriter effect on the streaming block).
  public func markdownBlockEquatableDisabled(_ disabled: Bool = true) -> some View {
    self.environment(\.markdownBlockEquatableDisabled, disabled)
  }
}

extension EnvironmentValues {
  var markdownBlockEquatableDisabled: Bool {
    get { self[MarkdownBlockEquatableDisabledKey.self] }
    set { self[MarkdownBlockEquatableDisabledKey.self] = newValue }
  }
}

private struct MarkdownBlockEquatableDisabledKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension View {
  /// Applies a typewriter reveal to the inline text in this subtree.
  ///
  /// When set to a non-nil value, every `InlineText` applies a `TextRenderer` (iOS 18+)
  /// that reveals glyphs up to `revealed` (a continuous glyph count), fading in at the edge.
  /// Drive `revealed` over time (e.g. from a `TimelineView`) for a live typewriter effect.
  /// Pair with `markdownBlockEquatableDisabled()` so per-frame updates actually re-render.
  public func markdownTypewriterRevealed(_ revealed: Double?) -> some View {
    self.environment(\.markdownTypewriterRevealed, revealed)
  }
}

extension EnvironmentValues {
  var markdownTypewriterRevealed: Double? {
    get { self[MarkdownTypewriterRevealedKey.self] }
    set { self[MarkdownTypewriterRevealedKey.self] = newValue }
  }
}

private struct MarkdownTypewriterRevealedKey: EnvironmentKey {
  static let defaultValue: Double? = nil
}
