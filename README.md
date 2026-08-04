# 文笺 / Type Folio

[中文说明](#中文说明) · [English](#English)

## 中文说明

"文笺"为 EPUB 等 CRE 排版书提供下划线与排版微调：逐行/段落/强调词下划线、荧光笔高亮、引用块装饰、章节标题线条、首字下沉、纯黑增强等，并附三个一键预设。
与"阅笺 / Reading Folio"为同族插件。

### 两种下划线渲染方式（二选一）

菜单顶部的**下划线渲染方式**只管下划线与荧光笔这一层，设置为全局（所有书统一）。
**结构类特效（标题装饰、章尾线、引用块、首字下沉、纯黑）两种方式下都可用**——它们作用于 `h1`、`hr`、`blockquote`、`::first-letter`，与画上去的下划线互不重叠。

|比较项|样式表（CSS）|直接绘制|
|---|---|---|
|原理|生成 CSS 经官方 Style tweaks 装载|用 registerViewModule 把线画到帧缓冲|
|逐行下划线 / 荧光笔|支持|支持|
|段落底线 / 强调词下划线|支持|灰置（需要 DOM 结构，绘制路径拿不到）|
|结构类特效与预设|支持|**同样支持**（走 CSS）|
|影响行高|会（border-bottom 占位）|不会|
|与原书 CSS 冲突|需靠 !important 抢|无|
|改粗细/笔触|触发整篇重排|立即重绘|

绘制模式下的下划线取 crengine 返回的整行文字框宽度，两端对齐的段落里行末空隙也会画上——**横格纸效果**，这是刻意为之。默认会跳过标题与引用块不画（避免和标题边框重叠），可在同一子菜单里关掉。

### 结构类特效的参数

每项特效的菜单行**点最左侧勾选框=开关，点其余区域=进子菜单调参数**（KOReader 的 `checkmark_callback` 机制）。墨水屏上那个小勾选框不好点，所以**子菜单第一行还有一个整行可点的「启用本特效」开关**，两处等效。
该整行开关的标题会实时写出当前状态，形如**「对话高亮：已开启」**，不依赖勾选框也能一眼看出是否生效。
参数存在每本书的配置里。

|特效|可调参数|
|---|---|
| 章节标题装饰 | 边框位置（上下/仅下/仅上/**无**）、线样式（实/虚/点）、粗细 1-5px、是否居中 |
| 章尾分隔线 | 线样式、粗细 1-5px、宽度占比 50/70/85/100% |
| 引用块装饰 | 左竖线粗细（含"无"）、背景底色（无/浅灰/中灰）、是否斜体 |
| 首字放大下沉 | 放大倍数 1.5-3.5em、是否加粗 |
| 对话高亮 | 三个独立开关：背景底色、加粗、斜体；底色深浅（浅/中/深） |
| 强制文字纯黑 | 无参数（无子菜单，直接勾选） |

边框位置选「无」时，只保留标题居中、不再占位留白，线样式与粗细一并灰置。
同理，特效未启用时其全部参数灰置。

### 风格与接口规范（改动必读）

为避免功能越长越乱，所有 tweak 遵循同一套规范，扩展新功能请对齐：

#### 1. 三层职责

|层|文件|管什么|不管什么|
|---|---|---|---|
| CSS 模板 | `css_templates.lua` | 生成 CSS 文本、默认值、参数取值域 | 不感知 UI、不读写设置 |
| 菜单与状态 | `main.lua` | 菜单组装、参数持久化、语言路由 | 不生成 CSS 文本 |
| 文案 | `locales/*.lua` | 所有用户可见字符串 | 不含逻辑 |

不要在 `main.lua` 里拼 CSS 字符串；`_paramXxx` 系列只负责把输入写入 `tweak_params`，CSS 永远由模板函数用 params 现场生成。

#### 2. 参数契约

- **默认值**：`tweak_defaults[key][name]` 是唯一来源，模板函数与菜单共用，禁止在两处各写一份。
- **取值域**：枚举型参数的全部合法值放 `tweak_options[key]`，菜单遍历它生成 radio 列表，模板对越界值自行回落——这样菜单与模板永远不会脱钩。
- **存取**：一律通过 `_getParam` / `_setParam`，缺省自动回落默认值；不要直接读 `config.tweak_params`。

#### 3. 菜单统一风格

- **子菜单首行必放整行开关**：用 `_tweakEnableItem(key, title)`，**不要**手写新的开关项；
  标题必须走 `tr(title)`，状态词 `Enabled` / `Disabled` 已入语言包。
- **参数控件只用三个组合器**：`_paramRadio`（枚举）、`_paramSpin`（数值）、`_paramToggle`（布尔）；
  每个都有 `enabled_func` 内置（未启用时灰置），新参数无需重复实现，除非有额外依赖（例如「底色深浅」只在含底色的模式下可用，用 `extra_enabled` 钩子）。
- **无参数 tweak** 不提供子菜单：在 `_tweakItems()` 选项表里加一行即完成，`sub_items == nil` 时菜单自动退化为单层勾选。
- **禁用逻辑集中**：未启用时整组参数灰置是统一约定，`extra_enabled` 只表达「启用但当前模式下不适用」。

#### 4. 语言包

- **英文为源串**：菜单 `text`、通知、参数标签一律写英文键，添加到 `en.lua`（自身=值），`zh_CN.lua` 给翻译。
- **动态拼接的串用占位符**：状态行 `"%1: %2"` 这类格式串单独入包；不要在代码里拼半句再补半句，会破坏语序可翻译的语言。
- **新增 tweak 命名**遵循「具体对象 + 动作/效果」的动宾或偏正结构，如 `Dialogue highlight`、`Chapter heading decoration`；避免纯动作（`Highlight`、`Decorate`）或纯对象（`Dialogue`、`Headers`）。

#### 5. 预设

- 预设里的 `name` 用英文源串，语言包加翻译；
- 预设只决定**开哪些 tweak**，不动 `tweak_params`——用户已调好的参数必须原样保留；
- 预设要可逆：再切到「恢复默认排版」应回到干净状态。

#### 6. CSS 生成纪律

- **颜色只用 `#000000` 与 `rgba(0,0,0,α)`**：墨水屏彩色无意义，灰阶叠加是唯一可控变量。
- **覆盖原书样式必加 `!important`**：KOReader 的 style tweak 注入点天然比书内样式表弱，不加大概率失效。
- **子元素透明化**：给容器加底色时，里层 `p`/`span`/`div` 要显式 `background: transparent`，否则原书的白底会把容器底色盖掉。
- **display 不动**：段落级 tweak 不要改 `display`，否则原书的缩进/对齐会丢，crengine 也不容错。

### 手势快捷方式

嫌「点菜单 → 翻到排版页 → 找文笺」麻烦，可以给文笺绑一个手势直接弹出菜单：**设置 → 手势（或快捷方式）→ 选一个手势 → 阅读器 → 排版 → 文笺**。插件通过 `Dispatcher:registerAction` 注册了 `typefolio_show` 动作（事件 `ShowTypeFolioMenu`，归在 `rolling` 分区）。

触发后会把文笺的菜单当作一个独立的单页 `TouchMenu` 直接弹出，内容与主菜单里那一份完全一致（同一个 `menuItems()`）。没有打开书时不响应。

### 安装

把 `typefolio.koplugin` 复制到 KOReader 的 `plugins/` 目录并重启。菜单入口在**阅读器菜单 → 排版分区 → 文笺**（通过 `registerToMainMenu` 注册）。仅在阅读器中出现（`is_doc_only = true`）。

菜单与通知文案支持简体中文与英文，跟随 KOReader 界面语言自动切换（语言包体系与阅笺同款，见 `locales/`）。

### 工作原理（改动前必读）

#### 样式表路径

1. KOReader 只扫描 `DataStorage:getDataDir()/styletweaks/` 这一个用户 CSS 目录；本插件把组合后的规则写入其中的 `99_typefolio.css`。
2. 用户 tweak 的 id = 完整文件名（含 `.css`）。每本书的启用清单存于 doc_settings 键 **`style_tweaks`**（注意有下划线）。
3. 关书时 `ReaderStyleTweak:onSaveSettings` 会用内存态整表覆盖写回，所以应用样式时必须同步 `ui.styletweak.doc_tweaks` 并调用 `updateCssText(true)` 即时生效——只写 doc_settings 会被冲掉。停用时要写 `false` 而不是 `nil`：`updateCssText` 里 `nil` 表示"未表态"，会让全局启用的同名 tweak 重新生效。
4. `updateCssText(true)` 会广播 `ApplyStyleSheet` 触发整篇重排，代价不低，故只在样式表内容真的变化时才调用。
5. 已知限制：CSS 文件全局共享，内容以最后一次"应用"的那本书为准（各书的启用开关彼此独立）；文件首次创建的那个会话内不会生效（tweak 注册发生在开书时），重开书即可。**绘制模式下的下划线不走 CSS，故不受这两条约束；但结构类特效仍走 CSS，仍然受约束。**

#### 直接绘制路径

1. 在 `onReaderReady` 里用 `view:registerViewModule` 注册（PDF/DjVu 直接跳过，行框 API 是 CRE 专有的）。官方没有反注册接口，故照 perceptionexpander 的做法始终注册、靠 `paintTo` 里的 `enabled` 早退来开关。
2. 行框走 `getXPointer()` + `getPageXPointer(page)` → `getScreenBoxesFromPositions`。选这条而非全屏 `getTextFromPositions`，是因为后者被标记 `add_buffer_trash`，每次调用都会作废 crengine 页面位图、逼一次整页重新光栅化；前者只是 `cache_by_tag`。取不到时才回退到贵的那条。
3. CRE 的行框已是屏幕坐标，可直接 `paintRect`，无需偏移换算（官方 `drawHighlightRect` 同样忽略传入的 x/y）。但 `getPageXPointer` 可能落在块起点而非页内首个文字节点，故一律按可见区域裁剪。
4. `view_modules` 是独立哈希表，**不在** `WidgetContainer:propagateEvent` 遍历的数组里——绘制模块收不到任何事件。失效由主插件（它在 ReaderUI 数组里）转发。
5. 行框惰性计算并缓存在 `paintTo` 里，而不是在事件处理器里算：翻页时本来就要整页重绘，搭顺风车不额外花钱。
6. 跳过标题：xpointer 字符串里带标签名（形如 `/body/DocFragment/body/div/p[12]/sup[3]/a[3].0`），用 `getNearestWordFromPosition` 取到后匹配 `/h%d` 与 `/blockquote` 即可判别。该 API 是 `cache_by_tag`、不作废页面位图。为省调用，先用「行高众数 ±10%」当筛子，只探测高度异常的少数行——首字下沉会让所在正文行变高从而触发探测，但探测结果是正文，不会误判（高度只作筛子，xpointer 才是判据）。

### 设置键

|键|位置|含义|
|---|---|---|
| `typefolio_render_mode` | G_reader_settings（全局） | `css` / `paint`，默认 `css` |
| `typefolio_config` | doc_settings（每本书） | `{ underline, line_thickness, dash_pattern, tweaks, tweak_params, skip_headings }` |
| `style_tweaks` | doc_settings（官方键） | 本插件写入 `["99_typefolio.css"] = true/false` |
| `typefolio_language` | G_reader_settings（预留） | 语言覆盖（`en` / `zh_CN`），暂无菜单，默认跟随系统 |
| `typefolio_global_default_config` | G_reader_settings（全局） | 「保存当前设置为默认值」时写入的全局基线；新书未个性化时回落到这份 |

### 扩展

- **新特效**：`css_templates.lua` 的 `layout_tweaks` 加 `function(params) -> css`，
  在 `tweak_defaults` 里给默认值 → `main.lua` 的 `_tweakItems()` 选项表加一行、
  `_tweakSubItems()` 加参数分支 → 两个语言包加词条。
- **新参数**：模板函数里读 `params.xxx`（缺省回落 `tweak_defaults`）→
  `_tweakSubItems()` 里用 `_paramRadio` / `_paramSpin` / `_paramToggle` 加一项。
  枚举取值域放 `tweak_options`，菜单与模板共用一份。
- **新增/修改子菜单开关**：统一调用 `_tweakEnableItem(key, 英文标题)`，
  标题会渲染为「标题：已开启/已关闭」，两个语言包只需补标题本身。
- **新预设**：`css_templates.lua` 的 `presets` 加条目（`name` 用英文源串），
  语言包加翻译；菜单自动按 key 字母序列出。
- **新绘制效果**：`painter.lua` 的 `paintTo` 加分支 → `main.lua` 的
  `_underlineItems()` 加选项（不带 `css_only`）→ 两个语言包加词条。
- **新语言**：`locales/` 加语言包并注册进 `locale_registry.lua`，缺词条自动
  回退英文再回退 gettext。

## English

Type Folio adds underline and typesetting tweaks (per-line / paragraph /
emphasis underlines, highlighter backgrounds, blockquote decoration, header
rules, drop caps, pure-black text) for CRE books. Type Folio is a sibling of
Reading Folio.

**The "Underline rendering" switch at the top of the menu picks one of two
backends** (a global setting, shared by all books). It governs *only* the
underline/highlighter layer — the structural tweaks below work in both modes,
since they target `h1`/`hr`/`blockquote`/`::first-letter` and never overlap the
painted underlines.

- **Stylesheet (CSS)** — generates `styletweaks/99_typefolio.css`, loaded
  through KOReader's official Style tweaks mechanism.
- **Direct drawing** — paints underlines and highlighter backgrounds straight
  onto the framebuffer via `ReaderView:registerViewModule`. Paragraph-bottom
  and emphasis underlines are greyed out (they need DOM structure that the
  geometry-only path cannot see). In exchange it does not disturb line height,
  does not fight the book's own CSS, and applies instantly without a re-render.
  Underlines span the full line box, so justified paragraphs get
  ruled-paper-style full-width lines. Headings and blockquotes are skipped by
  default (so they don't collide with the heading-border tweak); this can be
  turned off in the same submenu.

**Structural tweaks are parameterized.** Tapping the leftmost checkbox toggles
the tweak; tapping anywhere else on the row descends into its parameters
(KOReader's `checkmark_callback` mechanism). Because that small checkbox is
fiddly on e-ink, **the first row inside each submenu is a full-width "Enable
this effect" toggle** that does the same thing. Heading decoration exposes
border position (including *no border*) / line style / thickness / centering;
chapter-break rules expose line style / thickness / width; blockquotes expose
bar thickness / background tint / italics; drop caps expose size / bold;
dialogue highlight exposes three independent toggles (tint / bold / italic)
plus tint intensity.
Parameters are stored per book, and are greyed out while their tweak is off.
The full-width toggle row in each submenu renders its own live status, so the
on/off state is legible at a glance without squinting at the checkmark.

**Extending the plugin.** All tweaks share one contract:

- CSS lives in `css_templates.lua` as `function(params) -> css`; `main.lua`
  never concatenates CSS. Parameter defaults live in `tweak_defaults`,
  enum domains in `tweak_options` — one source of truth, shared by menu and
  template.
- Sub-menu first row is always a full-width toggle built via
  `_tweakEnableItem(key, english_title)`; the row renders `<title>: Enabled`
  or `<title>: Disabled`. Don't hand-roll new toggle rows.
- Parameter widgets come from three combinators only: `_paramRadio` for
  enums, `_paramSpin` for numbers, `_paramToggle` for booleans. Disable-while-
  off is built in; use `extra_enabled` only for "enabled but not applicable
  in the current mode" cases (e.g. tint intensity under a non-tint style).
- All user-visible strings go through `locales/` with English source keys;
  dynamic pieces use `%1`-style placeholders rather than string concat.
- CSS discipline: only pure black and `rgba(0,0,0,α)` (e-ink is grayscale),
  always `!important` when overriding book styles, explicitly transparent
  inner `p`/`span`/`div` when painting container backgrounds, and never touch
  `display` on paragraph nodes.

Install by copying `typefolio.koplugin` into KOReader's `plugins/` folder
and restarting. The menu entry lives in the reader menu's typeset section
(registered via `registerToMainMenu`). Reader-only (`is_doc_only = true`). Menu
strings are bilingual (English / Simplified Chinese) using the same locale
system as Reading Folio.

The menu's topmost row is a Help entry that pops an in-reader guide explaining
what each section does. The preset strip has two global-default actions:
"Save current as default for new books" stores the current configuration to a
global key; "Clear global default settings" removes it without touching the
current book.

**Gesture shortcut.** To skip the menu-then-page-then-find dance, bind a
gesture under Settings → Gestures → Reader → Typeset → Type Folio. The plugin
registers a `typefolio_show` Dispatcher action (event `ShowTypeFolioMenu`, in
the `rolling` section) that pops its own menu straight up as a standalone
single-tab `TouchMenu`, built from the very same `menuItems()` the main menu
uses. It is a no-op when no document is open.

Key mechanics, CSS path: KOReader only scans
`DataStorage:getDataDir()/styletweaks/`; per-book enablement lives in the
`style_tweaks` doc setting; the in-memory `ui.styletweak.doc_tweaks` must be
kept in sync (`updateCssText(true)` applies immediately) because
`onSaveSettings` overwrites the doc setting from memory on book close. Store
`false` rather than `nil` to disable — `nil` means "no opinion" and lets a
globally-enabled tweak of the same id apply. The generated CSS file is shared
globally (last writer wins); a freshly created file is picked up on the next
book open.

Key mechanics, drawing path: registered in `onReaderReady`, skipped entirely
for paging (PDF/DjVu) documents. Line boxes come from `getXPointer()` plus
`getPageXPointer(page)` fed to `getScreenBoxesFromPositions`, which is only
`cache_by_tag`; the full-screen `getTextFromPositions` alternative is tagged
`add_buffer_trash` and forces a full crengine re-rasterization on every call,
so it is used only as a fallback. CRE line boxes are already in screen
coordinates, but are clipped to the visible rect because `getPageXPointer` may
land on a block start above the page top. Note that `view_modules` is a
separate hash table and is *not* walked by `WidgetContainer:propagateEvent`, so
the drawing module receives no events — cache invalidation is forwarded from
the main plugin object, and boxes are recomputed lazily inside `paintTo` to
piggyback on the repaint that a page turn triggers anyway. Heading detection
matches `/h%d` and `/blockquote` against the xpointer string returned by
`getNearestWordFromPosition` (also `cache_by_tag`), probing only lines whose
height deviates from the page's modal line height.

## 更新记录 / Changelog

### 2026-08-01（四）

- 新增**手势快捷方式**：注册 `typefolio_show` 动作（事件 `ShowTypeFolioMenu`），绑定后一步弹出文笺菜单，不必再「点菜单 → 翻页 → 找文笺」。

### 2026-08-01（三）

- 四组可配置特效的子菜单首行加「启用本特效」整行开关——墨水屏上外层那个小勾选框不好点。
- 章节标题装饰的边框位置新增「无」：只居中、不画线，且不再占位留白。

### 2026-08-01（二）

- 互斥范围收窄到**仅下划线**：结构类特效（标题装饰、章尾线、引用块、首字下沉、纯黑）在两种渲染方式下都可用。
- 结构类特效由固定开关升级为**可调参数**：`layout_tweaks` 从 CSS 字符串改为 `function(params) -> css`，菜单行支持"点勾选框=开关、点其余=进子菜单"。
- 绘制模式下默认跳过标题与引用块，避免与标题边框重叠；可单独关闭。

### 2026-08-01（一）

- 新增**直接绘制**渲染后端，与原有样式表路径二选一（全局设置 `typefolio_render_mode`）。逐行下划线与荧光笔可脱离 CSS，不再影响行高。
- 样式表停用改为写 `false` 而非 `nil`，避免全局同名 tweak 意外复活。
- 仅在样式表内容真的变化时才调 `updateCssText(true)`，避免无谓的整篇重排。

### 2026-07-27

- 菜单通过 `registerToMainMenu` 注册进排版分区，支持真正的菜单分隔线与单选圆点（radio）。
- 全部文案接入双语语言包体系（`locales/en.lua`、`zh_CN.lua`）。
- CSS 目录使用官方 `DataStorage:getDataDir()/styletweaks/`，并同步内存态即时生效。

