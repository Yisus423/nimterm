## Vertical picker block with a header, input, menu, and footer lines.

import ../canvas
import ../geometry
import ../style
import ../widget
import ./menu

type
  Picker* = ref object of Widget
    header*: string ## Optional line painted above the input.
    input*: Widget ## Optional filter input rendered without owning its query.
    menu*: Menu ## Optional rows rendered between the input and footer lines.
    counter*: string ## Optional counter line painted below the menu.
    detail*: string ## Optional detail line painted below the counter.
    notice*: string ## Optional notice line painted below the detail.
    keys*: string ## Optional key hint line painted last.
    headerStyle*: Style ## Style used for the header line.
    counterStyle*: Style ## Style used for the counter line.
    detailStyle*: Style ## Style used for the detail line.
    noticeStyle*: Style ## Style used for the notice line.
    keysStyle*: Style ## Style used for the key hint line.

proc newPicker*(input: Widget = nil, menu: Menu = nil, header = "", counter = "",
                detail = "", notice = "", keys = "", headerStyle = defaultStyle(),
                counterStyle = defaultStyle(), detailStyle = defaultStyle(),
                noticeStyle = defaultStyle(), keysStyle = defaultStyle()): Picker =
  ## Creates a picker block whose caller owns the input and menu contents.
  Picker(input: input, menu: menu, header: header, counter: counter,
    detail: detail, notice: notice, keys: keys, headerStyle: headerStyle,
    counterStyle: counterStyle, detailStyle: detailStyle,
    noticeStyle: noticeStyle, keysStyle: keysStyle)

proc footerRows(widget: Picker): int =
  ## Counts the non-empty footer lines in their painted order.
  for line in [widget.counter, widget.detail, widget.notice, widget.keys]:
    if line.len > 0: inc result

proc childHeight(widget: Widget, width: int): int =
  ## Returns a child's natural height at the block's available width.
  if widget.isNil: return 0
  widget.measure(Constraints(maxSize: size(width, int.high))).h

proc paintLine(widget: Picker, canvas: var Canvas, row: int, text: string,
               style: Style) =
  ## Paints one clipped line only when its row belongs to the picker block.
  if row < widget.area.y or row >= widget.area.y + widget.area.h: return
  canvas.writeText(widget.area.x, row, text, style, widget.area.w)

method children*(widget: Picker): seq[Widget] =
  ## Returns the caller-owned input and menu as the picker's child widgets.
  if not widget.input.isNil: result.add widget.input
  if not widget.menu.isNil: result.add widget.menu

method focusable*(widget: Picker): bool =
  ## Keeps focus on the caller's input rather than on the picker block.
  false

method measure*(widget: Picker, constraints: Constraints): Size =
  ## Measures the header, input, menu, and footer lines as one vertical block.
  var width = 0
  var height = 0
  for line in [widget.header, widget.counter, widget.detail, widget.notice,
      widget.keys]:
    if line.len > 0:
      width = max(width, line.len)
      inc height
  if not widget.input.isNil:
    let measured = widget.input.measure(constraints)
    width = max(width, measured.w)
    height += measured.h
  if not widget.menu.isNil:
    let measured = widget.menu.measure(constraints)
    width = max(width, measured.w)
    height += measured.h
  constraints.clamp(size(width, height))

method paint*(widget: Picker, canvas: var Canvas) =
  ## Paints the picker in header, input, menu, counter, detail, notice, keys order.
  if widget.area.w <= 0 or widget.area.h <= 0: return
  let headerRows = if widget.header.len > 0: 1 else: 0
  let footer = widget.footerRows
  let contentRows = max(0, widget.area.h - headerRows - footer)
  let inputRows = min(childHeight(widget.input, widget.area.w), contentRows)
  let menuRows = max(0, contentRows - inputRows)
  var row = widget.area.y
  if widget.header.len > 0:
    widget.paintLine(canvas, row, widget.header, widget.headerStyle)
    inc row
  if not widget.input.isNil and inputRows > 0:
    widget.input.render(canvas, rect(widget.area.x, row, widget.area.w, inputRows))
  row += inputRows
  if not widget.menu.isNil and menuRows > 0:
    widget.menu.render(canvas, rect(widget.area.x, row, widget.area.w, menuRows))
  row += menuRows
  if widget.counter.len > 0:
    widget.paintLine(canvas, row, widget.counter, widget.counterStyle)
    inc row
  if widget.detail.len > 0:
    widget.paintLine(canvas, row, widget.detail, widget.detailStyle)
    inc row
  if widget.notice.len > 0:
    widget.paintLine(canvas, row, widget.notice, widget.noticeStyle)
    inc row
  if widget.keys.len > 0:
    widget.paintLine(canvas, row, widget.keys, widget.keysStyle)
