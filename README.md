# 《反物质维度》简体中文汉化补丁（0.3.6 社区热修版）

这是适用于 Steam Windows 版《Antimatter Dimensions》（游戏版本 11.5，Build 16370635）的便携简体中文汉化补丁。

本仓库在上游 0.3.2 补丁的基础上，对遗漏翻译做了一次系统性的整理与修复（详见下文[本仓库的工作](#本仓库的工作)）。补丁包含中文文本、中文字体和安装/卸载工具；无需安装 Node.js、Python 或其他软件，也不需要联网。

补丁版本号（`0.3.6`）与本仓库的 payload 修订绑定：安装器把「版本号相同」视为「payload 相同」，因此每次改动 `payload/zh-cn-catalog.js` 都会递增此版本号，这样已装旧版的用户直接双击 `Install-Chinese.cmd` 即可自动升级。

**本仓库不包含、也不分发任何游戏本体文件**；安装器仅替换游戏目录中的 `resources/app.asar`，并会先校验游戏版本与原文件哈希。

## 鸣谢与内容来源

本补丁的译文并非从零翻译，其来源链条如下，在此向所有贡献者致谢：

- **百度贴吧社区**：部分译文来自百度贴吧社区已有的《反物质维度》汉化结果（安卓版中文翻译），是最早的社区翻译基础；
- **aquamarine309/ADChinese**（MIT）：上游 0.3.2 补丁的译文与运行时框架整理自该项目，其在安卓版社区汉化的基础上做了大量校对、润色与补充翻译；
- **《反物质维度》游戏本体**：IvarK 等（MIT）；
- **霞鹜文楷字体**：LXGW（SIL OFL 1.1）。

完整的第三方许可文本见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 `payload/fonts/OFL.txt`。

## 本仓库的工作

以下全部修改完成于 2026 年 9 月 26 日至 10 月 26 日的一次连续工作会话（在与 AI 助手的协作中完成），仅修改 `payload/zh-cn-catalog.js` 一个文件（翻译目录），未改动运行时脚本 `zh-cn-runtime.js`：

| 项 | 上游 0.3.2 | 本仓库 | 增量 |
| --- | --- | --- | --- |
| 精确词条 | 4,816 | 5,746 | +930 |
| 模式规则 | 1,084 | 1,416 | +332 |
| 碎片规则 | 17 | 32 | +15 |

分轮修复内容：

1. **第一轮（复制器页 / 永恒按钮 / 顶栏）**：补齐复制器升级按钮（`间隔：`、`费用：`、`复制器星系上限：`）、自动星系开关、永恒按钮速率行（`EP/min` 变体）、`（下一永恒点数需 …）`；为带时间的规则补上时长转换（`14 minutes and 31 seconds` → `14 分钟 31 秒`）；修正两条结构化规则译文的节点形状，使其能被运行时安全替换接受。
2. **第二轮（挑战系统 / 统计 / 自动购买器）**：无限/永恒挑战的目标行与全部限制变体、`奖励：` 前缀的奖励词条（该前缀与描述在同一文本节点内）、挑战开始弹窗正文，并为 `Inside this … Challenge, …` 三条规则开启捕获递归翻译（覆盖全部 28 个挑战弹窗）；永恒里程碑标题与计数、统计页计数句、自动购买器标签。
3. **第三轮（批量补翻）**：从游戏源码（source map 还原的 2,518 个文件）提取 1,682 个未覆盖文本模板，按长度分 9 批由多个并行翻译代理翻译，经机械校验（占位符数量与位置、HTML 标签序列、必须含汉字、规范化冲突检查——避免触发运行时的冲突删除保护）后合并 **+848 精确词条、+202 模式规则**；另 530 条经代理与人工审计确认为非界面文本（CSS、调试信息等）正确跳过。此轮覆盖了帮助页、新闻滚动条、设置、模态框等大面积剩余英文。
4. **第四轮（运行时拼装字符串）**：修复无法靠整句词条覆盖的动态拼装文本——快捷键弹窗的枚举句（`makeEnumeration` 双/三元素形态）、`同时按下 Alt 和 Shift…` 句、确认选项弹窗的数据驱动标签（`Sacrifice: OFF` 等 9 个碎片）、离线永恒里程碑的全部 9 种拼装形态、复制器倒计时的 `(… total)` 追加后缀。
5. **第五轮（维度行 / 星系 / 触发行）**：时间/无限维度行名的序数（`1st Time Dimension` → `第 1 时间维度`，经 `ordinal` 捕获转换）、`Cost: … EP/IP` 购买按钮、`Time Shards` 词条与既有规则捕获转换、`遥远/远端反物质星系` 头部、自动永恒标签（渲染时追加冒号导致的失配）、大坍缩自动购买器的 `Will trigger at …` 状态行族。
6. **第六轮（时间研究 / 永恒挑战 / 时间跨度）**：时间研究描述与解锁条件文本、永恒挑战 `Requirement:` 前缀与需求句、时间研究商店页脚的计数行，以及 `TimeSpan` 各单复数形态的节点形状（`N hours, N minutes and N seconds` 全组合）。
7. **第七轮（零散运行时拼装文本）**：复制器升级自动购买器按钮名（`Replicanti Chance/Interval/Max Galaxies`，运行时模板拼接）、时间研究商店页脚的 `You have N total Time Theorems.` 与 `You are gaining N TT/sec|hour.`、膨胀时间研究的 `Requirement:` 需求句（`… and N rows of Achievements`、仅 `N Eternity Points`）与 EC11/EC12 的 `Use only the … path`、永恒升级页的 `The cost for the ×N multiplier jumps at …` 与 `Capped: …`、无限维度页的 `Auto: ON/OFF`。
8. **第八轮（永恒挑战页）**：`ToggleButton` 的 `标签 + ON/OFF` 单节点形态（`Show all known challenges: OFF`、`Auto Eternity Challenges: ON`、`Auto-collapse space:`、`Never Auto-purge Glyphs accepted by filter:` 等 21 个标签——此前只有裸标签词条，追加状态词后便失配）；永恒挑战卡片的 `Completed N times`、裸 `Reward:`、`Goal Span: … IP - … IP` 与 `Next: <效果值>`；`Next:`/`Currently:` 两个 `EffectDisplay` 规则开启捕获递归翻译，配合 `N AG later`、`N per second`、`N (After TS31: M)`、`x^N` 四条效果值规则覆盖 EC5/6/7/10/11/12 的奖励显示；EC 说明段被拆成两节点导致的“前句译成整句、后句留英文”；EC6 描述（含无名氏乱码变体）。

9. **第九轮（无限维度页）**：复制器面板的 `You are gaining N Replicanti Galaxies per second`（含 `(all Replicanti Galaxies within …)` 后缀，单复数两种形态）此前完全没有词条；`You are currently in <挑战名>` 规则命中了骨架但不翻译捕获，导致挑战名保留英文——为该规则开启捕获递归翻译，并修正 `in a Doomed Reality. Good luck.` 那条规则（它按**内部计算值**而非**渲染节点**编写，把 `You are currently in` 一起吞进了捕获），补上 Pelle 无挑战时的整句词条；顺带修掉两处译文残留（`距离 无限 复制器还有` 的空格、`无限复制器 （需要⏎…）` 的换行），以及两个把 `Time Theorem(s)` 误译为「时间定理」（全目录其余处均为「时间之理」）的碎片规则，并补 `Time Dilation` 碎片以覆盖 `时间膨胀 + 永恒挑战 N` 这类拼接串。

10. **第十轮（永恒挑战描述）**：EC7 的描述在源码里是两段字符串拼接，目录只收录了拆开的两半，整句永远匹配不上——补整句词条；EC9/EC11/EC12（解锁现实后）的规则末尾带一个承接「可选 Pelle 句」的 `{{#N}}`，该后缀为空时匹配器会整条拒绝（`end <= cursor`），导致描述全英文——补无后缀的基础词条；EC10 同类问题，另为其捕获开启递归翻译；新增「The Pelle-Specific effect…」前后两种位置的包装规则，使佩勒（毁灭现实）下也能整体译出；顺带修掉 EC5 译文里多余的空格与 EC10 译文里「。（」的标点。

11. **第十一轮（时间研究树标题）**：树节点标题由 `TimeStudyButton.hintText` 拼成 `"<id> <路径名>"`（`NormalTimeStudies.pathList`），而目录里只有**裸路径名**（`Antimatter Dims`、`Active` 等）的词条——带 ID 前缀的节点永远匹配不上，于是碎片把 `Antimatter` 译成「反物质」、`Dims` 留在英文，显示为 `71 反物质 Dims`。为 8 个路径名各补一条带整数捕获的规则（`71 反物质维度`、`72 无限维度`、`73 时间维度`、`121 活跃`、`122 被动`、`123 挂机`、`221 光明`、`234 黑暗`）。

**验证方法**：将补丁运行时的匹配核心原样移植到独立验证台；每轮修改都通过占位符/标签/汉字/冲突机械校验，并运行覆盖全部历史修复的回归用例（最终 216 用例）；另对全部 33 个 `ToggleButton` 标签逐一扫描 `标签 ON/OFF` 形态。对游戏 `app.asar` 的每次重建都做 764 个文件的字节级回比对。静态全量覆盖率扫描显示已覆盖 UI 候选从 12,710 条提升至 13,579 条。

**兼容性说明**：

- 本包 `payload/zh-cn-catalog.js` 与上游 0.3.2 的哈希不同。已安装上游 0.3.2 的用户请先运行上游的 `Uninstall-Chinese.cmd` 还原原版，再安装本包。
- 从本仓库的旧热修版（0.3.2）升级：直接双击 `Install-Chinese.cmd` 即可，安装器会从已验证的原版备份重建。**注意**：重建基于原版 `app.asar`，因此若你另外装了修改 `app.asar` 的 Mod（如 HoldKeys 长按 Mod），升级后需要重新安装该 Mod（按「先汉化、后其它 Mod」的顺序）。
- 本包可与 HoldKeys 长按 Mod（锚点式安装的版本）共存；建议安装顺序：先汉化、后其它 Mod。
- 游戏更新后请先运行 `Check-Patch.cmd` 查看状态，等待适配版本，不要手动替换 `app.asar`。

## 安装

1. 完全退出游戏。
2. 可先用 PowerShell 运行 `Get-FileHash .\AD-Zh-CN-Patch.zip -Algorithm SHA256`，并与 Release 页面提供的 SHA-256 值比较。
3. 解压整个汉化包，不能直接在压缩包内运行。
4. 双击 `Install-Chinese.cmd`。
5. 看到安装成功提示后，从 Steam 启动游戏。

安装器会读取 Steam 的库配置，因此游戏安装在默认目录、其他磁盘或自定义 Steam 库时都无需修改脚本。只找到一份受支持的游戏时，安装器会直接显示该目录并请你确认；未找到或找到多份时，会打开目录选择窗口，请选择包含 `Antimatter Dimensions.exe` 的游戏目录。游戏目录没有写入权限时，Windows 才会弹出管理员授权窗口。

便携版 Steam 未登记在 Windows 中时，可以把 Steam 根目录（其下应有 `steamapps` 文件夹）拖到 `Install-Chinese.cmd` 上。也可以拖入下列任一位置：

- 《反物质维度》游戏目录；
- `Antimatter Dimensions.exe`；
- 游戏目录下的 `resources` 文件夹或 `resources\app.asar`；
- Steam 库根目录、其 `steamapps` 文件夹或 `steamapps\common` 文件夹。

一次只能拖入一个位置。安装器仍会校验 Steam App ID、Build ID、游戏版本和 `app.asar` 哈希；路径正确但版本不受支持时，不会强行安装。

如果希望通过命令行指定位置，可在汉化包目录打开 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch.ps1 -Action Install -GameRoot "D:\SteamLibrary\steamapps\common\Antimatter Dimensions"
```

同一 Windows 用户一次只管理一份游戏副本。电脑中有多份《反物质维度》时，请在目录选择窗口中明确选择目标。

## 检查与卸载

- 双击 `Check-Patch.cmd`：只读检查当前状态，不修改游戏文件。
- 双击 `Uninstall-Chinese.cmd`：校验备份后恢复原版文件。
- 检查或卸载时，也可将游戏目录、游戏 EXE、`resources\app.asar` 或 Steam 库根目录拖到对应的 `.cmd` 文件上。

原版备份和安装状态保存在：

```text
%LOCALAPPDATA%\AntimatterDimensionsZhPatch
```

备份不放在游戏目录内，因此 Steam 验证文件、覆盖安装或删除汉化包后仍可用于卸载。卸载器只会恢复它亲自安装且哈希完全匹配的文件，不会覆盖未知版本。

## 汉化范围

补丁覆盖主要界面、设置、挑战、成就说明、时间研究、天神内容、帮助页、商店/云存档提示及新闻文本。为避免破坏脚本，自动机代码关键字、存档数据、内部标识符和 URL 保持原样。

普通与隐藏成就的原始图片内含英文标题；补丁会完整保留这些图片及其中的文字，仅汉化悬浮提示中的成就名称、达成条件和奖励。启动画面等少量装饰性图片仍可能包含原作标题；专有名词、按键名和社区梗会在确有必要时保留拉丁字母。

## 文件安全

- 补丁只替换游戏目录中的 `resources/app.asar`。
- 补丁不读取或修改游戏存档。
- 安装、检查和卸载过程均不联网。

## 许可

本仓库遵循 [MIT License](LICENSE)。译文整理相关的第三方许可与致谢见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 分发

可以将完整 ZIP 原样发给朋友。请保留 `LICENSE`、`THIRD_PARTY_NOTICES.md` 和 `payload\fonts\OFL.txt`，并且不要单独售卖内含字体。
