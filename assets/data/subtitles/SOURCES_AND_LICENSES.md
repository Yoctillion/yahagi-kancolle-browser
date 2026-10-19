# 舰娘语音字幕：来源与许可

本目录包含简体中文、繁體中文、日本語、English、한국어 的舰娘语音字幕文本，不包含舰队 Collection 的语音、图片或其他游戏资源。所有语言均来自现有社区台词资料，未使用机器翻译。

| 文件 | 来源 | 数据版本 | 舰娘条目数 | 字幕条目数 | UTF-8 字节数 |
| --- | --- | --- | ---: | ---: | ---: |
| `zh-cn.json` | kcwiki 简中 | `2026101805` | 860 | 33,709 | 5,551,642 |
| `zh-tw.json` | kcwiki 繁中 | `2026101805` | 860 | 33,709 | 5,551,924 |
| `ja-jp.json` | kcwiki 日文 | `2026101805` | 860 | 33,709 | 6,586,949 |
| `en-us.json` | KC3 改英文 | `20260804124356` | 752 | 16,222 | 1,395,903 |

上表快照获取日期均为 2026-10-18（Asia/Tokyo）。当前运行时以 kcwiki 三语正文组和下述 KC3 资料包为两个独立来源组保存、检查和更新；一次检查覆盖功能所需的两个来源组。表中的 `en-us.json` 保留为旧格式英文快照，实际英文、韩文正文与舰名使用下述 `kc3-bundle.json`，无需单独的韩文资源文件。

## 简体中文文本快照

- 文件：`zh-cn.json`
- 直接数据来源：kcwiki 字幕 API，https://acc.kcwiki.cn/subtitles/zh-cn
- 版本接口：https://acc.kcwiki.cn/subtitles/version
- 备用 API：https://api.kcwiki.moe/subtitles/zh-cn
- 下载日期：2026-10-18（Asia/Tokyo）
- 数据版本：`2026101805`
- 舰娘条目数：860；字幕条目数：33,709
- 字节数：5,551,642（UTF-8，无 BOM）
- SHA-256：`75fcdf604acd3cfb4e4a4954c504880baf4272fc040b0a20f7da4504395fc092`
- 作者和贡献者：kcwiki 舰娘百科及各舰娘语音翻译页面的编辑、翻译贡献者。
- 署名入口：https://zh.kcwiki.cn/ ，各舰娘页面及其历史记录可以追溯具体贡献者。
- 文本修改说明：此快照原样保存 API 返回的文本和 JSON，没有改写翻译内容。应用运行期间只将其映射为舰娘编号与语音编号的查找表。

kcwiki 中文站页脚标示的内容许可为 **知识共享署名—非商业性使用—相同方式共享 3.0（CC BY-NC-SA 3.0）**：
https://creativecommons.org/licenses/by-nc-sa/3.0/

版权和编辑条款入口：
https://zh.kcwiki.cn/wiki/舰娘百科:条款

字幕译文及其衍生版本应保留来源和署名、注明修改，并遵守非商业性使用及相同方式共享的许可条件。该内容许可不改变应用自身代码的许可，也不授予游戏原始台词、角色或语音资源的额外权利。

## 繁體中文与日文文本快照

- 繁中全量接口：[acc.kcwiki.cn/subtitles/zh-tw](https://acc.kcwiki.cn/subtitles/zh-tw)
- 日文全量接口：[acc.kcwiki.cn/subtitles/jp](https://acc.kcwiki.cn/subtitles/jp)
- 版本接口：[acc.kcwiki.cn/subtitles/version](https://acc.kcwiki.cn/subtitles/version)
- 备用 API 域名：`api.kcwiki.moe`，路径与主源相同。
- `zh-tw.json` SHA-256：`80793a35bac0a6a3f9f90e58c3a32f4d664ec65a62f5213bc18cca61b5303bb3`
- `ja-jp.json` SHA-256：`e52c6960027cafc939daeedaea663ec1f89f89d7d2fdf5e8775ee7171fcfa023`

这两个文件原样保存 kcwiki API 返回的文本和 JSON。来源、编辑贡献者、署名入口与上文简中快照相同，遵守 kcwiki 内容许可；原始游戏台词及角色相关权利仍归原权利人。繁中来自上游繁中端点，应用没有执行简繁转换。日文来自台词端点，未使用插件界面 `i18n/` 文案作为语音字幕。

kcwiki 的全量响应含有自己的 `version`。程序先检查公共版本接口，再请求简中、繁中和日文的全量资料，最终以正文中的版本为准；旧版本和无效响应不会覆盖本地资料。

## English：KC3 改台词快照

- 上游项目：[KC3Kai/kc3-translations](https://github.com/KC3Kai/kc3-translations)
- 真实台词文件：`data/en/quotes.json`，不是 `terms.json` 等界面翻译文件。
- 固定源提交：[`dfa489f91a2a15120037d174e76771330d4c3582`](https://github.com/KC3Kai/kc3-translations/commit/dfa489f91a2a15120037d174e76771330d4c3582)
- 固定原始数据：[data/en/quotes.json](https://raw.githubusercontent.com/KC3Kai/kc3-translations/dfa489f91a2a15120037d174e76771330d4c3582/data/en/quotes.json)
- 该文件最近修改时间：`2026-08-04T12:43:56Z`；本地版本号去除分隔符后为 `20260804124356`。
- 原始文件：2,335,628 字节；SHA-256：`4da4ac039218ae1eac0572c96df0e349567afcc9a2eb5a6a549b3ad1cfaf3f86`
- 规范化快照 `en-us.json` SHA-256：`96b5fdcfae54c1a045f1fe93587ad467884233c4fbe9745377ff8bdf9d4ecc68`
- 作者和贡献者：KC3 改及 [kc3-translations 贡献者](https://github.com/KC3Kai/kc3-translations/graphs/contributors)。
- 上游仓库许可：[MIT License](https://github.com/KC3Kai/kc3-translations/blob/master/LICENSE)，`Copyright (c) 2015-2021 KC3改`。许可全文随包保存在 `KC3_TRANSLATIONS_LICENSE.txt`。

格式转换参照上游 [tools/convert-quotes.py](https://github.com/KC3Kai/kc3-translations/blob/master/tools/convert-quotes.py) 的描述名与语音编号对应表。应用仅转换基础 `Intro`、`Poke(1)` 等 1–53 号标签及直接使用数字的语音编号。分段台词按开始时间排序后用换行连接；`<br>` 转为换行，移除其余 HTML 标记并解码实体。英文译文没有重新翻译或改写。

含 `@` 的季节性标签、友军特殊标签、非舰娘分类及只含这些内容的空基础条目均不纳入此快照。当前未实现 KC3 的季节、音频文件大小等特征匹配，所以此快照不代表 KC3 全部字幕能力或全部游戏语音覆盖。不会把季节台词直接覆盖到同编号的基础台词。

英文不使用 kcwiki 的公共版本号；2026-10-18 实测 kcwiki `/subtitles/en` 返回错误，旧 poi 插件英文快照停留于 `2018082511`，因此未采用这两个来源更新英文。当前英文、韩文更新已统一到下面的 KC3 资料包，版本取仓库 HEAD 的提交时间，英韩正文与四语舰名、词缀均固定到该提交。

## KC3 统一资料包：英韩正文、四语舰名、装备名与类别

- 文件：`kc3-bundle.json`，schema 3，UTF-8 无 BOM，3,305,783 字节；获取日期为 2026-10-19（Asia/Tokyo）。
- 仓库提交：[`6fed2aac44a1ca95f2892bb1af93a6bc0e60b667`](https://github.com/KC3Kai/kc3-translations/commit/6fed2aac44a1ca95f2892bb1af93a6bc0e60b667)。
- 提交时间：`2026-10-17T02:31:18Z`；资料包版本：`20261017023118`。
- 资料包 SHA-256：`3e87fae932a50b8a221ed6d4af85ab848225dc9ce0f26c4a4a7985340f3befe3`。
- 英文正文：752 个舰娘条目、16,222 条基础／数字语音；转换规则和季节语音限制与上节相同。正文文件在此仓库提交中未变，其最近修改日期仍为 `2026-08-04T12:43:56Z`；资料包版本表示整组来源提交时间。
- 韩文正文：818 个舰娘条目、17,851 条基础／数字语音；使用与英文相同的基础标签、分段顺序及 HTML 清理转换，保留上游韩文社区译文，无机器翻译，也不以英文补齐缺失台词。与英文相同，含 `@` 的季节和友军特殊标签未纳入基础字幕。
- 舰名词典：简中 630、繁中 728、英文 631、韩文 726 个 JSON 键；包含上游自身的分类键，数量不等同于游戏舰娘数量。词典和词缀均来自社区译文，未执行机器翻译或简繁转换；日文直接保留游戏主数据 `api_name`。
- 原始来源和校验值如下，所有路径均位于上述同一提交：

| 上游路径 | UTF-8 字节数 | 原始文件 SHA-256 |
| --- | ---: | --- |
| `data/en/quotes.json` | 2,335,628 | `4da4ac039218ae1eac0572c96df0e349567afcc9a2eb5a6a549b3ad1cfaf3f86` |
| `data/scn/ships.json` | 16,960 | `847c0bd1eab566c9f829dc7f548fd34b8e76f4f794d312852e881fa521e975f7` |
| `data/scn/ship_affix.json` | 4,317 | `033a7ae42ab1bd414e410033cd3fcf0a5c24ce89d78a3d4a376dddb44fbe9bc4` |
| `data/tcn/ships.json` | 28,139 | `6d3a89848fc07385a9d3b29a2c1c55323403fad211121db28597803485adf929` |
| `data/tcn/ship_affix.json` | 4,502 | `030867f20c5ac7fc93c0e18f050a37fb30efff2c0c093a39c0fbfb1eefd0f769` |
| `data/en/ships.json` | 18,579 | `7ca35dbd86a9d44193d758adfd9ec9261001ecf5215de04df84a26e14f3876ab` |
| `data/en/ship_affix.json` | 4,655 | `48067bf65be5621806dda2d3f2369b3642f1c194c05442232fc5fdd4f5eb3344` |
| `data/kr/quotes.json` | 2,603,567 | `7351ede216f320afa7f8cb7fe75c31db2a164b33de5cf4e038b17f3a728bfb8c` |
| `data/kr/ships.json` | 22,480 | `2445fa2247d45c3396865785851fed400e4a7fcd4ddd9449e3457fb0b43ad737` |
| `data/kr/ship_affix.json` | 4,257 | `b5cbfad858372ebdc23d619149b78256be72dfbfaaae13a8664e53d0e04488b2` |

这些数据与上述英文资料采用同一 [kc3-translations MIT 许可](https://github.com/KC3Kai/kc3-translations/blob/6fed2aac44a1ca95f2892bb1af93a6bc0e60b667/LICENSE)，作者与贡献者署名入口相同，完整许可见 `KC3_TRANSLATIONS_LICENSE.txt`。

舰名组合参照 KC3Kai [`Meta.js` 的 `shipName`／`shipNameAffix`](https://github.com/KC3Kai/KC3Kai/blob/db1e102da2315299d543cfc90003929dc377c111/src/library/modules/Meta.js#L559) 和 [`Translation.js` 的 `getJSONWithOptions`](https://github.com/KC3Kai/KC3Kai/blob/db1e102da2315299d543cfc90003929dc377c111/src/library/modules/Translation.js#L168)。先使用上游 `byId` 中与真实主数据编号对应的名称，区分宗谷及 Glorious 的不同形态；没有编号译名时，保留全文精确匹配优先、词缀原有空格、前缀的堆栈顺序，以及 `$`／`^` 移到另一端的标记规则。普通舰名例子为 `睦月改` → `Mutsuki Kai`、`金剛改二甲` → `Kongou Kai Ni A`。区别是本应用只有去除词缀后能找到基础译名才组合，否则完整回退游戏原名，避免混合两种语言。编号直接来自游戏主数据，不根据名称猜测；日文始终保留 `api_name`。

KC3Kai 的参考实现同样为 MIT，`Copyright (c) 2015-2026 dragonjet`，完整许可另附 `KC3KAI_LICENSE.txt`。没有引入 KC3 的界面翻译文件作为语音正文。

更新先查询 [kc3-translations 仓库 HEAD](https://api.github.com/repos/KC3Kai/kc3-translations/commits/master)。SHA 未变化时仅检查版本元数据；SHA 变化时从固定 SHA 的官方 `raw.githubusercontent.com` 地址下载全部 22 个文件，校验英韩正文、四语舰名、词缀、装备名和类型数组后才原子替换一个资料包。缺文件、格式异常、旧提交、GitHub 限流、超时或写入失败均保留旧资料包，不混用不同提交的数据。只允许 GitHub 官方 HTTPS、固定仓库和文件路径，禁止重定向改变主机／路径／SHA；限制元数据 128 KiB、整组正文 16 MiB、单次请求或分块等待 20 秒、整次下载 2 分钟。

旧 schema 1／2 缓存缺少韩文或装备、类型资料，即便提交 SHA 与内置包一致、甚至缓存日期更晚，也不再加载；程序自动回退到完整的 schema 3 内置包。完整资料随应用离线提供，同 SHA 检查亦不会绕过完整性要求，不依赖首次更新成功，也不删除其他来源的数据缓存。

### 应用界面实体译名

本次新增同一提交的 `data/{scn,tcn,en,kr}/{items,stype,equiptype}.json`，合计 12 个文件，和上表的 10 个文件组成一个不可拆分的来源组。装备名映射条目分别为简中 743、繁中 750、英文 748、韩文 748；包含分类、敌方装备或别名键，条目数不等于独立装备数量。`stype.json` 是按舰种 ID 索引的数组；`equiptype.json` 是对应 `api_type` 的 5 组数组，界面装备种类使用第 3 组（索引 2），其他组保留原始独立 ID 空间。上游简中第 5 组为空，保留此合法占位，不以其它语言补齐。

应用界面只在英文、韩文时使用这些资料转换舰名、装备名、舰种、装备种类；简中、繁中、日文保留各页面原有行为。日文实体名直接来自游戏主数据，不新增一份易失步的日本语译名表。原始数据、日志和游戏画面不改写；字幕仍按独立字幕语言选择。旧日志保存的简／繁中文名只在译名反查没有歧义时转为对应日文键，再查目标语言；缺译名或歧义回退原文。已知实体复合字段使用最长名称优先的一次替换，不把所有界面文案当作实体字典。

新增来源原始校验值如下，许可、固定提交与上表相同：

| 上游路径 | UTF-8 字节数 | 原始文件 SHA-256 |
| --- | ---: | --- |
| `data/en/equiptype.json` | 5,910 | `7841c2b3843db504f436961f5ac8a7c1d1dc352db29b7d2005e1af08fc31fd7e` |
| `data/en/items.json` | 48,238 | `e8a972da879fee44f4119503e42d25dff7bf9ad452b0feda883bb4d43336b7e5` |
| `data/en/stype.json` | 612 | `0740640231a8a6de9bcd9a366c96eb6e0d4376254e55a6784afe15e34752ee8b` |
| `data/kr/equiptype.json` | 5,786 | `535f50432c0f6a827624817f490f48a1a6bd6d87f26ef24b5b6eb1c122db7e7a` |
| `data/kr/items.json` | 43,982 | `2e4b44cb9119080b546c95a3db6ebfe6c466086be013994608ac7d2c70974d75` |
| `data/kr/stype.json` | 799 | `71f70f8f8d5ed8a3f1bce1636e66ebbcb113889fbe86f09e0b88b3ddef1cdd60` |
| `data/scn/equiptype.json` | 4,565 | `51b628b31fe531c4ab7a2a2c79d7607be34081e0309da696bf4487402c59679c` |
| `data/scn/items.json` | 41,429 | `5352828a3d1de2e8104014476e8a61e1b87e9ed0213e76d7a53ca1dcac4e88e1` |
| `data/scn/stype.json` | 612 | `0740640231a8a6de9bcd9a366c96eb6e0d4376254e55a6784afe15e34752ee8b` |
| `data/tcn/equiptype.json` | 5,956 | `2af5bb4647d37fe187030e7203ffe53cf42a4de97e1fbf27c94f6fcd1aa52b05` |
| `data/tcn/items.json` | 48,088 | `3369d649e75eb18a4a2b8724d6b3d3c749dd3b10cfbbc40fac0d4c1f53b5e96e` |
| `data/tcn/stype.json` | 672 | `dfeac18cfb30c095091e2427571000c110a6d763dfd2b721a6391c2bdf73d23a` |

## poi 字幕插件与文本许可的区分

参考项目：https://github.com/kcwikizh/poi-plugin-subtitle

poi-plugin-subtitle 的**程序代码**采用 MIT License，版权为 `Copyright (c) 2015 poi contributors`。本功能参考其数据格式与音频匹配流程，并直接从 kcwiki API 获取当前简中、繁中、日文快照；英文使用上述 KC3 改资料，未将 poi 插件包内旧版 JSON 作为当前数据。

插件代码的 MIT License **不应当被解释为将 kcwiki 翻译文本统一重新授权为 MIT**。上面的 kcwiki 内容许可应独立遵守。原插件 MIT 许可全文见 https://github.com/kcwikizh/poi-plugin-subtitle/blob/master/LICENSE 。

## KC3 改 MIT 许可全文

以下为上游 `LICENSE` 全文，另附同内容文件 `KC3_TRANSLATIONS_LICENSE.txt`：

```text
The MIT License (MIT)

Copyright (c) 2015-2021 KC3改

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
