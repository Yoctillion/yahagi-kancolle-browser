# ヤハギ v1.0.8

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.8/README.md) ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.8/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.8/README.ja.md) ｜ English ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.8/README.ko.md)

[Back to this release / Download installation files](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.8)

---

This is **the last major update of this year**. Yahagi's main features are now largely complete, and development will gradually shift toward **maintenance, optimization, and bug fixes**, so future releases are also expected to become less frequent.

Compared with v1.0.7, this update focuses on **map and enemy ship information lookup, ship experience planning, record backup and restore, complete game resource caching, and an HD layout optimized for larger devices**. Fleet information displays, game browsing controls, everyday status reminders, and other features also continue to improve.

This version supports **direct in-place upgrades from v1.0.7 and previously released v1.0.8 Beta versions**. There is no need to uninstall the old version before installation. Please do not uninstall it, as doing so may cause the loss of data stored in the app.

**Thank you as well to GitHub user @Kutinana for making an iOS 1.08 port. This version was independently ported and produced by a third party.**

## 1. New features and main improvements

### 1. Map lookup and enemy ship information

Added Map lookup to the Toolbox. Select a regular map to view its route map and information about each node.

- Check node types, enemy compositions, formations, experience, and air power data for a quick review before a sortie.
- Tap an enemy ship to view detailed stats, equipment, aircraft counts, and more.
- Map and enemy ship data can be checked for updates and updated independently within the app. When game data changes, you can obtain the latest data without waiting for a new Yahagi release.

### 2. Ship experience calculation and training tracking

Added Experience calculator to the Toolbox. After choosing a ship, its current level, and a target level, you can estimate the experience gained per run and the number of sorties needed to reach the target based on your planned sortie route.

- Add multiple battle nodes and set victory rating, flagship, and MVP conditions separately for each one.
- Use estimated experience values from map data directly, or enter experience manually for exercises or nodes with incomplete data.
- Add training goals to tracking so that you can keep checking a ship's leveling progress afterward.

### 3. Logbook and fleet composition record backup

Added Record backup and restore in Settings, mainly for saving **the current account's logbook and fleet composition records**.

- Select a document folder on your device to enable background synchronization, or synchronize manually at any time.
- Save backup files locally or share them through other apps.
- After changing devices, import a backup file to restore the relevant records.
- Before restoring, the app shows the scope of data involved and asks for confirmation again to help prevent mistakes.

### 4. HD layout and home page customization

Added an **HD layout** optimized for tablets, foldables, and other larger devices, displaying the game alongside fleet, quest, expedition, repair, and other information more clearly on large screens. **Do not use it on devices 8 inches or smaller.**

The home page now also supports custom editing. Freely reorder its modules, hide cards you do not currently need, and restore the default layout with one tap.

The fleet summary has additional display customization options too. Adjust which information items appear and how fleet names, ship type labels, and other content are displayed, adapting both compact and large screens to your preferences.

### 5. Complete game resource caching

In addition to the existing mechanism that caches resources as needed while playing, a Local cache mode now lets you download the game's basic resources to your device in advance.

- Continue playing normally while the cache downloads.
- Check the current cache status in Settings, and pause or resume downloads.
- Check cache integrity and clear the local cache.
- The existing temporary cache mode remains available for use as needed.

### 6. Resource bar and game control details

- Added **Furniture coins** to the top resource bar, with an option to convert furniture boxes into their coin value and include them in the preview total.
- Further customize the items and order shown in resource capsules.
- Added a shortcut to refresh the game frame, making it easier to reload the frame when the game display behaves abnormally.
- Improved the controls for exiting full-screen mode.

### 7. Mouse support

Yahagi now supports external mouse input, including **scrolling pages with the mouse wheel**, further improving operation on tablets, in desktop mode, and on larger devices.

If the wheel does not work correctly or pages cannot be scrolled after connecting a mouse, enable Mouse compatibility settings in **Settings** to improve compatibility with some devices or mice.

## 2. Fixes and experience improvements

- **Game display and caching:** Improved resource downloads, cache validation, and recovery from errors; improved display stability when zooming the game, resizing the window, or switching full-screen mode.
- **Quests and notifications:** Improved quest progress calculations and completion feedback, reducing delayed quest state updates; adjusted the timing and content of some notifications.
- **Fleets and repairs:** Improved refresh accuracy for fleet status, anchorage repair countdowns, repair dock status, and repair completion reminders.
- **Layout adaptation:** Improved composition image, experience calculator, fleet card, and Settings page layouts on narrow and large screens; fixed some text overflow, obscured content, and controls that were difficult to tap.
- **Other fixes:** Continued fixing some data display issues after switching accounts and battle information display issues, with further improvements to interface performance and runtime stability.

## 3. Usage notes

- Map experience, enemy compositions, and related data may change with game updates. Refer to the actual in-game situation when using lookup results. You can check for map data updates in Settings at any time.
- Record backup and restore currently focuses on **logbook and fleet composition records**; it is not a complete backup of the app's data.
- If you plan to change devices, uninstall the app, or clear its data, export a backup file in advance and confirm that it has been saved successfully.

Thank you to all admirals for your continued feedback and support!

As its main features become more complete, Yahagi will devote more effort to continuously improving stability, compatibility, and the user experience.
