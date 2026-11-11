import std/[strutils, unittest]
import nimterm/[canvas, geometry, style, widget, widgets]
import nimterm/widgets/picker

suite "picker widget":
  test "paints the block in pi's exact top-to-bottom order":
    let input = newInput()
    input.setText("filter")
    let menu = newMenu(@[
      MenuItem(label: "first row"),
      MenuItem(label: "second row")])
    let picker = newPicker(input = input, menu = menu,
      header = "Only showing models from configured providers.",
      counter = "(20/105)",
      detail = "Model Name: GLM-5.3",
      notice = "Model catalogs refreshed.",
      keys = "Enter to select · Escape/Ctrl+C to cancel")
    var canvas = newCanvas(size(80, 8))
    picker.render(canvas, rect(0, 0, 80, 8))
    check canvas.lineText(0).strip == "Only showing models from configured providers."
    check canvas.lineText(1).startsWith("> filter")
    check "first row" in canvas.lineText(2)
    check "second row" in canvas.lineText(3)
    check canvas.lineText(4).strip == "(20/105)"
    check canvas.lineText(5).strip == "Model Name: GLM-5.3"
    check canvas.lineText(6).strip == "Model catalogs refreshed."
    check canvas.lineText(7).strip == "Enter to select · Escape/Ctrl+C to cancel"
    check input.text == "filter"

  test "skips empty lines without leaving gaps":
    let input = newInput()
    input.setText("query")
    let menu = newMenu(@[MenuItem(label: "only row")])
    let picker = newPicker(input = input, menu = menu, header = "",
      counter = "counter", detail = "", notice = "notice", keys = "")
    var canvas = newCanvas(size(40, 4))
    picker.render(canvas, rect(0, 0, 40, 4))
    check canvas.lineText(0).startsWith("> query")
    check "only row" in canvas.lineText(1)
    check canvas.lineText(2).strip == "counter"
    check canvas.lineText(3).strip == "notice"

  test "clips a long line to the block width":
    let picker = newPicker(header = "abcdefghijklmnop")
    var canvas = newCanvas(size(12, 1))
    picker.render(canvas, rect(2, 0, 8, 1))
    check canvas.lineText(0) == "  abcdefgh  "

  test "measures its present lines and child heights":
    let input = newInput()
    input.setText("one\ntwo")
    let menu = newMenu(@[
      MenuItem(label: "first row"),
      MenuItem(label: "second row")])
    let picker = newPicker(input = input, menu = menu, header = "header",
      counter = "counter")
    check picker.measure(unconstrained()).h == 6
    check picker.measure(Constraints(maxSize: size(80, 4))).h == 4
    check picker.measure(Constraints(maxSize: size(80, 0))).h == 0
    check not picker.focusable
    check picker.headerStyle == defaultStyle()
    check picker.counterStyle == defaultStyle()
    check picker.detailStyle == defaultStyle()
    check picker.noticeStyle == defaultStyle()
    check picker.keysStyle == defaultStyle()

suite "menu hardening":
  test "a negative selected index cannot produce a negative scroll offset":
    let menu = newMenu(@[MenuItem(label: "row")])
    menu.selected = -1
    var canvas = newCanvas(size(10, 2))
    menu.render(canvas, rect(0, 0, 10, 2))
    check menu.scrollOffset >= 0
    check "row" in canvas.plainText
