# 文笺 / Type Folio

[中文说明](#中文说明) · [English](#English)

## 中文说明

「文笺」为 EPUB 等 CRE 排版书提供下划线与排版微调：逐行/段落/强调词下划线、荧光笔高亮、引用块装饰、章节标题线条、对话高亮、首字下沉、纯黑增强等，并附自定义与内置预设。
与「阅笺 / Reading Folio」为同族插件。

### 自动混合渲染

默认的**自动选择**会按效果决定后端：逐行下划线与荧光笔直接绘制，不改变行高；段落底线与强调词下划线自动使用 CSS；章节标题、引用块、对话高亮、首字下沉、正文加粗/斜体和纯黑使用 CSS，章节开头与结尾标记则由章节感知直接绘制。用户无需再为整本书二选一，也不会因切换渲染策略而丢失正文标记设置。

特殊书籍可改用全局兼容策略：**CSS 兼容模式**强制下划线走样式表；**优先直接绘制**对支持的效果使用 Painter，对依赖 DOM 的效果仍安全回落 CSS。

| 比较项 | 样式表（CSS） | 直接绘制 |
| --- | --- | --- |
| 原理 | 生成 CSS 经官方 Style tweaks 装载 | 用 `registerViewModule` 把线画到帧缓冲 |
| 逐行下划线 / 荧光笔 | 支持 | 支持 |
| 段落底线 / 强调词下划线 | 支持 | 自动回落 CSS（需要 DOM 结构） |
| 结构类特效与预设 | 支持 | **同样支持**（走 CSS） |
| 影响行高 | 会（`border-bottom` 占位） | 不会 |
| 与原书 CSS 冲突 | 需靠 `!important` 抢 | 无 |
| 改粗细 / 笔触 | 触发整篇重排 | 立即重绘 |

直接绘制的下划线取 crengine 返回的物理文字框宽度（从行首第一个字到行末最后一个字），两端对齐段落内部的字间距空隙也会连贯画上；由于受文字框范围约束，行首缩进与段尾未填满的空白处同样不会多画线。默认会跳过标题与引用块不画（避免和标题边框重叠），可在同一子菜单里关掉。

### 推荐排版步骤：先检测文档健康度

在为新打开的书籍配置排版特效或遇到排版异常时，**强烈建议先检测文档健康度**：

- **检查位置**：菜单路径 **`排版工具` → `书籍排版体检`**（英文界面下为 **`Typesetting tools` → `Typesetting health check`**）。
- **检测内容**：自动抽样全书目录与当前页 HTML 结构，精准检测是否存在标准标题标签（`<h1>`~`<h6>`）、对话 Class 标记、引用块（`<blockquote>`）以及段首全角空格。
- **一键诊断**：输出 0-100 健康度评分、兼容性分析，并直接给出插件参数勾选建议或 Calibre 正则修改方案。

### 功能与参数全景表

每项特效在菜单中**点最左侧勾选框 = 开关，点其余区域 = 进子菜单调参数**（KOReader 的 `checkmark_callback` 机制）。子菜单首行均提供整行可点的**「功能名：已开启/已关闭」**开关。

| 功能分类 | 特效 / 参数名称 | 可调参数与选项 | 作用标签 / Class / 作用机制 | 渲染模式支持 |
| --- | --- | --- | --- | --- |
| **下划线与高亮** | **下划线类型** | 无 (默认)<br>逐行下划线 (`all_lines`)<br>段落底线 (`para`)<br>强调词下划线 (`em_only`)<br>荧光笔背景 (`marker`) | 取消下划线<br>`p span...` (自动排除标题/居中段)<br>`p { border-bottom: ... }`<br>`em, i, u { border-bottom: ... }`<br>`background-color: rgba(0,0,0,0.12)` | 双模式支持<br>双模式支持<br>仅 CSS 模式<br>仅 CSS 模式<br>双模式支持 |
| | **笔触样式** | 平滑实线 (`solid`: `──────`)<br>标准短虚线 (`normal`: `-- --`)<br>密集点线 (`dense`: `······`)<br>加粗实线 (`thick`: 自动提升至 2.5px) | 生成对应 CSS `border-bottom` 样式 / 绘制模式画对应点阵虚线 | 双模式支持 |
| | **线粗细控制** | 1.0px (发丝线)<br>1.5px (标准默认)<br>2.0px (加粗)<br>**自定义粗细…** (弹窗输入任意 px 数值) | 改变 `border-bottom` 像素宽度<br>绘制模式直接修改绘笔粗细 | 双模式支持 |
| **结构类排版** | **对话高亮** | 两条通路合于一项：<br>① 按 class 标记着色（底色浅/中/深、加粗、斜体）<br>② 动态匹配（无需修改 EPUB）：标记方式（底色/下划线/左侧竖线）、匹配引号语言（中英/中/英）、底色深浅 | ① `span.dialogue`, `.dialog`, `.speech` 等（需 Calibre 标注）<br>② 直接绘制：按引号定位对话，段首引号即判定，行内引用词（如拟声词、绰号）不着色。底色与下划线只覆盖引号内的文字，说话人部分留白；左侧竖线天生整行。加粗与斜体只有 ① 提供——画笔在页面渲染完成后叠加图形，改不了已成形的字 | ① 走 CSS 机制<br>② 直接绘制 |
| | **章节标题装饰** | 边框位置（上下/仅下/仅上/无）、线样式、粗细 1-5px、是否居中 | `h1`~`h3`, `.title`, `.chapter-title` | 走 CSS 机制 |
| | **章节分页** | 居中段落也视为章节标题（默认开） | `h1-h3`, `.chapter-title` 等；`page-break-before: always`（文件首标题除外）。开启居中回退后同时命中 `p[align="center"]`，用于 Calibre 转换后无 h 标签的书籍 | 走 CSS 机制 |
| | **引用块装饰** | 左竖线粗细 (0-8px)、背景底色 (无/浅/中)、是否斜体 | `blockquote`, `.quote`, `.citation` | 走 CSS 机制 |
| | **首字放大下沉** | 放大倍数 (1.5-3.5em)、是否加粗 | `h1+p::first-letter`, `p:first-of-type` | 走 CSS 机制 |
| | **正文加粗** | 无参数（直接勾选） | `p, li, blockquote` 等正文标签（不改标题） | 走 CSS 机制 |
| | **正文斜体** | 无参数（直接勾选） | `p, li, blockquote` 等正文标签（不改标题） | 走 CSS 机制 |
| | **强制文字纯黑** | 无参数（直接勾选） | `body, p, div, span, li, a` | 走 CSS 机制 |

边框位置选「无」时，只保留标题居中、不再占位留白，线样式与粗细一并灰置。特效未启用时其全部参数灰置。

### 预设

- **内置与自定义预设**：提供一键排版方案（如全虚线模式、研读模式、复古报纸等），同时支持将当前方案保存为独立快照，随时应用、重命名、删除或导出。
- **导入 / 导出**：预设以版本化 `.typefolio.json` 文件保存在 `DataStorage/typefolio_presets/`；导入时严格校验效果、参数与范围，并在确认前显示当前设置与导入设置的差异摘要。点文件名进子菜单，可导入或直接删除该文件（删除前确认），无需再去文件管理器。
- **方案比较**：将两套排版分别保存为命名预设，即可反复应用比较；选定后保留需要的预设，也可随时恢复其他方案。
- **一并携带 KOReader 底部菜单设置**：保存或导出预设时会连同当前书的 KOReader 排版设置一起记下（字体、字号、行间距、边距、视图与渲染模式、缩放 dpi、内嵌样式与字体、顶部状态栏、屏幕方向、单书样式表等），应用到别的书时按 creoptions 逐项重放对应事件，一次刷新到位。这份设置是**一次性载荷**：只作用于应用的那一刻，不会存进书里，因此之后在底部菜单做的改动不会被开书重放覆盖。导入预设文件时保留文件里原本那份载荷，只有「保存当前设置为新预设」才抓取当前正在读的这本书。

### 使用指南与 Calibre 正则表

主菜单首行提供**「使用指南」**子菜单，包含概览、Calibre 标记指南及手势预设说明。以下为 Calibre 编辑书籍时的常用正则查找替换表：

| 对应功能 | Calibre 查找内容 (正则) | 替换为 | 说明 |
| --- | --- | --- | --- |
| **逐行文字下划线 (CSS模式)** | `<p([^>]*)>(.*?)</p>` | `<p\1><span>\2</span></p>` | CSS 逐行下划线依赖 `p span` 选择器；若原书 `<p>` 内无内联标签，用此正则包裹 `<span>` 即可触发 CSS 模式画线 |
| **对话高亮** | `“([^””]*)”` | `<span class="dialogue">“\1”</span>` | 为引号对话加 `.dialogue` 标签，触发高亮 |
| **章节标题装饰** | `<p[^>]*>\s*(?:<[^>]+>\s*)*(第[0-9一二三四五六七八九十百千零0-9\s]+[章卷集回部][^<]*)\s*(?:</[^>]+>\s*)*</p>` | `<h2 class="chapter-title">\1</h2>` | 清洗多层 `<span><font><b>` 嵌套与换行，替换为标准 `<h2>` |
| **引用块装饰** | `<p[^>]*>【引用】([^\n<]*)</p>` | `<blockquote><p>\1</p></blockquote>` | 将标记段落转为标准 `<blockquote>` 引用块 |
| **清除首段全角空格** | `(<h[1-4][^>]*>[^<]*</h[1-4]>\s*<p[^>]*>)　+` | `\1` | 移除标题后首段开头的全角空格，避免放大空字符 |

### 手势快捷方式与安装

- **手势绑定**：设置 → 手势（或快捷方式）→ 选一个手势 → 阅读器 → 排版 → 文笺。绑完后可用手势直接弹出菜单。
- **安装方法**：将 `typefolio.koplugin` 复制到 KOReader 的 `plugins/` 目录并重启即可。

### 工作原理与 CSS 下划线规则

#### 样式表路径与下划线 CSS 生成机制
1. **样式表存储**：KOReader 只扫描 `DataStorage:getDataDir()/styletweaks/` 目录；本插件把规则动态生成并写入 `99_typefolio.css`。
2. **下划线 CSS 生成 (`CSSTemplates.getUnderlineCss`)**：
   - **逐行下划线 (`all_lines`)**：1.5px 实线模式下优先采用原生 `text-decoration: underline !important`；其他笔触与粗细采用 `border-bottom: <thickness> <style> #000000 !important`，并自动注入排除选择器（`h1 span`, `h2 span`, `p[align="center"] span`, `.title span` 等），确保章节标题与居中段落不受干预。
   - **段落底线 (`para`)**：注入 `p { border-bottom: ... !important; }`。
   - **强调词下划线 (`em_only`)**：针对 `em, i, u` 标签清除原本倾斜并加底线 `border-bottom: ... !important`。
   - **荧光笔高亮 (`marker`)**：注入 `background-color: rgba(0, 0, 0, 0.12) !important;` 灰阶底色。
3. **线粗细与笔触**：线粗细支持 `1.0px`~`2.0px` 及弹窗自定义任意 `px` 数值；笔触支持实线（`solid`）、短虚线（`dashed`）、密点（`dotted`）及加粗实线（`thick` 提升至 2.5px）。
4. **动态生效**：修改后调用 `updateCssText(true)` 并广播 `ApplyStyleSheet` 触发即时重排。

#### 直接绘制路径
1. 在 `onReaderReady` 里用 `view:registerViewModule` 注册（PDF/DjVu 自动跳过）。
2. 行框优先走 `getXPointer()` + `getPageXPointer(page)` → `getScreenBoxesFromPositions`（`cache_by_tag` 不打碎位图缓存）。
3. 行框在 `paintTo` 中惰性计算与绘制；跳过标题基于 XPointer 中的 `/h%d` 与 `/blockquote` 进行判定。

#### BookContext 与感知排版

- **BookContext** 是 CRE 行框、目录章节状态和页面语义信息的统一只读入口；同一帧结果按页缓存，并在翻页、重排或视图变化后失效。
- **章节**统一管理章节标题 CSS，以及基于 KOReader 目录识别的章节开头/结尾绘制。标题、开头、结尾各自独立；开头和结尾分别拥有开关、单线/双线/五点样式及 1–3 档粗细。
- 章节头尾标记默认关闭，仅使用 Painter 覆盖绘制，不修改 EPUB、不注入语义标签，也不触发行高变化；设置参与每本书配置和预设导入导出。

#### Folio Scenes：正文与屏保联动

- 每本书可选择关闭、自动跟随、静读、研读、编辑或章节聚焦。自动模式依次根据引用与对话等研读特效、编辑类结构特效、章节感知和普通正文归纳场景。
- Type Folio 只发布版本化的 `folio-scene` 快照；Reading Folio 1.5+ 消费该快照，并在本次预览/休眠渲染中临时选择对应风格与内容模式，不覆盖用户原有阅笺设置。
- 场景随每本书设置即时发布，并参与 Type Folio 预设的导入导出。

### 已知限制

- KOReader 的用户 Style tweaks 只扫描一份目录，本插件生成的落地文件是全局唯一的 `styletweaks/99_typefolio.css`。每本书的开关与参数仍记在各自的 `typefolio_config` 里；**打开书籍时会按该书配置重写该文件**，因此正常换书不会串样式。若在外部同时改这份 CSS，以最后一次写入为准。

### 设置键

| 键 | 位置 | 含义 |
| --- | --- | --- |
| `typefolio_render_policy` | G_reader_settings（全局） | `auto` / `css` / `paint`，默认 `auto`；自动迁移旧 `typefolio_render_mode` |
| `typefolio_config` | doc_settings（每本书） | Schema v8：正文标记、章节、正文样式、语义绘制及 `folio_scene` 配置 |
| `typefolio_folio_scene` | doc_settings（每本书） | 供 Reading Folio 消费的 Folio Scene v1 快照 |
| `style_tweaks` | doc_settings（官方键） | 本插件写入 `["99_typefolio.css"] = true/false` |
| `typefolio_language` | G_reader_settings（预留） | 语言覆盖（`en` / `zh_CN`），默认跟随系统 |

### 扩展开发规范

- **新特效**：`css_templates.lua` 的 `layout_tweaks` 加 `function(params) -> css` → `tweak_defaults` 给默认值 → `main.lua` 的 `_tweakItems()` 加选项与 `_tweakSubItems()` 参数分支 → 语言包加词条。
- **开关与参数控件**：子菜单首行统一调用 `_tweakEnableItem(key, 英文标题)`；参数控件只用 `_paramRadio`、`_paramSpin`、`_paramToggle`。
- **预设与 CSS 纪律**：预设只改变开关动静、不动用户调好的参数；颜色仅用黑色与 `rgba(0,0,0,α)` 灰阶，覆盖样式必加 `!important`。

## English

> **Full documentation (feature table, Calibre regex, settings keys, extension notes) is in the Chinese section above.** This English section is a concise companion.

Type Folio adds underline and typesetting tools for CRE books in KOReader (EPUB etc.), including visible-page health checks, selector suggestions, and non-destructive semantic drawing. Sibling plugin of Reading Folio.

### Recommended workflow: Check document health first

When setting up a new book or troubleshooting layout issues, **check your document health first**:
- **Where to check**: Menu path **`Typesetting tools` → `Typesetting health check`** (Chinese: **`排版工具` → `书籍排版体检`**).
- **What it checks**: Samples TOC chapters and the current page to inspect heading tags (`<h1>`-`<h6>`), dialogue classes, blockquotes, and leading full-width spaces.
- **Diagnosis**: Scores document health from 0-100 and offers targeted action recommendations (plugin toggles or Calibre regex to fix EPUB markup).

### Automatic hybrid rendering

| | Stylesheet (CSS) | Direct drawing |
| --- | --- | --- |
| Mechanism | Writes `styletweaks/99_typefolio.css` via Style tweaks | Paints via `registerViewModule` |
| Per-line underline / highlighter | Yes | Yes |
| Paragraph bottoms / emphasis underlines | Yes | Falls back to CSS (DOM required) |
| Structural tweaks | Yes (CSS) | Yes (still CSS) |
| Line height impact | May shift (`border-bottom`) | None |

Automatic mode paints per-line underlines and highlighters while routing paragraph/emphasis underlines through CSS. Compatibility policies can force CSS or prefer painting without discarding settings. Painted lines can **Skip headings and blockquotes** (default on).

### Menu map

1. **Help / user guide** — overview, Calibre regex, gestures & presets
2. **Chapters** — chapter title, page break, start, and end controls
3. **Text styling** — text marks (underline/highlighter types, stroke, thickness, rendering), body bold/italic, dialogue, blockquote, drop caps, and pure black text
4. **Typesetting tools** — health check, selector helper, and semantic drawing
5. **Folio Scenes** — per-book sleep-screen linkage with Reading Folio 1.5+
6. **Presets** — built-ins, named layout comparisons, versioned JSON import/export (tap a `.typefolio.json` file to import or delete it)

A saved or exported preset also carries the book's KOReader typesetting settings (font, size, line spacing, margins, view/render mode, zoom dpi, embedded styles and fonts, alt status bar, rotation, per-book stylesheet). Applying it to another book replays each option's own creoptions event, batched into a single refresh. This payload is **one-shot**: it is applied but never stored on the book, so later changes made in the bottom menu are not overwritten the next time the book is opened. Importing a preset file keeps the payload the file was exported with; only "Save current as new preset" captures the book you are reading now.

Built-in presets only flip effect switches (parameters you already tuned are kept):

- **All-line dashes** — per-line dashes + pure black
- **Study notes** — emphasis underline + quote boxes + pure black
- **Vintage newspaper** — drop caps + heading borders

### Settings keys

| Key | Where | Meaning |
| --- | --- | --- |
| `typefolio_render_policy` | global | `auto` / `css` / `paint` (default `auto`; migrates the old mode key) |
| `typefolio_config` | per book | Schema v8 text marks, chapters, text styling, semantic drawing, and Folio Scene mode |
| `typefolio_folio_scene` | per book | Versioned scene snapshot consumed by Reading Folio 1.5+ |
| `style_tweaks["99_typefolio.css"]` | per book | enable generated stylesheet |
| `typefolio_custom_presets` | global | named config snapshots |
| `typefolio_language` | global (optional) | `en` / `zh_CN` override |

### Known limitation

The generated `styletweaks/99_typefolio.css` is a **single shared file**. Per-book settings live in `typefolio_config`; **on each book open the file is rewritten from the current book**, so styles do not leak across books during normal use.

## 更新记录 / Changelog

### 2026-08-11 (v3.0.4)

- **修复导入的预设只有文笺内部样式生效**：从 `.typefolio.json` 导入后去「自定义预设」应用，字体、字号、行间距、边距等 KOReader 设置全都是当前这本书的，只有下划线、特效等文笺自己的样式对。原因在保存环节而不是应用环节：导入确认后调用的 `saveCustomPreset` 会无条件用 `captureKOReaderDocSettings(ui)` 覆写 `koreader_settings`，于是文件里那份载荷在存进自定义预设的瞬间就被当前书的设置换掉了，应用时重放的自然是当前书。现改为仅当配置未自带载荷时才抓取当前书，与 `writePresetFile` 早有的判断一致：「保存当前设置为新预设」照常抓当前书，导入则原样保留文件里的那份。
- **不影响已导出的文件**：预设文件格式未变，此前导出的 `.typefolio.json` 载荷一直是完整的，重新导入一次即可恢复正常。
- **补齐排版体检的语言包**：体检报告里的功能名、状态徽章、诊断说明和两条建议是从 `health_check.lua` 的表里取出后经 `tr()` 翻译的，这些字符串此前没进 `en.lua`，英文界面下靠 `gettext` 兜底、实际显示的是原始字面量；其中 25 条连 `zh_CN.lua` 也没有，中文界面同样漏出英文。现补齐 64 条英文词条与 25 条中文翻译，两个语言包各 295 条、完全对齐。
- **清理失效词条**：删掉 11 条代码里已无任何引用的旧体检文案（`Health score: %1/100`、`【✔】 Ready for Drop Caps`、四条早期合并式正则说明等）。

### 2026-08-10 (v3.0.3)

- **导出的预设文件可在插件内删除**：此前「导入 / 导出预设」里每个 `.typefolio.json` 只有「导入」一个动作，想删掉只能去文件管理器。现在每个文件是一个子菜单，含「导入此文件」与「删除此文件」，删除前弹确认框并显示文件名。删除只接受 `listPresetFiles` 列出的纯文件名（不含路径分隔符、且以 `.typefolio.json` 结尾），越界或非预设文件一律拒绝。注意这删的是磁盘上的导出文件；已导入成为自定义预设的那一份仍在「自定义预设」里各自删除。
- **修复预设携带的 KOReader 菜单设置在另一本书上不生效**：屏幕方向、双栏、边距、视图模式、渲染模式、缩放 dpi、行间距、字号、文字间距、文字扩展、对比度、字重、字体微调、字距微调、顶部状态栏、内嵌样式、内嵌字体、图片缩放共 18 项此前只发了 `ConfigChange`。该事件在 KOReader 里只把值写进 `document.configurable`（见 `readercoptlistener.lua` 的 `onConfigChange`），并不调用 crengine，于是菜单里数值已变、版面纹丝不动，要重开书才由 `onReadSettings` 补上。现按 `ui/data/creoptions.lua` 取出每项自己的 `event` 并与 `ConfigChange` 一同发送，与官方 ConfigDialog、Dispatcher 的做法一致；字体此前能生效，正是因为它单独发了 `SetFont`。
- **值 → 参数映射**：creoptions 存的是 `values`、事件收的是 `args`，二者在若干项上并不相同（视图模式 `0/1` → `"page"`/`"scroll"`；内嵌样式、内嵌字体、图片缩放、反色图片 `0/1` → `false`/`true`）。现按下标换算后再发，不在候选表内的自定义值（自定义字号、自定义边距）原样透传。字体微调是相对量 `ChangeSize ±0.5`，重放会让字号逐次漂移，已排除。
- **上下边距合并发送**：分别发 `SetPageTopMargin` 与 `SetPageBottomMargin` 时，「同步上下边距」逻辑会用先到的那个覆盖后到的那个。改为一次 `SetPageTopAndBottomMargin`，同步开关随后单独恢复。
- **一次刷新而非二十次**：整段重放包在 `BatchedUpdate` / `BatchedUpdateDone` 之间并临时静音逐项提示，约二十次重排合并成一次 `UpdatePos`，墨水屏只闪一次。
- **移除两个无效调用**：不带参数的 `ReadSettings`（处理函数首行即调用 `config:readSetting`，必然抛错后被 pcall 吞掉）与 `ReInit`（当前 KOReader 无任何处理函数）。
- **样式表按书籍格式携带**：`copt_css` / `copt_fb2_css` 是全局默认值，写进单书 `doc_settings` 不会生效。现记录单书 `css` 键并标记来源是否 FB2，仅在格式相符时经 `ReaderTypeset:setStyleSheet` 应用，避免把 `fb2.css` 推到 EPUB 上。
- **预设不再残留在书上**：预设携带的 KOReader 设置是一次性载荷，此前会随 `typefolio_config` 存进单书设置，导致每次开书都重放一遍、覆盖读者事后在底部菜单里的改动。现在应用后即从待持久化的配置中剔除，开书时也不再重放；旧版本残留的载荷会在下次保存时自动清除。预设文件格式未变，已导出的 `.typefolio.json` 仍然兼容。

### 2026-08-09 (v3.0.2)

- **动态对话改为只标记引号内的文字**：原先命中一段对话就整行涂满，「对话 + 说话人」句式里说话人也被一起标上。现在按引号切出字节区间，换算成字符偏移后直接改写 xpointer 末尾的 `.N`（该格式见 KOReader `readerlink.lua`），交给 `getScreenBoxesFromPositions` 取回屏幕框——每条引文一次引擎调用，不必逐字走 `getNextVisibleChar`。文档取不到子行几何时自动退回整行框，不会漏画。左侧竖线天生是整行的，保持原样，菜单文案随之改为「背景底色（仅引号内）」「下划线（仅引号内）」「左侧竖线（整行）」。
- **修正跨行段落重复着色**：`snapshot.nodes` 是按行给的，而引号区间描述的是整段，逐行解析会把同一批像素 `darkenRect` 两三次（该操作会叠加，肉眼可见地变黑）。改为按元素路径去重，一段只解析一次。
- **说明加粗与斜体的边界**：画笔在页面渲染完成后往画面上叠图形，blitbuffer 只有矩形与像素操作、没有任何字形接口，无法把已成形的字换成另一套字重或字形；CSS 也没有按内容匹配的选择器。因此这两项仍只在「按 class 标记着色」通路提供，使用指南与 README 均已写明原因。
- **「正文标记」并入「正文样式」**：下划线类型、笔触、粗细与渲染方式本身就是样式选择，现作为「正文样式」的首行子菜单，顶层菜单由 7 项减为 6 项。设置键与外部调用接口未变。

### 2026-08-09 (v3.0.1)

- **修复章节分页对无 `h` 标签书籍不生效**：Calibre 转换的书籍常把章节标题写成 `<p align="center"><font><b>标题</b></font></p>`，既无 `h1`~`h3` 也无 class，原规则全部落空。新增「居中段落也视为章节标题」参数（默认开启），命中 `p[align="center"]`；同时抑制每个 DocFragment 的首个标题（epub.css 已在此处分页，重复会产生空白页），并让连续居中行（主标题 + 副标题）只分一次页。
- **修复动态对话识别完全不生效**：画笔遍历的是 `snapshot.semantics`，而 `semantic_index:inspect()` 实际返回的字段是 `nodes`，循环恒为空，一个矩形都画不出来。着重号画笔存在同一处错误，一并修正。
- **修复引号匹配在中文下静默失效**：模式 `[^”]+` 按字节取反，而 `”` 是 `E2 80 9D`、常见汉字（如 `一` = `E4 B8 80`）含有相同的续字节，匹配会在字符中途截断。改用惰性 `.-`，可安全跨越 UTF-8 序列。
- **修正对话判定阈值**：原先要求引号内容占全段 50% 以上，导致「对话 + 说话人」这一中文小说最常见的句式（`“在那里！”马脸男子忙朝前方一指。`）被漏判。改为段首出现引号即判定为对话，行内引用仍走占比阈值。在测试书籍 8608 段真实文本上，段首引号段召回率由 63.7% 升至 100%，且 6375 段无引号文本零误判。
- **合并对话菜单**：原「排版工具 → 动态对话识别」与「正文 → 对话」是两个各自独立的开关，且前者只响应勾选框、不响应整行点击。现统一到「正文 → 对话」一项：父行开关同时控制 CSS 与画笔两条通路，底色深浅为两者共用。「着重号画笔」也改为整行可点，与其他项一致。

### 2026-08-07 (v3.0.0)

- **书籍排版体检**：对当前可见页及全书目录做快速检查，输出健康度、警告、提示与语义覆盖率。
- **选择器助手**：检查页面上部、中央或下部，优先使用 CRE HTML 中的真实 ID/class，并以明确置信度安全降级到标签选择器。
- **无损语义绘制**：按屏幕坐标标记标题、引用、场景分隔与诊断问题；默认关闭，不修改 EPUB，也不触发重排。
- **共享语义索引**：三项能力复用同一份 BookContext 缓存，并在翻页、重排或视图变化后一起失效。
- **菜单与章节整合**：删除低命中率的旧章尾分隔线；章节标题、章节开头和章节结尾归入统一入口，头尾拥有独立开关、样式与粗细；正文标记、正文样式、排版工具和预设分别归类。
- **统一预设比较**：删除临时双快照实验及其独立菜单，改用命名预设保存、切换和恢复排版方案；升级时仍会安全清理未结束实验留下的旧备份。
- **移除标注页边提示**：删除低信息增量的标注感知菜单、配置、绘制与体检项；Schema v8 会安全丢弃旧配置和旧预设中的相关字段，不影响 KOReader 原有高亮与笔记。

### 2026-08-07 (v2.4.0)

- **Folio Scenes**：新增关闭、自动、静读、研读、编辑、章节聚焦六种每书场景，使正文排版语义可联动 Reading Folio 预览与休眠屏保。
- **窄接口联动**：Type Folio 发布独立的版本化场景快照，Reading Folio 只消费场景，不读取完整正文配置，也不修改用户原有阅笺全局设置。
- **场景与预设闭环**：正式场景参与 Schema v5、每书保存、预设快照和严格导入校验。

### 2026-08-07 (v2.3.0)

- **BookContext**：集中封装 CRE 可见行框、TOC 章节信息与页面语义，提供按页快照缓存和统一失效边界；下划线 Painter 不再直接读取文档引擎。
- **章节感知排版**：识别目录章首/章尾并以单线、双线或五点式轻量绘制，可独立控制两端和 1–3 档粗细，不修改 EPUB、不触发重排。
- **配置联动**：升级到 Schema v4；新增设置默认关闭，并完整接入每本书持久化、预设快照与严格导入校验。

### 2026-08-07 (v2.2.0)

- **自动混合渲染器**：按效果自动选择 Painter 或 CSS；逐行线/荧光笔不改行高，段落/强调词自动走 CSS，切换兼容策略不再清空设置。
- **预设方案比较**：可将不同排版保存为命名快照，通过反复应用预设进行比较和恢复。
- **预设导入导出**：新增版本化 `.typefolio.json`、严格白名单校验、重名处理和导入前差异确认。
- **架构底座**：新增配置 Schema v3、深拷贝迁移、纯渲染规划和统一 Engine；修复自定义预设嵌套参数共享引用的问题。

### 2026-08-05 (v2.1.2)

- **目录/章节跳转时绘制不崩**：直接绘制模式下对 crengine 行框/双页 xpointer 查询加 `pcall` 护栏，并校验指针有序性；跳转瞬间若原生侧暂时给不出稳定行框，跳过这一帧，不再把异常抛进 `ReaderView.paintTo` 主循环。
- 补充与重构 **README 说明**：在功能与参数全景表中补充完整的下划线类型（逐行/段落/强调词/荧光笔）、笔触样式（实线/短虚线/密点/加粗）与自定义粗细（弹窗 px 输入）说明，详细阐述 `99_typefolio.css` 规则生成与标题排除机制；英文节扩写并标明完整说明见中文。
- **开书按书重写 CSS**：`onReaderReady` 用当前书 `typefolio_config` 同步 `99_typefolio.css`，避免多书串样式；README 补充单文件限制说明。
- 删除未实现的**全局默认配置**文档条目，避免与代码不一致。
- 优化**菜单交互体验** (Keep Menu Open)：所有子菜单弹窗、帮助指南及预设操作完成后保持菜单打开状态，避免频繁重复点击进入。
- 增强**Calibre 正则兼容性** (Calibre Regex Enhancement)：优化使用指南中的标题查找正则，完美兼容多层 `<font>/<span>/<b>` 标签嵌套、换行及各种章节关键字。
- 扩充**使用指南**：补充直接绘制能力边界、跳过标题、纯黑、对话与三套内置预设说明；清理死词条并补全 `Save` 等翻译。
- 切换到直接绘制时，若仍选中段落底线/强调词下划线则**自动重置为无**；自定义粗细增加正数校验（上限 20px）。

### 2026-08-04

- 新增**对话高亮** (Dialogue Highlight)：支持独立配置底色背景（浅/中/深 3 档浓度）、加粗与斜体，适配 `.dialogue` 等常见 class，附带 Calibre 正则标注教程。
- 新增**自定义预设** (Custom Presets)：支持将当前排版配置保存为自定义预设，可随时应用、重命名或删除。
- 新增**使用指南** (In-Reader User Guide)：主菜单顶部新增帮助入口，直接弹窗介绍下划线渲染原理、对话高亮用法与手势绑定。
- 优化**子菜单状态指示** (Submenu Status Labels)：各特效子菜单首行统一显示「功能名：已开启/已关闭」，在墨水屏上状态更清晰。

### 2026-08-01

- 新增**手势快捷方式**：注册 `typefolio_show` 动作（事件 `ShowTypeFolioMenu`），绑定后一步弹出文笺菜单。
- 优化**子菜单整行开关**：四组可配置特效的子菜单首行加整行开关，避免墨水屏勾选框点击困难。
- 优化**章节标题装饰**：边框位置新增「无」选项（只居中、不画线，且不再占位留白）。
- 收窄**互斥范围**与升级**可调参数架构**：结构类特效均可调参数且双模式可用；新增直接绘制渲染后端。

### 2026-07-27

- 菜单通过 `registerToMainMenu` 注册进排版分区，支持真正的菜单分隔线与单选圆点。
- 全部文案接入双语语言包体系（`locales/en.lua`、`zh_CN.lua`）。
