import Foundation

extension URL {
  /// Markdown image/link 源串到 URL 的鲁棒解析。
  /// - 优先走标准 URL(string:) 解析（http/https/file:// 等带 scheme 的 URL）
  /// - 失败时若是绝对路径（以 "/" 开头），用 URL(fileURLWithPath:) 处理
  ///   兼容含空格、`~`、特殊字符的本地文件路径，例如 LLM 生成的：
  ///   /var/mobile/Library/Mobile Documents/.../generated-images/foo.png
  /// - 仍失败时尝试百分号编码后再解析
  static func markdownImageURL(source: String, relativeTo baseURL: URL?) -> URL? {
    // 1. 含 scheme 的 URL：http/https/file:// 等，原样返回
    if let url = URL(string: source, relativeTo: baseURL), url.scheme != nil {
      return url
    }
    // 2. 绝对路径：source 可能已被 SiderMarkdown 预处理成 `/var/.../Mobile%20Documents/...`
    //    需要 removingPercentEncoding 还原为真实文件路径再构造 file URL
    if source.hasPrefix("/") {
      let decoded = source.removingPercentEncoding ?? source
      return URL(fileURLWithPath: decoded)
    }
    // 3. 兜底：百分号编码后再尝试解析
    if let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let url = URL(string: encoded, relativeTo: baseURL) {
      return url
    }
    return nil
  }
}
