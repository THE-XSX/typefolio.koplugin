# KOReader 插件开发与审查规范 (Plugin Development & Review Standard)

本规范用于指导 KOReader 插件（如 `typefolio`、`readingfolio` 等）的日常功能开发、重构及发布前审查，确保**“代码无隐患、文档不超前、状态不串乱、交互有防错”**。

---

## 一、 开发完成对照检查表 (Review Checklist)

每次功能开发或 Bug 修复完成后，请逐项对照检查并打勾 `[x]`：

### 1. 版本与元数据一致性
- [ ] **版本号统一**：`_meta.lua` 中的 `version` 与 `README.md` changelog 中的版本号完全一致。
- [ ] **更新日志完整**：本次改动的关键点已记录在 `README.md` 的更新日志中。

### 2. 文档-实现完全对齐
- [ ] **功能零虚标**：README、菜单项、应用内帮助中声称的功能、设置键（Setting Key），在代码中均有完整实现。
- [ ] **废弃功能清理**：删除或未实现的逻辑，已从 README、帮助弹窗、语言包中彻底移除。
- [ ] **已知限制显式化**：受 KOReader 架构限制的逻辑（如全局单 CSS 文件机制），已在 README 的「已知限制」小节明确说明。

### 3. 多书生命周期与状态隔离
- [ ] **开书自动刷写**：在 `onReaderReady`（或开书事件）中，严格按当前书籍的 `doc_settings` 重刷输出状态（如 CSS 文件或 Painter 参数），防止跨书切换串样式。
- [ ] **静默同步 (skip_persist)**：开书时的自动同步只刷新文件/内存状态，避免向全新书籍静默写入默认空配置。
- [ ] **预设与配置分离**：全局预设库（如模板）与单书个性化开关（如当前选择的 Preset / 各种特效开关）存储位置清晰、互不干扰。

### 4. Crengine / Native 接口防崩溃
- [ ] **Native 调用的 `pcall` 包裹**：凡涉及 `getWordBoxesFromPositions`、`getTextFromPositions`、`getNearestWordFromPosition` 等底层 xpointer 接口，全部进 `pcall` 防护。
- [ ] **瞬态/逆序指针退化处理**：TOC 跳转、换页、文档重排瞬间，若指针逆序或计算失败，优雅返回空结果（退化为本帧不画），绝不抛出异常导致 KOReader 闪退。

### 5. UI 交互与边界校验
- [ ] **模式互斥与动态灰置**：当切到不支持特定参数的模式时，对应菜单项通过 `enabled_func` 正确灰置，并在切模式时对原无效勾选项进行安全降级。
- [ ] **自定义输入严格校验**：所有 `InputDialog` 输入（如粗细 px、数值参数）在保存前做 `tonumber` 范围判断，非法输入阻止保存并弹出 UI 提示。

### 6. i18n 多语言与帮助闭环
- [ ] **双语 1:1 镜像对齐**：`locales/zh_CN.lua` 与 `locales/en.lua` 键位完全一致，无遗漏通用词（如 `Save`），无废弃死键。
- [ ] **使用指南完整**：应用内「使用指南」包含概览、能力边界、内置预设说明与手势入口。

---

## 二、 核心开发规范与落地标准

### 1. 生命周期与 CSS 文件写入规范
```lua
-- 示例：开书时刷新状态，但不强制持久化默认配置
function Plugin:onReaderReady()
    self:applyStyle(self:getConfig(self.ui), { skip_persist = true })
end
```
- **原则**：全局单文件输出（如 `99_typefolio.css`）属于共享介质，每次开书必须按当前书重写介质内容。

### 2. Native 接口安全防护规范
```lua
-- 示例：对底层 xpointer / box 抓取使用安全包裹
local ok, boxes = pcall(function()
    return document:getWordBoxesFromPositions(xp0, xp1)
end)
if not ok or not boxes or type(boxes) ~= "table" then
    return {} -- 安全退化
end
```
- **原则**：目录跳转、跨章翻页时 Crengine 处于重排瞬态，绝对不能信任原生指针直接返回的结果。

### 3. 输入框校验规范
```lua
-- 示例：输入框回调校验
local num = tonumber(input_text)
if not num or num < 1 or num > 20 then
    UIManager:show(Notification:new{ text = _("Please enter a valid number (1-20).") })
    return true -- 返回 true 阻止对话框关闭
end
```
- **原则**：非法值严禁直接写入 `doc_settings`。

---

## 三、 审查流程执行指南

1. **功能开发完成后**：打开本文件 `DEVELOPMENT_SPEC.md`。
2. **逐条核对**：逐项对照 CheckList 进行静态检查。
3. **真机/模拟器测试**：
   - 切换不同书籍验证是否串样式。
   - 打开目录跳转验证是否崩溃。
   - 尝试非法输入验证提示是否生效。
4. **测试无误后打勾提交**。

---

## 四、 Release 发布规范与打包标准 (Release Specification)

### 1. 版本与发布前检查
- **三处版本号一致**：检查 `_meta.lua` 中的 `version`、`README.md` changelog 中的最新版本号、Git Tag 保持完全一致（格式如 `v2.1.2`）。
- **打包排除杂质**：Zip 安装包根目录必须包含插件根文件夹（如 `typefolio.koplugin/`），且严格排除 `.git/`、`.DS_Store` 及临时构建缓存。
- **用脚本打包，不要手工 zip**：在仓库根目录执行 `python3 tools/package.py`，产物为 `typefolio.koplugin.zip`。在仓库内直接 `zip -r … .` 会把 `main.lua`、`core/` 等摊在压缩包根目录，解压进 `koreader/plugins/` 后文件散落一地、插件根本不会加载——这正是脚本存在的原因。脚本会在写出后重新打开压缩包自检：全部条目位于 `typefolio.koplugin/` 之下、`_meta.lua` 与 `main.lua` 存在、`tests/`、`.git/`、`.DS_Store`、`*.py`、旧 zip 均未混入，任一项不满足即报错退出（`-l` 可列出全部打包文件）。

### 2. Release Notes / 变更说明模板格式
版本发布时，Release 文档/页面描述须统一采用**标准 Markdown 中英双语分块格式**，每条均使用无序列表及加粗标题简明总结变动：

```markdown
# Release vX.Y.Z

## What's Changed / 变更说明

### 中文 (Simplified Chinese)
- **模块/功能名**：变更说明...
- **模块/功能名**：变更说明...

### English
- **Module/Feature**: Change description...
- **Module/Feature**: Change description...
```


