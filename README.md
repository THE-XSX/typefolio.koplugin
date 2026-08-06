# 文笺 / Type Folio

[中文说明](#中文说明) · [English](#English)

## 中文说明

「文笺」为 EPUB 等 CRE 排版书提供下划线与排版微调：逐行/段落/强调词下划线、荧光笔高亮、引用块装饰、章节标题线条、对话高亮、首字下沉、纯黑增强等，并附自定义与内置预设。
与「阅笺 / Reading Folio」为同族插件。

### 两种下划线渲染方式（二选一）

菜单顶部的**下划线渲染方式**只管下划线与荧光笔这一层，设置为全局（所有书统一）。
**结构类特效（标题装饰、章尾线、引用块、对话高亮、首字下沉、纯黑）两种方式下都可用**——它们作用于 `h1`、`hr`、`blockquote`、`.dialogue`、`::first-letter`，与画上去的下划线互不重叠。

| 比较项 | 样式表（CSS） | 直接绘制 |
| --- | --- | --- |
| 原理 | 生成 CSS 经官方 Style tweaks 装载 | 用 `registerViewModule` 把线画到帧缓冲 |
| 逐行下划线 / 荧光笔 | 支持 | 支持 |
| 段落底线 / 强调词下划线 | 支持 | 灰置（需要 DOM 结构，绘制路径拿不到） |
| 结构类特效与预设 | 支持 | **同样支持**（走 CSS） |
| 影响行高 | 会（`border-bottom` 占位） | 不会 |
| 与原书 CSS 冲突 | 需靠 `!important` 抢 | 无 |
| 改粗细 / 笔触 | 触发整篇重排 | 立即重绘 |

绘制模式下的下划线取 crengine 返回的物理文字框宽度（从行首第一个字到行末最后一个字），两端对齐段落内部的字间距空隙也会连贯画上；由于受文字框范围约束，行首缩进与段尾未填满的空白处同样不会多画线。默认会跳过标题与引用块不画（避免和标题边框重叠），可在同一子菜单里关掉。

### 功能与参数全景表

每项特效在菜单中**点最左侧勾选框 = 开关，点其余区域 = 进子菜单调参数**（KOReader 的 `checkmark_callback` 机制）。子菜单首行均提供整行可点的**「功能名：已开启/已关闭」**开关。

| 功能分类 | 特效 / 参数名称 | 可调参数与选项 | 作用标签 / Class / 作用机制 | 渲染模式支持 |
| --- | --- | --- | --- | --- |
| **下划线与高亮** | **下划线类型** | 无 (默认)<br>逐行下划线 (`all_lines`)<br>段落底线 (`para`)<br>强调词下划线 (`em_only`)<br>荧光笔背景 (`marker`) | 取消下划线<br>`p span...` (自动排除标题/居中段)<br>`p { border-bottom: ... }`<br>`em, i, u { border-bottom: ... }`<br>`background-color: rgba(0,0,0,0.12)` | 双模式支持<br>双模式支持<br>仅 CSS 模式<br>仅 CSS 模式<br>双模式支持 |
| | **笔触样式** | 平滑实线 (`solid`: `──────`)<br>标准短虚线 (`normal`: `-- --`)<br>密集点线 (`dense`: `······`)<br>加粗实线 (`thick`: 自动提升至 2.5px) | 生成对应 CSS `border-bottom` 样式 / 绘制模式画对应点阵虚线 | 双模式支持 |
| | **线粗细控制** | 1.0px (发丝线)<br>1.5px (标准默认)<br>2.0px (加粗)<br>**自定义粗细…** (弹窗输入任意 px 数值) | 改变 `border-bottom` 像素宽度<br>绘制模式直接修改绘笔粗细 | 双模式支持 |
| **结构类排版** | **对话高亮** | 底色背景（浅/中/深 3 档）、加粗、斜体 | `span.dialogue`, `.dialog`, `.speech` 等 (需 Calibre 标注) | 走 CSS 机制 |
| | **章节标题装饰** | 边框位置（上下/仅下/仅上/无）、线样式、粗细 1-5px、是否居中 | `h1`~`h3`, `.title`, `.chapter-title` | 走 CSS 机制 |
| | **章尾分隔线** | 线样式（实/虚/点）、粗细 1-5px、宽度占比 (50%-100%) | `<hr>`, `.break`, `.separator` 等 | 走 CSS 机制 |
| | **引用块装饰** | 左竖线粗细 (0-8px)、背景底色 (无/浅/中)、是否斜体 | `blockquote`, `.quote`, `.citation` | 走 CSS 机制 |
| | **首字放大下沉** | 放大倍数 (1.5-3.5em)、是否加粗 | `h1+p::first-letter`, `p:first-of-type` | 走 CSS 机制 |
| | **强制文字纯黑** | 无参数（直接勾选） | `body, p, div, span, li, a` | 走 CSS 机制 |

边框位置选「无」时，只保留标题居中、不再占位留白，线样式与粗细一并灰置。特效未启用时其全部参数灰置。

### 预设

- **内置与自定义预设**：提供一键排版方案（如全虚线模式、研读模式、复古报纸等），同时支持将当前的排版与下划线方案在「自定义预设」中**保存为独立快照**，随时应用、重命名或删除。

### 使用指南与 Calibre 正则表

主菜单首行提供**「使用指南」**子菜单，包含概览、Calibre 标记指南及手势预设说明。以下为 Calibre 编辑书籍时的常用正则查找替换表：

| 对应功能 | Calibre 查找内容 (正则) | 替换为 | 说明 |
| --- | --- | --- | --- |
| **逐行文字下划线 (CSS模式)** | `<p([^>]*)>(.*?)</p>` | `<p\1><span>\2</span></p>` | CSS 逐行下划线依赖 `p span` 选择器；若原书 `<p>` 内无内联标签，用此正则包裹 `<span>` 即可触发 CSS 模式画线 |
| **对话高亮** | `“([^””]*)”` | `<span class="dialogue">“\1”</span>` | 为引号对话加 `.dialogue` 标签，触发高亮 |
| **章节标题装饰** | `<p[^>]*>\s*(?:<[^>]+>\s*)*(第[0-9一二三四五六七八九十百千零0-9\s]+[章卷集回部][^<]*)\s*(?:</[^>]+>\s*)*</p>` | `<h2 class="chapter-title">\1</h2>` | 清洗多层 `<span><font><b>` 嵌套与换行，替换为标准 `<h2>` |
| **章尾 / 场景分隔线** | `<p[^>]*>\s*(?:[*＊#＃◆◇▲\-—]{3,})\s*</p>` | `<hr class="break" />` | 将 `***` 或 `◆◆◆` 等符号行转为标准 `<hr>` 线 |
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

### 已知限制

- KOReader 的用户 Style tweaks 只扫描一份目录，本插件生成的落地文件是全局唯一的 `styletweaks/99_typefolio.css`。每本书的开关与参数仍记在各自的 `typefolio_config` 里；**打开书籍时会按该书配置重写该文件**，因此正常换书不会串样式。若在外部同时改这份 CSS，以最后一次写入为准。

### 设置键

| 键 | 位置 | 含义 |
| --- | --- | --- |
| `typefolio_render_mode` | G_reader_settings（全局） | `css` / `paint`，默认 `css` |
| `typefolio_config` | doc_settings（每本书） | `{ underline, line_thickness, dash_pattern, tweaks, tweak_params, skip_headings }` |
| `style_tweaks` | doc_settings（官方键） | 本插件写入 `["99_typefolio.css"] = true/false` |
| `typefolio_language` | G_reader_settings（预留） | 语言覆盖（`en` / `zh_CN`），默认跟随系统 |

### 扩展开发规范

- **新特效**：`css_templates.lua` 的 `layout_tweaks` 加 `function(params) -> css` → `tweak_defaults` 给默认值 → `main.lua` 的 `_tweakItems()` 加选项与 `_tweakSubItems()` 参数分支 → 语言包加词条。
- **开关与参数控件**：子菜单首行统一调用 `_tweakEnableItem(key, 英文标题)`；参数控件只用 `_paramRadio`、`_paramSpin`、`_paramToggle`。
- **预设与 CSS 纪律**：预设只改变开关动静、不动用户调好的参数；颜色仅用黑色与 `rgba(0,0,0,α)` 灰阶，覆盖样式必加 `!important`。

## English

> **Full documentation (feature table, Calibre regex, settings keys, extension notes) is in the Chinese section above.** This English section is a concise companion.

Type Folio adds underline and typesetting tweaks for CRE books in KOReader (EPUB etc.): per-line / paragraph / emphasis underlines, highlighter backgrounds, blockquote decoration, chapter heading rules, chapter-break rules, drop caps, dialogue highlight, and pure-black text. Sibling plugin of Reading Folio.

### Rendering modes (global)

| | Stylesheet (CSS) | Direct drawing |
| --- | --- | --- |
| Mechanism | Writes `styletweaks/99_typefolio.css` via Style tweaks | Paints via `registerViewModule` |
| Per-line underline / highlighter | Yes | Yes |
| Paragraph bottoms / emphasis underlines | Yes | No (menu greys out; auto-reset to None if selected) |
| Structural tweaks | Yes (CSS) | Yes (still CSS) |
| Line height impact | May shift (`border-bottom`) | None |

Paint mode can **Skip headings and blockquotes** (default on). Stroke style and thickness apply in both modes; custom thickness accepts a positive px value (max 20).

### Menu map

1. **Help / user guide** — overview, Calibre regex, gestures & presets  
2. **Underline rendering** — CSS vs direct drawing  
3. **Underline type / stroke / thickness**  
4. **Structural tweaks** — dialogue, chapter rules, blockquote, heading decoration, drop caps, pure black (left checkmark toggles; body opens params)  
5. **Presets** — three built-ins, restore defaults, custom snapshots (save/rename/delete/apply)

Built-in presets only flip effect switches (parameters you already tuned are kept):

- **All-line dashes** — per-line dashes + pure black  
- **Study notes** — emphasis underline + quote boxes + pure black (underlines need CSS mode)  
- **Vintage newspaper** — drop caps + heading borders + chapter rules  

### Settings keys

| Key | Where | Meaning |
| --- | --- | --- |
| `typefolio_render_mode` | global | `css` / `paint` (default `css`) |
| `typefolio_config` | per book | underline, thickness, dash, tweaks, params, skip_headings |
| `style_tweaks["99_typefolio.css"]` | per book | enable generated stylesheet |
| `typefolio_custom_presets` | global | named config snapshots |
| `typefolio_language` | global (optional) | `en` / `zh_CN` override |

### Known limitation

The generated `styletweaks/99_typefolio.css` is a **single shared file**. Per-book settings live in `typefolio_config`; **on each book open the file is rewritten from the current book**, so styles do not leak across books during normal use.

## 更新记录 / Changelog

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
