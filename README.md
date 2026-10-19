<div align="center">
  <img src="assets/app_icon.png" width="128" alt="ヤハギ应用图标">

# ヤハギ（Yahagi KanColle Browser）

**让舰队信息与日常工具陪你一起出击。**

面向《舰队 Collection》玩家的移动端浏览器及信息辅助工具。

[下载应用](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/latest) · [版本更新](https://github.com/yamatosaki/yahagi-kancolle-browser/releases) · [问题反馈](https://github.com/yamatosaki/yahagi-kancolle-browser/issues)

简体中文 ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/README.ja.md) ｜ [English](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/README.en.md) ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/README.ko.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://www.android.com/)
[![iOS（第三方移植）](https://img.shields.io/badge/Platform-iOS-000000?logo=apple)](https://github.com/yamatosaki/yahagi-kancolle-browser/releases)
[![CI](https://github.com/yamatosaki/yahagi-kancolle-browser/actions/workflows/ci.yml/badge.svg)](https://github.com/yamatosaki/yahagi-kancolle-browser/actions/workflows/ci.yml)

</div>

## 软件介绍

ヤハギ将游戏画面与常用辅助信息放在一起。游玩时，可以同步查看舰队状态、任务进度、未卜先知战斗信息和航海记录；准备出击或安排日常时，也能使用改修规划、开发计算、远征检查、海域查询及经验计算等工具。

应用支持手机、平板和折叠屏，提供可调整的信息布局与适合大屏设备的 HD 布局，并支持简体中文、繁体中文、日语、英语和韩语界面。

游戏操作始终由玩家自行完成。ヤハギ根据游戏页面已经收到的数据整理辅助信息，不会代替玩家编成、补给、出击、开发、改修或领取任务。

## 下载与安装

前往 [GitHub Releases](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/latest) 获取已发布版本、安装包和对应的使用说明。

| 平台 | 获取方式与说明 |
| --- | --- |
| Android | 本项目主要维护的版本，在发布页下载 APK 安装。 |
| iOS | 发布页提供由 [Kutinana](https://github.com/Kutinana) 制作的第三方移植版 IPA。安装方式、支持功能和维护情况请以对应版本的发布说明为准。 |

更新 Android 版本时，请优先按照发布说明覆盖安装。卸载应用、清除应用数据或更换设备前，请先导出需要保留的航海日志与编成记录。

## 软件展示

### 手机、平板与折叠屏

<table>
  <tr>
    <td width="33%" align="center">
      <a href="docs/images/screenshots/phone.png"><img src="docs/images/screenshots/phone.png" alt="手机上的游戏与辅助信息布局"></a>
    </td>
    <td width="33%" align="center">
      <a href="docs/images/screenshots/tablet.png"><img src="docs/images/screenshots/tablet.png" alt="平板上的游戏与辅助信息布局"></a>
    </td>
    <td width="33%" align="center">
      <a href="docs/images/screenshots/foldable.png"><img src="docs/images/screenshots/foldable.png" alt="折叠屏上的游戏与辅助信息布局"></a>
    </td>
  </tr>
  <tr>
    <td align="center">手机</td>
    <td align="center">平板</td>
    <td align="center">折叠屏</td>
  </tr>
</table>

普通布局适用于手机等设备；HD 布局面向平板、展开后的折叠屏等较大窗口。可根据设备尺寸和使用习惯调整信息区宽度、模块顺序及显示项目。

### 游戏与辅助信息

<table>
  <tr>
    <td width="64%" rowspan="2" align="center" valign="middle">
      <a href="docs/images/screenshots/battle.png"><img src="docs/images/screenshots/battle.png" width="100%" alt="游戏画面与未卜先知战斗信息"></a>
      <br><strong>游戏与战斗辅助</strong>
    </td>
    <td width="36%" align="center">
      <a href="docs/images/screenshots/fleet.png"><img src="docs/images/screenshots/fleet.png" width="100%" alt="舰队与装备信息"></a>
      <br>舰队信息
    </td>
  </tr>
  <tr>
    <td width="36%" align="center">
      <a href="docs/images/screenshots/quests.png"><img src="docs/images/screenshots/quests.png" width="100%" alt="任务列表与任务信息"></a>
      <br>任务中心
    </td>
  </tr>
</table>

## 功能概览

| 功能 | 可以做什么 |
| --- | --- |
| 舰队与战斗辅助 | 查看舰队状态、制空与索敌信息，使用未卜先知查看战斗过程与结果预测，进行出击状态检查。 |
| 任务中心 | 查询任务说明、奖励与前后置关系，筛选任务，追踪部分任务的分项进度。 |
| 舰娘与装备 | 浏览持有与未持有图鉴，筛选、排序并查看装备装载情况，查询舰娘与装备的适装关系。 |
| 日常规划 | 查询改修安排与消耗，计算开发配方与概率，检查远征条件并估算收益。 |
| 战果与养成 | 查看战果记录与日历，规划战果目标，计算升级经验与出击次数，保存养成追踪。 |
| 编成与海域 | 保存编成和陆航记录，导出编成图与外部工具数据，查询海域路线、节点和敌舰资料。 |
| 日志与备份 | 查看六类航海记录与资源趋势，筛选战斗详情，导出、同步和恢复日志及编成记录。 |
| 移动端体验 | 自定义界面与资源栏，使用完成提醒、后台倒计时、游戏资源缓存及鼠标兼容设置。 |

### 舰队与未卜先知

- 查看舰娘等级、耐久、疲劳度、燃料、弹药、装备及舰队汇总信息。
- 查看制空、索敌等参考信息，以及远征、入渠、建造和泊地修理状态。
- 支持通常舰队与联合舰队的战斗信息，展示敌我耐久变化、战果等级及 MVP 预测。
- 提供出击前状态检查、大破提醒和战前敌舰信息展示。

未卜先知根据游戏页面已经收到的战斗数据整理信息，官方结算到达后会更新为正式结果。预测与状态提示供玩家参考，请结合游戏画面判断。

### 任务中心

- 浏览已接受任务与任务资料，按类型、周期等条件筛选和搜索。
- 查看任务说明、基础奖励、前置与后续任务，方便安排任务顺序。
- 追踪部分任务的分项进度，并提供完成提示。
- 支持任务资料更新。

部分任务进度依据本地观察与记录推算；尚未被应用观察到的进度可能不完整。

### 舰娘与装备

- 分类查看持有与未持有舰娘、装备，按条件筛选与排序。
- 查看装备的改修、熟练度和装载情况。
- 从装备查询可装备的舰娘，也可从舰娘查询可用装备，并区分通常槽与增设槽。

### 改修、开发与远征规划

- **改修规划：** 按星期、装备分类、关键词与收藏查询，查看二番舰条件、消耗及进化路线。
- **开发计算：** 按秘书舰与投入资源查询目标装备的开发概率，也可按目标装备反查配方。
- **远征检查：** 检查舰种、等级、装备、补给和士气等条件，估算大成功率、收益及完成时间。

### 战果与经验规划

- 查看本地战果信息、出击记录与战果日历。
- 结合 EO 与任务战果奖励规划目标，估算剩余战果及每日需求。
- 按海域、路线、胜利评价、旗舰和 MVP 等条件计算经验，估算升级所需出击次数。
- 保存舰娘养成目标，持续查看经验与等级进度。

战果与经验计算依据已记录的数据和设定条件进行估算。

### 编成记录与海域资料

- 保存当前舰队与陆航编成，按名称、海域等条件查找记录。
- 导出高清编成图，方便分享和整理攻略。
- 导出 DeckBuilder 数据，或主动打开制空权模拟器、Jervis 等外部工具继续计算。
- 查看海域路线图、节点类型、敌方编成、阵型、经验和制空参考；点击敌舰可查看详细资料。
- 海域、敌舰等资料支持在应用内独立检查更新。

保存的编成用于查阅与分享，游戏内的编成操作仍由玩家完成。海域与敌舰资料可能随游戏更新变化，请以游戏内实际情况为准。

### 航海日志、资源趋势与备份

- 保存出击、远征、建造、开发、除籍和资源六类记录。
- 按日期、海域和状态等条件筛选出击记录，查看节点与战斗详情。
- 查看各类资源的存量趋势、区间变化与历史记录。
- 支持为当前账号导出、分享和恢复航海日志与编成记录，也可选择文档文件夹进行后台同步与手动同步。

记录从应用实际观察到的数据开始积累。备份范围是航海日志与编成记录，不包含登录账号密码、登录 Cookie 或全部应用设置。

### 界面、提醒与游戏缓存

- 支持全屏、画面适配、信息区调整与首页模块编辑，可调整顺序、隐藏模块并恢复默认布局。
- 可自定义部分舰队简报与顶部资源栏项目。
- 提供远征、入渠、建造、泊地修理及疲劳相关提醒与倒计时展示。
- 提供游戏资源缓存与本地缓存下载，支持暂停、继续、完整性检查和清理。
- 支持画面与帧率选项、外接鼠标操作及鼠标滚轮兼容设置。

提醒与后台运行会受到系统权限和省电策略影响。资源缓存用于减少重复加载，游玩时仍需连接游戏服务器。

## 开始使用

1. 从发布页下载安装包，按照对应版本的说明安装并打开应用。
2. 选择连接方式，在游戏页面自行完成登录。需要时可配置系统网络、HTTP 代理或 SOCKS5 代理。
3. 进入母港，让应用收到舰队与账号数据后，再查看舰队、任务、仓库等辅助页面。
4. 按设备尺寸调整布局，并根据需要设置通知、缓存与记录备份。

应用提供两种运行模式：

- **游戏信息模式：** 读取游戏页面已经收到的接口响应，启用舰队、任务、战斗与日志等辅助功能。
- **纯浏览模式：** 关闭接口信息读取，仅在应用内浏览和操作游戏页面。

除 DMM 入口外，应用也提供实验性的 OOI 第三方连接入口。使用 OOI 时，登录凭据会提交给该第三方服务，请按应用内说明确认后再使用。

## 数据与隐私

辅助记录主要保存在设备本地，无需额外注册应用云端账号。不同功能的数据处理方式如下：

| 项目 | 数据处理方式 |
| --- | --- |
| 航海日志与编成记录 | 保存在本地；由用户选择导出、恢复或同步到指定文档文件夹。 |
| 匿名设备与使用统计 | 使用 TelemetryDeck，默认开启，可在设置中关闭。 |
| KCWiki 数据贡献 | 默认关闭；在版本和配置支持时，由用户自行选择是否启用。 |
| 诊断文件 | 由用户手动保存或通过系统分享面板发送，应用不会自动上传诊断文件。 |

用于辅助分析的游戏接口信息会清理 api_token、api_starttime 等敏感参数。记录备份不包含登录 Cookie；登录状态仍可能由系统 WebView 按其默认机制保存在设备上。

## 交流与反馈

欢迎分享使用体验、兼容性问题和功能建议。

- **QQ 群：1104904097**
- **联系邮箱：yamatosaki123[AT] gmail.com**
- **问题反馈：** [GitHub Issues](https://github.com/yamatosaki/yahagi-kancolle-browser/issues)

反馈问题时，请尽量说明应用版本、设备型号、系统版本、复现步骤及相关截图，方便定位。

## 开源与贡献

ヤハギ以开放源代码的方式开发，欢迎提交 Issue、Pull Request，参与功能改进、兼容性测试、文档与本地化。

从源码构建或运行测试，请参阅 [源码构建与验证](BUILDING.md)。参与开发前请阅读 [贡献指南](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/CONTRIBUTING.md) 和 [安全政策](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/SECURITY.md)。

项目源代码使用 [MIT License](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/LICENSE)。第三方字体、依赖与资产说明见 [THIRD_PARTY_NOTICES](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/THIRD_PARTY_NOTICES)。

## 免责声明

ヤハギ是社区开发的非官方工具，与《舰队 Collection》运营方、开发方、DMM 及相关权利方不存在隶属、授权或合作关系。

使用者应自行了解并遵守相关服务条款，并承担使用第三方工具可能产生的账号、网络与兼容性风险。游戏名称、商标及第三方素材的相关权利归各自权利人所有。

## 致谢

特别感谢 [POI 浏览器](https://github.com/poooi/poi) 项目及其开源社区，在数据组织、功能设计和社区协作方面为本项目提供的参考与启发。

感谢 [Kutinana](https://github.com/Kutinana) 制作和提供 iOS 第三方移植版本。

同时感谢 Flutter、WebView Flutter 及各依赖库的维护者，以及每一位参与测试、反馈问题和贡献代码的提督。

ヤハギ是独立开发的项目，项目观点与实现不代表上述项目或社区的官方立场。

## 赞助支持

[通过 GitHub Sponsors 支持 Yahagi](https://github.com/sponsors/yamatosaki)

也可以通过支付宝或微信支持项目，点击二维码可查看原图。

| 支付宝 | 微信支付 |
| :---: | :---: |
| <a href="docs/images/sponsors/alipay.jpg"><img src="docs/images/sponsors/alipay.jpg" width="220" alt="支付宝赞助收款码"></a> | <a href="docs/images/sponsors/wechat-pay.png"><img src="docs/images/sponsors/wechat-pay.png" width="220" alt="微信支付赞助收款码"></a> |

感谢您对 Yahagi 项目的支持！❤️

您的赞助是对我莫大的鼓励，也是我持续开发和改进这个开源项目的重要动力。

衷心感谢您的支持！
