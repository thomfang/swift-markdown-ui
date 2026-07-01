import SwiftUI

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct TableView: View {
  @Environment(\.theme.table) private var table
  @Environment(\.tableBorderStyle.strokeStyle.lineWidth) private var borderWidth

  private let columnAlignments: [RawTableColumnAlignment]
  private let rows: [RawTableRow]

  // 打字机各 cell 偏移缓存。只在内容变化(.task id)时算一次,绝不挂在 revealed 上 —— 否则
  // TableView 会随 TimelineView 逐帧失效并逐帧重跑 cmark renderPlainText + cellOffsets(引入卡顿)。
  @State private var cellOffsetCache: [[Int]] = []

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
    // 内容变化(首现/流式增长)时算一次各 cell 偏移存入 state。
    // ★id 必须用 cheap 的 `rows`(Equatable):流式 tail 关了 EquatableView,本视图 body 逐帧重评,
    //   若 id 用 tablePlainText 则每帧都跑一次 cmark 渲染算 id → 卡顿。rows 仅在内容增长时变,cmark 只在 task 体内跑一次。
    .task(id: self.rows) {
      let plain = self.tablePlainText
      let offsets = self.cellOffsets(in: plain)
      self.cellOffsetCache = offsets
    }
  }

  private var label: some View {
    // 打字机:每个 cell 用其文本在「整表 plaintext」里的真实起始字符索引作 leaf offset,
    // 与 app 侧 revealed(= tail.renderPlainText().count 同源)同坐标系,避免逐 cell 累积漂移。
    Grid(horizontalSpacing: self.borderWidth, verticalSpacing: self.borderWidth) {
      ForEach(0..<self.rowCount, id: \.self) { row in
        GridRow {
          ForEach(0..<self.columnCount, id: \.self) { column in
            TableCell(row: row, column: column, cell: self.rows[row].cells[column])
              .gridColumnAlignment(.init(self.columnAlignments[column]))
              .markdownTypewriterLeafOffset(Self.offsetValue(self.cellOffsetCache, row: row, column: column))
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

  /// cache 未覆盖到的 cell(内容刚增长、task 还没回填的那 1 帧)返回大哨兵 → 该 cell 暂时隐藏,
  /// 待 offset 算好再淡入,避免「新 cell 先整格全显一帧再重打」的闪烁。
  /// 非流式时 InlineText 无 revealed 不挂渲染器,offset 被忽略,哨兵无副作用。
  private static let unknownOffset = Int.max / 2

  private static func offsetValue(_ offsets: [[Int]], row: Int, column: Int) -> Int {
    guard row < offsets.count, column < offsets[row].count else { return unknownOffset }
    return offsets[row][column]
  }
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
