# ヤハギ v1.0.6

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.md) ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.ja.md) ｜ English ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.6/README.ko.md)

[Back to this release / Download installation files](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.6)

---

**This update mainly adds equipment development lookup, two-way compatibility lookup between equipment and ships, battle details for sortie records, noro6 export, and sortie records, while further improving localization and the interface experience.**
**Following feedback from many admirals, high refresh rate mode has also been optimized and added back.**

**Thank you as well to GitHub user @Kutinana for independently making an iOS port. However, this version was ported and produced by a third party. I do not own an iOS device, so I cannot test this iOS version. It may also differ in version from the Android version I develop, contain unknown bugs, or lack some features.**

---

## 1. New features and improvements

### 1. Equipment development lookup

Added equipment development functionality to the Construction page, supporting:

* Entering a recipe to see the equipment that can be developed and its probabilities
* Selecting target equipment to find recommended recipes and secretary ships

### 2. Two-way equipment / ship compatibility lookup

Added:

* Equipment → ships that can equip it
* Ship → equipment it can equip

### 3. Battle details for sortie records

Added battle details to the logbook, showing battle sequences and damage information for day battles, night battles, aerial battles, support, land-based air squadrons, and more.

Also improved how sortie records are loaded, making queries faster when there are large amounts of historical records.

### 4. Fleet configuration export

Added fleet export to the Toolbox, supporting:

* DeckBuilder v4 JSON
* The noro6 Air Superiority Simulator

### 5. Battle prediction and battle alerts

* Added formation records for each node, allowing you to check the formation used in the previous battle at that node
* Added screen flash and vibration alert settings based on damage status
* Improved the judgment for advancing with heavily damaged ships

### 6. Interface and performance improvements

* Rebuilt the resource trends page
* Added switching between left and right layouts on the main screen
* Added restoring the default card order
* Added four frame rate modes: 30 FPS / Automatic 60 FPS / Continuous 60 FPS / Unlocked high refresh rate

**High refresh rate mode carries some risk. Please use it at your discretion.**

### 7. Localization improvements

Reviewed **895+ entries** across Simplified Chinese, Traditional Chinese, and Japanese, correcting more than 100 translation and display issues.

---

## 2. Bug fixes

* Fixed some missing drop records in the logbook
* Fixed incorrect air superiority state records for night battle nodes
* Fixed synchronization of evacuation status from the fleet command facility
* Fixed false heavy damage warnings for the second fleet flagship in combined fleets
* Fixed sortie record filtering and pagination issues
* Fixed some loading issues in the equipment development workbench
* Fixed resource trend sampling and stuttering issues
* Fixed various translation, layout, and touch input issues

---

Thank you to all admirals for your continued testing and feedback!

**Yahagi will keep working to make KanColle more convenient to play on mobile devices.**
