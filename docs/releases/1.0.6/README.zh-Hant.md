# ヤハギ v1.0.6

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.md) ｜ 繁體中文 ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.ja.md) ｜ [English](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.en.md) ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.ko.md)

[返回此版本發布頁／下載安裝套件](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.6)

---

**本次更新主要新增裝備開發查詢、裝備與艦娘雙向適配查詢、出擊記錄戰鬥詳情、noro6 匯出、出擊記錄等功能，並進一步完善多語言與介面體驗。**
**另外，根據多數提督的回饋，高更新率模式已經過最佳化並重新加入。**

**也感謝 GitHub ID @Kutinana 同志自發製作了 iOS 移植版本，但該版本由第三方自行移植與製作。我手上沒有 iOS 裝置，因此無法測試該 iOS 版本，而且它與我開發的 Android 版本之間可能存在版本差異、未知 BUG 及功能缺失。**

---

## 一、新增與最佳化

### 1. 裝備開發查詢

在「建造」頁面新增裝備開發功能，支援：

* 輸入配方，查看可開發裝備及機率
* 選擇目標裝備，反查推薦配方與秘書艦

### 2. 裝備／艦娘雙向適配

新增：

* 裝備 → 可裝備艦娘查詢
* 艦娘 → 可裝備裝備查詢

### 3. 出擊記錄戰鬥詳情

航海日誌新增戰鬥詳情，可查看日戰、夜戰、航空戰、支援、基地航空隊等戰鬥過程及傷害資訊。

同時最佳化出擊記錄的載入方式，提升大量歷史記錄下的查詢效能。

### 4. 艦隊配置匯出

工具箱新增艦隊匯出功能，支援：

* DeckBuilder v4 JSON
* noro6 制空權模擬器

### 5. 未卜先知與戰鬥提醒

* 新增節點陣形記錄，可查看該節點上一次戰鬥使用的陣形
* 支援依損傷狀態設定閃屏與震動提醒
* 最佳化大破進擊判定

### 6. 介面與效能最佳化

* 重構資源趨勢頁面
* 主介面支援左右配置切換
* 支援恢復預設卡片排序
* 新增 4 種幀率模式：30 FPS／自動 60 FPS／持續 60 FPS／高更新率解鎖

**高更新率模式伴隨一定風險，請酌情使用。**

### 7. 多語言最佳化

重新審查簡體中文、繁體中文、日本語共 **895+ 詞條**，修正 100+ 處翻譯與顯示問題。

---

## 二、問題修正

* 修正航海日誌部分掉落記錄遺漏
* 修正夜戰節點制空狀態記錄異常
* 修正司令部退避狀態同步問題
* 修正聯合艦隊第二艦隊旗艦大破誤報警告
* 修正出擊記錄篩選與分頁異常
* 修正裝備開發工作台部分載入問題
* 修正資源趨勢取樣及卡頓問題
* 修正多處翻譯、排版與觸控問題

---

感謝各位提督一直以來的測試與回饋！

**Yahagi 會繼續努力，為大家帶來更順手的行動裝置艦 C 體驗。**
