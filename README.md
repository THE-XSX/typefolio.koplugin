# 文笺 / Type Folio

[中文说明](#中文说明) · [English](#english)

## 中文说明

"文笺"为 EPUB 等 CRE 排版书提供下划线与排版微调：逐行/段落/强调词下划线、
荧光笔高亮、引用块装饰、章节标题线条、首字下沉、纯黑增强等，并附三个一键预设。
生成的 CSS 通过 KOReader 官方 **Style tweaks（样式微调）** 机制装载。与"阅笺 / Reading Folio"为同族插件。

### 安装

把 `typefolio.koplugin` 复制到 KOReader 的 `plugins/` 目录并重启。菜单入口
在**阅读器菜单 → 排版分区 → 文笺**（通过 `registerToMainMenu` 注册）。仅在阅读器中出现（`is_doc_only = true`）。

菜单与通知文案支持简体中文与英文，跟随 KOReader 界面语言自动切换
（语言包体系与阅笺同款，见 `locales/`）。

### 工作原理（改动前必读）

1. KOReader 只扫描 `DataStorage:getDataDir()/styletweaks/` 这一个用户 CSS
   目录；本插件把组合后的规则写入其中的 `99_typefolio.css`。
2. 用户 tweak 的 id = 完整文件名（含 `.css`）。每本书的启用清单存于
   doc_settings 键 **`style_tweaks`**（注意有下划线）。
3. 关书时 `ReaderStyleTweak:onSaveSettings` 会用内存态整表覆盖写回，所以
   应用样式时必须同步 `ui.styletweak.doc_tweaks` 并调用
   `updateCssText(true)` 即时生效——只写 doc_settings 会被冲掉。
4. 已知限制：CSS 文件全局共享，内容以最后一次"应用"的那本书为准（各书的
   启用开关彼此独立）；文件首次创建的那个会话内不会生效（tweak 注册发生在
   开书时），重开书即可。

### 设置键

| 键 | 位置 | 含义 |
|---|---|---|
| `typefolio_config` | doc_settings（每本书） | `{ underline, line_thickness, dash_pattern, tweaks }` |
| `style_tweaks` | doc_settings（官方键） | 本插件写入 `["99_typefolio.css"] = true` |
| `typefolio_language` | G_reader_settings（预留） | 语言覆盖（`en` / `zh_CN`），暂无菜单，默认跟随系统 |

### 扩展

- **新特效**：`css_templates.lua` 的 `layout_tweaks` 加模板 →
  `main.lua` 的 `_tweakItems()` 选项表加一行 → 两个语言包加词条。
- **新预设**：`css_templates.lua` 的 `presets` 加条目（`name` 用英文源串），
  语言包加翻译；菜单自动按 key 字母序列出。
- **新语言**：`locales/` 加语言包并注册进 `locale_registry.lua`，缺词条自动
  回退英文再回退 gettext。

## English

Type Folio adds underline and typesetting tweaks (per-line / paragraph /
emphasis underlines, highlighter backgrounds, blockquote decoration, header
rules, drop caps, pure-black text) for CRE books, applied through KOReader's
official Style tweaks mechanism via a generated
`styletweaks/99_typefolio.css`. Type Folio is a sibling of Reading Folio.

Install by copying `typefolio.koplugin` into KOReader's `plugins/` folder
and restarting. The menu entry lives in the reader menu's typeset section
(registered via `registerToMainMenu`). Reader-only (`is_doc_only = true`). Menu
strings are bilingual (English / Simplified Chinese) using the same locale
system as Reading Folio.

Key mechanics: KOReader only scans `DataStorage:getDataDir()/styletweaks/`;
per-book enablement lives in the `style_tweaks` doc setting; the in-memory
`ui.styletweak.doc_tweaks` must be kept in sync (`updateCssText(true)` applies
immediately) because `onSaveSettings` overwrites the doc setting from memory
on book close. The generated CSS file is shared globally (last writer wins);
a freshly created file is picked up on the next book open.

## 更新记录 / Changelog

### 2026-07-27

- 菜单通过 `registerToMainMenu` 注册进排版分区，支持真正的菜单分隔线与单选圆点（radio）。
- 全部文案接入双语语言包体系（`locales/en.lua`、`zh_CN.lua`）。
- CSS 目录使用官方 `DataStorage:getDataDir()/styletweaks/`，并同步内存态即时生效。

