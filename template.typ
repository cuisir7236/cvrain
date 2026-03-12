// vRain 古籍刻本风格直排电子书制作工具 - 最终版（天头页码反转 + 页脚书名）
// 适用 Typst 0.14
// 功能：生成仿古籍直排 PDF，支持正文楷体、批注宋体（双行夹注）、竖排标点自动转换、
//       标点位置微调、批注两列间距可调，并可添加背景图。
// 说明：行序从上到下，批注按“先右列后左列、自上而下”正确排列。

#let vrain(
  // ----- 书籍基本信息 -----
  title: "未命名",                // 书名（显示于页脚）

  // ----- 版面布局参数 -----
  canvas: (
    width: 842pt,                // 页面宽度
    height: 595pt,               // 页面高度
    margins: (top: 200pt, bottom: 50pt, left: 50pt, right: 50pt), // 页边距
    columns: 24,                   // 正文列数
    center-width: 120pt            // 中缝宽度
  ),
  rows: 30,                        // 每列行数
  row-delta-y: 10pt,               // 行间纵向微调

  // ----- 字体与字号 -----
  text-font-size: 42pt,            // 正文字号
  comment-font-size: 30pt,         // 批注字号
  font-rotate: 0,                  // 字符旋转角度

  // ----- 颜色 -----
  text-font-color: black,
  comment-font-color: red,

  // ----- 标题（天头）样式（现用于页码）-----
  if-tpcenter: 1,                  // 是否居中（1=居中，0=居左）
  title-font-size: 42pt,           // 天头字号（页码字号）
  title-font-color: black,         // 天头颜色（页码颜色）
  title-y: 1800pt,                 // 天头基线 Y 坐标
  title-ydis: 1.0,                 // 天头字符垂直间距因子

  // ----- 页脚样式（现用于书名）-----
  pager-font-size: 30pt,           // 页脚字号（书名）
  pager-font-color: black,         // 页脚颜色（书名）
  pager-y: 250pt,                  // 页脚基线 Y 坐标

  // ----- 批注样式 -----
  comment-column-gap-ratio: 0.5,
  comment-column-gap: 0pt,
  comment-extra-spacing: 0pt,

  // ----- 调试选项 -----
  test-mode: 0,

  // ----- 竖排标点开关 -----
  if-vertical-punct: 1,

  // ----- 标点位置微调 -----
  punct-shift-x: -0.3em,
  punct-shift-y: -0.2em,

  // ----- 背景图 -----
  background-image: none,
  background-opacity: 1.0,
  background-fit: "cover",

  // ----- 正文内容 -----
  texts: (),
  start-index: 1,
  end-index: 1
) = {
  // ========== 1. 布局计算 ==========
  let cw = (canvas.width - canvas.margins.left - canvas.margins.right - canvas.center-width) / canvas.columns
  let rh = (canvas.height - canvas.margins.top - canvas.margins.bottom) / rows
  let page-chars-num = canvas.columns * rows

  let pos-l = ()
  for col in range(1, canvas.columns + 1) {
    for row in range(rows, 0, step: -1) {
      let pos-x = if col <= canvas.columns / 2 {
        canvas.width - canvas.margins.right - cw * col
      } else {
        canvas.width - canvas.margins.right - cw * col - canvas.center-width
      }
      let pos-y = canvas.height - canvas.margins.top - rh * row + row-delta-y
      pos-l = pos-l + ((pos-x, pos-y),)
    }
  }

  // ========== 2. 字体定义 ==========
  let text-fonts = ("AaHLGGT",)
  let comment-fonts = ("AaHLGGT",)

  let get-font(char, font-list) = {
    if font-list.len() == 0 { return () }
    font-list.first()
  }

  // ========== 3. 标点映射表 ==========
  let vert-punct-map = (
    "，": "︐", "。": "︒", "、": "︑", "“": "﹁", "”": "﹂",
    "‘": "﹃", "’": "﹄", "《": "︽", "》": "︾", "（": "︵", "）": "︶",
    ",": "︐", ".": "︒", "?": "︖", "!": "︕", ":": "︓", ";": "︔"
  )

  let all-punct-chars = ()
  for (k, v) in vert-punct-map { all-punct-chars = all-punct-chars + (k, v) }
  let extra-punct = ("…", "—", "～", "　")
  all-punct-chars = all-punct-chars + extra-punct

  // ========== 4. 类型安全处理 ==========
  let input-texts = if type(texts) == "string" {
    (texts,)
  } else if type(texts) == "array" {
    texts
  } else {
    (str(texts),)
  }

  // ========== 5. 文本预处理（@替换为全角空格 + 竖排标点转换）==========
  let preprocess(str) = {
    let result = str.replace("@", "\u{3000}")
    if if-vertical-punct == 1 {
      for (k, v) in vert-punct-map { result = result.replace(k, v) }
    }
    result
  }

  let processed-texts = ()
  for t in input-texts { processed-texts = processed-texts + (preprocess(t),) }

  // ========== 6. 文本解析为令牌流 ==========
  let tokenize(str) = {
    let tokens = ()
    let i = 0
    let chars = str.split("")
    while i < chars.len() {
      let c = chars.at(i)
      if c == "【" {
        let comment = ()
        i += 1
        while i < chars.len() and chars.at(i) != "】" {
          comment = comment + (chars.at(i),)
          i += 1
        }
        i += 1
        tokens = tokens + (("comment", comment),)
      } else {
        tokens = tokens + (("char", c),)
        i += 1
      }
    }
    tokens
  }

  // ========== 7. 分页分配 ==========
  let assign-to-pages(tokens) = {
    let pages = ()
    let current-page = ()
    let pos = 0
    let remaining = tokens

    while remaining.len() > 0 {
      let token = remaining.at(0)
      if token.at(0) == "char" {
        if pos < page-chars-num {
          current-page = current-page + (("char", token.at(1), pos),)
          pos += 1
          remaining = remaining.slice(1,)
        } else {
          pages = pages + (current-page,)
          current-page = ()
          pos = 0
        }
      } else {
        let comment-chars = token.at(1)
        let needed = calc.floor((comment-chars.len() + 1) / 2)
        if pos + needed <= page-chars-num {
          current-page = current-page + (("comment", comment-chars, pos),)
          pos += needed
          remaining = remaining.slice(1,)
        } else {
          pages = pages + (current-page,)
          current-page = ()
          pos = 0
        }
      }
    }
    if current-page.len() > 0 { pages = pages + (current-page,) }
    pages
  }

  // ========== 8. 带偏移的字符绘制 ==========
  let draw-char-with-shift(char, font, size, color, x, y) = {
    let is-punct = all-punct-chars.contains(char)
    let final-x = if is-punct { x + punct-shift-x } else { x }
    let final-y = if is-punct { y + punct-shift-y } else { y }
    let content = if font-rotate != 0 {
      rotate(font-rotate * 1deg, text(font: font, size: size, fill: color)[#char])
    } else {
      text(font: font, size: size, fill: color)[#char]
    }
    place(dx: final-x, dy: final-y, content)
  }

  // ========== 9. 渲染单页 ==========
  let render-page(page-instr, page-num, title-str) = {
    let page-content = ()

    // 背景图
    if background-image != none {
      let bg = image(background-image, width: canvas.width, height: canvas.height, fit: background-fit)
      page-content = page-content + (place(dx: 0pt, dy: 0pt, bg),)
    }

    // -------------------- 天头：显示页码（反转，个位在上） --------------------
    let num-chars = str(page-num + 1).split("").rev()   // 反转字符顺序，个位在上
    for i in range(0, num-chars.len()) {
      let char = num-chars.at(i)
      let fn = get-font(char, text-fonts)
      let fsize = title-font-size
      let fx = if if-tpcenter == 0 { -fsize/2 } else { canvas.width/2 - fsize/2 }
      let fy = title-y - fsize * i * title-ydis
      let content = text(font: fn, size: fsize, fill: title-font-color)[#char]
      page-content = page-content + (place(dx: fx, dy: fy, content),)
    }

    // -------------------- 正文和批注 --------------------
    let comment-gap = if comment-column-gap == none {
      cw * comment-column-gap-ratio
    } else {
      comment-column-gap
    }

    for instr in page-instr {
      if instr.at(0) == "char" {
        let (_, char, cell-idx) = instr
        let (fx0, fy0) = pos-l.at(cell-idx)
        let fn = get-font(char, text-fonts)
        let fsize = text-font-size
        let fcolor = if test-mode > 0 and fn != text-fonts.first() { blue } else { text-font-color }
        let fx = fx0 + (cw - fsize) / 2
        let fy = fy0 + (rh - fsize) / 2
        page-content = page-content + (draw-char-with-shift(char, fn, fsize, fcolor, fx, fy),)
      } else {
        let (_, comment-chars, cell-idx) = instr
        let total = comment-chars.len()
        let right-count = calc.floor((total + 1) / 2)
        let left-count = total - right-count
        for i in range(0, right-count) {
          let (lx, ly) = pos-l.at(cell-idx + i)
          let y_offset = i * comment-extra-spacing
          if i < left-count {
            let char = comment-chars.at(right-count + i)
            let fn = get-font(char, comment-fonts)
            let fsize = comment-font-size
            let fx = lx + (cw - comment-gap)/2 - fsize/2
            let fy = ly + (rh - fsize) / 2 + y_offset
            page-content = page-content + (draw-char-with-shift(char, fn, fsize, comment-font-color, fx, fy),)
          }
          if i < right-count {
            let char = comment-chars.at(i)
            let fn = get-font(char, comment-fonts)
            let fsize = comment-font-size
            let fx = lx + (cw + comment-gap)/2 - fsize/2
            let fy = ly + (rh - fsize) / 2 + y_offset
            page-content = page-content + (draw-char-with-shift(char, fn, fsize, comment-font-color, fx, fy),)
          }
        }
      }
    }

    // -------------------- 页脚：显示书名（原序，第一个字符在上） --------------------
    let title-chars = title.split("")
    for i in range(0, title-chars.len()) {
      let char = title-chars.at(i)
      let fn = get-font(char, text-fonts)
      let fsize = pager-font-size
      let px = if if-tpcenter == 0 { -fsize/2 } else { canvas.width/2 - fsize/2 }
      let py = pager-y - fsize * i * title-ydis
      let content = text(font: fn, size: fsize, fill: pager-font-color)[#char]
      page-content = page-content + (place(dx: px, dy: py, content),)
    }

    page(width: canvas.width, height: canvas.height, margin: 0pt, [#for item in page-content { item }])
  }

  // ========== 10. 主流程 ==========
  let all-pages = ()
  for idx in range(start-index, end-index + 1) {
    if idx - 1 < processed-texts.len() {
      let tokens = tokenize(processed-texts.at(idx - 1))
      let pages = assign-to-pages(tokens)
      for p in pages { all-pages = all-pages + (p,) }
    }
  }

  let output = ()
  for i in range(0, all-pages.len()) {
    output = output + (render-page(all-pages.at(i), i, title),)   // title-str 不再使用，但保留参数
  }
  output.join()
}

