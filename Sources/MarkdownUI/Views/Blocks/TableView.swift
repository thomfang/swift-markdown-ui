import SwiftUI

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct TableView: View {
  @Environment(\.theme.table) private var table
  @Environment(\.tableBorderStyle.strokeStyle.lineWidth) private var borderWidth

  private let columnAlignments: [RawTableColumnAlignment]
  private let rows: [RawTableRow]

  // 打字机各 cell 偏移:同步 + 按 rows 记忆化(引用型 memo 存于 @State,body 内可安全读/写)。
  // 只有 rows 变化(内容首现/流式增长)才跑一次 cmark renderPlainText + cellOffsets,其余帧命中记忆化直接返回;
  // 绝不挂在 revealed 上,故流式 tail 关了 EquatableView、body 随 TimelineView 逐帧重评时也不会逐帧重算。
  // ★为何同步而非早先的 .task 异步回填:异步存在「offset 尚未算好」的空缓存帧,该帧所有 cell 落到隐藏分支
  //   → 整表文字瞬时清空、再逐格重打(视觉闪烁),且此额外的异步 @State 回填还会多触发一次布局重排。
  //   同步计算保证首帧即有正确 offset:table 结构/行高稳定,只有 cell 内文字逐字淡入,无清空闪。
  @State private var offsetMemo = TableOffsetMemo()

  init(columnAlignments: [RawTableColumnAlignment], rows: [RawTableRow]) {
    self.columnAlignments = columnAlignments
    self.rows = rows
  }

  var body: some View {
    self.table.makeBody(
      configuration: .init(
        label: .init(self.label),
        content: .init(block: .table(columnAlignments: self.columnAlignments, rows: self.rows))
      )
    )
  }

  private var label: some View {
    // 打字机:每个 cell 用其文本在「整表 plaintext」里的真实起始字符索引作 leaf offset,
    // 与 app 侧 revealed(= tail.renderPlainText().count 同源)同坐标系,避免逐 cell 累积漂移。
    let offsets = self.resolvedOffsets()
    return Grid(horizontalSpacing: self.borderWidth, verticalSpacing: self.borderWidth) {
      ForEach(0..<self.rowCount, id: \.self) { row in
        GridRow {
          ForEach(0..<self.columnCount, id: \.self) { column in
            TableCell(row: row, column: column, cell: self.rows[row].cells[column])
              .gridColumnAlignment(.init(self.columnAlignments[column]))
              .markdownTypewriterLeafOffset(Self.offsetValue(offsets, row: row, column: column))
          }
        }
      }
    }
    .padding(self.borderWidth)
    .tableDecoration(
      rowCount: self.rowCount,
      columnCount: self.columnCount,
      background: TableBackgroundView.init,
      overlay: TableBorderView.init
    )
  }

  /// 同步返回当前 rows 对应的 cell 偏移;仅在 rows 变化时重算(记忆化)。
  /// 这里改写的是引用型 memo 的属性(并非重置 @State 包装本身),不触发视图失效 → 无重渲染回环。
  private func resolvedOffsets() -> [[Int]] {
    if self.offsetMemo.rows != self.rows {
      self.offsetMemo.rows = self.rows
      self.offsetMemo.offsets = self.cellOffsets(in: self.tablePlainText)
    }
    return self.offsetMemo.offsets
  }

  private var rowCount: Int {
    self.rows.count
  }

  private var columnCount: Int {
    self.columnAlignments.count
  }

  /// 整表的 plaintext(与 app 侧 revealed = tail.renderPlainText().count 同源)。
  /// renderPlainText() 定义在 `[BlockNode]` 上,故包成单元素数组。
  private var tablePlainText: String {
    [BlockNode.table(columnAlignments: self.columnAlignments, rows: self.rows)].renderPlainText()
  }

  /// 每个 cell 文本在整表 plaintext 中按行优先顺序定位到的起始字符索引。
  /// 用游标顺序搜索:空 cell / 未命中回退到当前游标(不前进),保证单调不倒退。
  private func cellOffsets(in plainText: String) -> [[Int]] {
    var result: [[Int]] = []
    var searchStart = plainText.startIndex
    var cursorOffset = 0
    for row in 0..<self.rowCount {
      var rowOffsets: [Int] = []
      let cells = self.rows[row].cells
      for column in 0..<self.columnCount {
        let cellText = column < cells.count ? cells[column].content.renderPlainText() : ""
        if cellText.isEmpty {
          rowOffsets.append(cursorOffset)
          continue
        }
        if let range = plainText.range(of: cellText, range: searchStart..<plainText.endIndex) {
          let start = plainText.distance(from: plainText.startIndex, to: range.lowerBound)
          rowOffsets.append(start)
          searchStart = range.upperBound
          cursorOffset = plainText.distance(from: plainText.startIndex, to: range.upperBound)
        } else {
          rowOffsets.append(cursorOffset)
        }
      }
      result.append(rowOffsets)
    }
    return result
  }

  /// 同步记忆化下 offsets 必然覆盖当前 rows;越界仅作防御(理论不达)。
  /// 越界回退为「已完全揭示」偏移(极小值 → InlineText 里 local = revealed - offset 恒为大正数 → 全显),
  /// 而非早先的隐藏哨兵——绝不让某 cell 因取不到 offset 而清空。
  private static let fullyRevealedOffset = Int.min / 2

  private static func offsetValue(_ offsets: [[Int]], row: Int, column: Int) -> Int {
    guard row < offsets.count, column < offsets[row].count else { return fullyRevealedOffset }
    return offsets[row][column]
  }
}

/// TableView 打字机 offset 的记忆化缓存(引用型:允许在 body 内按 rows 变化同步重算而不触发视图失效)。
private final class TableOffsetMemo {
  var rows: [RawTableRow]?
  var offsets: [[Int]] = []
}

extension HorizontalAlignment {
  fileprivate init(_ rawTableColumnAlignment: RawTableColumnAlignment) {
    switch rawTableColumnAlignment {
    case .none, .left:
      self = .leading
    case .center:
      self = .center
    case .right:
      self = .trailing
    }
  }
}
