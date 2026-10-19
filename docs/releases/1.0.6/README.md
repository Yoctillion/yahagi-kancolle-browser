# ヤハギ v1.0.6

简体中文 ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.ja.md) ｜ [English](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.en.md) ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.ko.md)

[返回此版本发布页／下载安装包](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.6)

---

**本次更新主要新增 **装备开发查询、装备与舰娘双向适配查询、出击记录战斗详情、noro6导出、出击记录** 等功能，并进一步完善多语言与界面体验。**
**并且受到多数提督反馈，高刷模式已经进行优化然后重新加入。**

**并且感谢 Github ID @Kutinana 同志自发性做了个IOS移植版本，但是该版本由第三方自行移植和制作。我手上也没有IOS设备，所以对于该IOS版本的无法做出测试，并且可能存在与我开发的安卓版本存在版本差异，未知BUG，和功能缺失情况。**

---

## 一、新增与优化

### 1. 装备开发查询

在「建造」页面新增装备开发功能，支持：

* 输入配方查看可开发装备及概率
* 选择目标装备反推推荐配方与秘书舰

### 2. 装备 / 舰娘双向适配

新增：

* 装备 → 可装备舰娘查询
* 舰娘 → 可装备装备查询

### 3. 出击记录战斗详情

航海日志新增战斗详情，可查看昼战、夜战、航空战、支援、基地航空队等战斗过程及伤害信息。

同时优化出击记录加载方式，提升大量历史记录下的查询性能。

### 4. 舰队配置导出

工具箱新增舰队导出功能，支持：

* DeckBuilder v4 JSON
* noro6 制空权模拟器

### 5. 未卜先知与战斗提醒

* 新增节点阵形记录，可以查看该节点上一次战斗的使用整形
* 支持按损伤状态设置闪屏与震动提醒
* 优化大破进击判定

### 6. 界面与性能优化

* 重构资源趋势页面
* 主界面支持左右布局切换
* 支持恢复默认卡片排序
* 新增 4 档帧率模式：30 FPS / 自动 60 FPS / 持续 60 FPS / 高刷解锁
**高刷模式伴随一定风险性，请酌情使用。**

### 7. 多语言优化

对简体中文、繁體中文、日本語共 **895+ 词条**进行重新审查，修正 100+ 处翻译与显示问题。

---

## 二、问题修复

* 修复航海日志部分掉落记录遗漏
* 修复夜战节点制空状态记录异常
* 修复司令部退避状态同步问题
* 修复联合舰队二队旗舰大破误报警告
* 修复出击记录筛选与分页异常
* 修复装备开发工作台部分加载问题
* 修复资源趋势采样及卡顿问题
* 修复多处翻译、排版与触控问题


---

感谢各位提督一直以来的测试与反馈！

**Yahagi 会继续努力，为大家带来更顺手的移动端舰 C 体验。**
