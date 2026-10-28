import Foundation

enum BlockNode: Hashable {
  case blockquote(children: [BlockNode])
  case bulletedList(isTight: Bool, items: [RawListItem])
  case numberedList(isTight: Bool, start: Int, items: [RawListItem])
  case taskList(isTight: Bool, items: [RawTaskListItem])
  case codeBlock(fenceInfo: String?, content: String, sourceLine: Int? = nil)
  case htmlBlock(content: String)
  case paragraph(content: [InlineNode])
  case heading(level: Int, content: [InlineNode])
  case table(columnAlignments: [RawTableColumnAlignment], rows: [RawTableRow])
  case thematicBreak

  // Source locations are rendering metadata, not Markdown semantic content.
  // Preserve equality with content constructed through the public DSL.
  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case let (.blockquote(a), .blockquote(b)): return a == b
    case let (.bulletedList(a, b), .bulletedList(c, d)): return a == c && b == d
    case let (.numberedList(a, b, c), .numberedList(d, e, f)): return a == d && b == e && c == f
    case let (.taskList(a, b), .taskList(c, d)): return a == c && b == d
    case let (.codeBlock(a, b, _), .codeBlock(c, d, _)): return a == c && b == d
    case let (.htmlBlock(a), .htmlBlock(b)): return a == b
    case let (.paragraph(a), .paragraph(b)): return a == b
    case let (.heading(a, b), .heading(c, d)): return a == c && b == d
    case let (.table(a, b), .table(c, d)): return a == c && b == d
    case (.thematicBreak, .thematicBreak): return true
    default: return false
    }
  }

  func hash(into hasher: inout Hasher) {
    switch self {
    case .blockquote(let a): hasher.combine(0); hasher.combine(a)
    case .bulletedList(let a, let b): hasher.combine(1); hasher.combine(a); hasher.combine(b)
    case .numberedList(let a, let b, let c): hasher.combine(2); hasher.combine(a); hasher.combine(b); hasher.combine(c)
    case .taskList(let a, let b): hasher.combine(3); hasher.combine(a); hasher.combine(b)
    case .codeBlock(let a, let b, _): hasher.combine(4); hasher.combine(a); hasher.combine(b)
    case .htmlBlock(let a): hasher.combine(5); hasher.combine(a)
    case .paragraph(let a): hasher.combine(6); hasher.combine(a)
    case .heading(let a, let b): hasher.combine(7); hasher.combine(a); hasher.combine(b)
    case .table(let a, let b): hasher.combine(8); hasher.combine(a); hasher.combine(b)
    case .thematicBreak: hasher.combine(9)
    }
  }

  var codeBlockSourceLines: [Int?] {
    if case .codeBlock(_, _, let line) = self { return [line] }
    return children.flatMap(\.codeBlockSourceLines)
  }
}

extension BlockNode {
  var children: [BlockNode] {
    switch self {
    case .blockquote(let children):
      return children
    case .bulletedList(_, let items):
      return items.map(\.children).flatMap { $0 }
    case .numberedList(_, _, let items):
      return items.map(\.children).flatMap { $0 }
    case .taskList(_, let items):
      return items.map(\.children).flatMap { $0 }
    default:
      return []
    }
  }

  var isParagraph: Bool {
    guard case .paragraph = self else { return false }
    return true
  }

  /// 是否为列表块(有序 / 无序 / 任务列表)。
  var isList: Bool {
    switch self {
    case .bulletedList, .numberedList, .taskList:
      return true
    default:
      return false
    }
  }
}

struct RawListItem: Hashable {
  let children: [BlockNode]
}

struct RawTaskListItem: Hashable {
  let isCompleted: Bool
  let children: [BlockNode]
}

enum RawTableColumnAlignment: Character {
  case none = "\0"
  case left = "l"
  case center = "c"
  case right = "r"
}

struct RawTableRow: Hashable {
  let cells: [RawTableCell]
}

struct RawTableCell: Hashable {
  let content: [InlineNode]
}
