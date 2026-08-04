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

绘制模式下的下划线取 crengine 返回的整行文字框宽度，两端对齐的段落里行末空隙也会画上——**横格纸效果**，这是刻意为之。默认会跳过标题与引用块不画（避免和标题边框重叠），可在同一子菜单里关掉。

### 功能与参数全景表

每项特效在菜单中**点最左侧勾选框 = 开关，点其余区域 = 进子菜单调参数**（KOReader 的 `checkmark_callback` 机制）。子菜单首行均提供整行可点的**「功能名：已开启/已关闭」**开关。

| 特效名称 | 可调参数 | 依赖标签 / Class | 渲染模式支持 |
| --- | --- | --- | --- |
| **对话高亮** | 底色背景（浅/中/深 3 档）、加粗、斜体 | `span.dialogue`, `.dialog`, `.speech` 等 (需 Calibre 标注) | CSS 模式 |
| **章节标题装饰** | 边框位置（上下/仅下/仅上/无）、线样式、粗细 1-5px、是否居中 | `h1`~`h3`, `.title`, `.chapter-title` | CSS 模式 |
| **章尾分隔线** | 线样式（实/虚/点）、粗细 1-5px、宽度占比 (50%-100%) | `<hr>`, `.break`, `.separator` 等 | CSS 模式 |
| **引用块装饰** | 左竖线粗细 (0-8px)、背景底色 (浅/中)、是否斜体 | `blockquote`, `.quote`, `.citation` | CSS 模式 |
| **首字放大下沉** | 放大倍数 (1.5-3.5em)、是否加粗 | `h1+p::first-letter`, `p:first-of-type` | CSS 模式 |
| **强制文字纯黑** | 无参数（直接勾选） | `body, p, div, span, li, a` | CSS 模式 |
| **逐行下划线 / 荧光笔** | 线样式、粗细、笔触 | `p span...` 或 XPointer 文字框 | CSS 与直接绘制均支持 |
| **段落底线 / 强调词下划线** | 线样式、粗细 | `<p>` 或 `<em>`/`<i>`/`<u>` | 仅 CSS 模式可用（绘制模式灰置） |

边框位置选「无」时，只保留标题居中、不再占位留白，线样式与粗细一并灰置。特效未启用时其全部参数灰置。

### 预设与全局默认配置

- **内置与自定义预设**：提供一键排版方案，同时支持将当前的排版与下划线方案在「自定义预设」中**保存为独立快照**，随时应用、重命名或删除。
- **全局默认设置**：在预设子菜单中可点击「将当前设置存为新书默认值」，新开未配置过的书将自动继承此基线；也可随时「清除全局默认设置」。

### 使用指南与 Calibre 正则表

主菜单首行提供**「使用指南」**子菜单，包含概览、Calibre 标记指南及手势预设说明。以下为 Calibre 编辑书籍时的常用正则查找替换表：

| 对应功能 | Calibre 查找内容 (正则) | 替换为 | 说明 |
| --- | --- | --- | --- |
| **对话高亮** | `“([^””]*)”` | `<span class="dialogue">“\1”</span>` | 为引号对话加 `.dialogue` 标签，触发高亮 |
| **章节标题装饰** | `<p[^>]*>\s*(?:<[^>]+>\s*)*(第[0-9一二三四五六七八九十百千零0-9\s]+[章卷集回部][^<]*)\s*(?:</[^>]+>\s*)*</p>` | `<h2 class="chapter-title">\1</h2>` | 清洗多层 `<span><font><b>` 嵌套与换行，替换为标准 `<h2>` |
| **章尾 / 场景分隔线** | `<p[^>]*>\s*(?:[*＊#＃◆◇▲\-—]{3,})\s*</p>` | `<hr class="break" />` | 将 `***` 或 `◆◆◆` 等符号行转为标准 `<hr>` 线 |
| **引用块装饰** | `<p[^>]*>【引用】([^\n<]*)</p>` | `<blockquote><p>\1</p></blockquote>` | 将标记段落转为标准 `<blockquote>` 引用块 |
| **清除首段全角空格** | `(<h[1-4][^>]*>[^<]*</h[1-4]>\s*<p[^>]*>)　+` | `\1` | 移除标题后首段开头的全角空格，避免放大空字符 |

### 手势快捷方式与安装

- **手势绑定**：设置 → 手势（或快捷方式）→ 选一个手势 → 阅读器 → 排版 → 文笺。绑完后可用手势直接弹出菜单。
- **安装方法**：将 `typefolio.koplugin` 复制到 KOReader 的 `plugins/` 目录并重启即可。

### 工作原理（改动前必读）

#### 样式表路径
1. KOReader 只扫描 `DataStorage:getDataDir()/styletweaks/` 目录；本插件把规则写入 `99_typefolio.css`。
2. 每本书的启用清单存于 doc_settings 键 `style_tweaks`（停用写 `false` 而非 `nil`）。
3. 动态更新调用 `updateCssText(true)` 并广播 `ApplyStyleSheet` 即时生效。

#### 直接绘制路径
1. 在 `onReaderReady` 里用 `view:registerViewModule` 注册（PDF/DjVu 自动跳过）。
2. 行框优先走 `getXPointer()` + `getPageXPointer(page)` → `getScreenBoxesFromPositions`（`cache_by_tag` 不打碎位图缓存）。
3. 行框在 `paintTo` 中惰性计算与绘制；跳过标题基于 XPointer 中的 `/h%d` 与 `/blockquote` 进行判定。

### 设置键

| 键 | 位置 | 含义 |
| --- | --- | --- |
| `typefolio_render_mode` | G_reader_settings（全局） | `css` / `paint`，默认 `css` |
| `typefolio_config` | doc_settings（每本书） | `{ underline, line_thickness, dash_pattern, tweaks, tweak_params, skip_headings }` |
| `style_tweaks` | doc_settings（官方键） | 本插件写入 `["99_typefolio.css"] = true/false` |
| `typefolio_language` | G_reader_settings（预留） | 语言覆盖（`en` / `zh_CN`），默认跟随系统 |
| `typefolio_global_default_config` | G_reader_settings（全局） | 全局基线配置，新书未个性化时继承 |

### 扩展开发规范

- **新特效**：`css_templates.lua` 的 `layout_tweaks` 加 `function(params) -> css` → `tweak_defaults` 给默认值 → `main.lua` 的 `_tweakItems()` 加选项与 `_tweakSubItems()` 参数分支 → 语言包加词条。
- **开关与参数控件**：子菜单首行统一调用 `_tweakEnableItem(key, 英文标题)`；参数控件只用 `_paramRadio`、`_paramSpin`、`_paramToggle`。
- **预设与 CSS 纪律**：预设只改变开关动静、不动用户调好的参数；颜色仅用黑色与 `rgba(0,0,0,α)` 灰阶，覆盖样式必加 `!important`。

## English

Type Folio adds underline and typesetting tweaks (per-line / paragraph / emphasis underlines, highlighter backgrounds, blockquote decoration, header rules, drop caps, dialogue highlight, pure-black text) for CRE books in KOReader.

### Core Architecture

- **Rendering Modes**:
  - **Stylesheet (CSS)**: Generates `styletweaks/99_typefolio.css` via KOReader Style Tweaks.
  - **Direct Drawing**: Paints underlines straight to the framebuffer via `registerViewModule` without affecting line height.
- **Structural Tweaks**: Work across both modes, targeting `h1`, `hr`, `blockquote`, `.dialogue`, and `::first-letter`.
- **Presets & Custom Presets**: Supports built-in style presets, custom preset snapshots (save/rename/delete), and global default baselines for new books.
- **In-Reader Help Guide**: Integrated submenu with categorized quick references and Calibre regex replacement guides.

## 更新记录 / Changelog

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
