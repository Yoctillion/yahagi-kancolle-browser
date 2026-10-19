# ヤハギ v1.0.3

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.3/README.md) ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.3/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.3/README.ja.md) ｜ English ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.3/README.ko.md)

[Return to this release / Download the app](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.3)

---

This update focuses on improvements to **client diagnostics, improvement planning, senka management, the quest center, the logbook, game rendering, and performance**, while fixing a number of known issues and further improving stability and compatibility across devices.

**The v1.0.3 released at 00:00 on August 14 had a packaging error. The old 1.0.3 has been removed, and the “True v1.0.3” has now been uploaded again! Admirals who downloaded it between 00:00 and 03:00 on August 14, please download it again. Do not use the old 1.0.3!!!!**

Following suggestions from many admirals, a QQ group has been created with this update so that everyone can chat, share suggestions, and provide feedback.

**QQ group: 1104904097**

---

## I. New features and enhancements

### 1. Client diagnostic logs

Added client diagnostic logs to help investigate stuttering, crashes, data processing errors, and compatibility issues on some devices.

Diagnostic logs have the following characteristics:

* **Enabled by default; users can turn them off manually at any time**
* Logs are never uploaded automatically
* Only performance data, error summaries, and anonymous information about device operation are recorded
* Accounts, passwords, cookies, tokens, request bodies, response bodies, and game screenshots are not recorded
* Logs can be saved locally or exported through the system share sheet
* Diagnostic logs on the device can be cleared at any time
* Turning off diagnostic logging stops the associated performance sampling and diagnostic recording

If you encounter an issue while using the app, please consider exporting the diagnostic logs and sending them, along with a description of the problem, steps to reproduce it, and relevant screenshots, to:

**yamatosaki123[at]gmail.com**

This information can help me locate and investigate problems more accurately.

---

### 2. Improvement planning

Added improvement planning, which lets you check equipment available for improvement on a given date and brings together:

* Development materials and improvement materials required
* Equipment and resources required at different improvement stages
* Available improvement days and assistant ship requirements
* Equipment favorites and quick filters

Also added manual updates for improvement data.

Updated data takes effect immediately without restarting the app. If downloading or data validation fails, the app automatically continues using the existing local data, without affecting existing functionality.

---

### 3. Senka

Added a dedicated senka page for recording and planning monthly senka gains.

It mainly includes:

* Current senka information and historical records
* Senka planning for EO maps
* Senka quest selection and totals
* A monthly senka calendar

This feature only assists with senka planning and does not modify any game data.

Please note that you need to **manually open the senka page in the game** to obtain the latest information and refresh the client's local cache.

---

### 4. Quest center upgrade

The quest center now has an “All quests” catalog, instead of only showing quests currently accepted in the game.

Added the following features:

* Search by quest ID, name, or description
* Filter by quest type, cycle, and unlock status
* View quest completion conditions
* View relationships between prerequisite and follow-up quests

Also added quest data updates.

The app can check for and download new quest data, which takes effect immediately after updating without a restart.

---

### 5. Logbook enhancements

The logbook can now record and display more types of game actions, including:

* Sortie records
* Expedition records
* Construction records
* Development records
* Improvement and dismantling records
* Ship removal records
* Resource change records

Each type of log also has corresponding filters, making it easier to find records by time or action type.

The logbook is stored only locally on the current device and is never uploaded automatically.

---

### 6. Game rendering modes

Added three game rendering modes to choose from according to your device's performance and compatibility.

#### High performance mode

Uses **Texture Layer + WebGL** rendering and retains the toolbar background blur effect.

This mode preserves more of the interface's visual effects, but may cause stuttering, increased power consumption, or greater performance overhead on some devices.

#### Standard mode (recommended)

Uses **Hybrid Composition + WebGL** rendering to balance performance, stability, and compatibility.

This mode disables the toolbar background blur effect and is recommended for most devices.

#### Compatibility mode

Uses **Hybrid Composition + Canvas** rendering, prioritizing compatibility.

Suitable for devices that experience WebGL display issues, black screens, flickering, or unstable visuals, though game rendering performance may be lower.

The app automatically reloads the game page after switching rendering modes.

> **Avoid switching rendering modes during battle or other important actions.**

---

### 7. Game frame rate settings

The previous “High frame rate mode” has been replaced with three frame rate policies.

#### Auto

Prioritizes running at **60 FPS**.

If the app detects that the device is persistently unable to maintain stable performance, it automatically reduces the frame rate to **30 FPS**.

#### Stable 30 FPS

Uses a fixed target of **30 FPS**, prioritizing fewer dropped frames, less device heat, and lower battery use.

#### Prefer 60 FPS

Maintains **60 FPS** whenever possible without proactively lowering the frame rate, but may increase device heat, battery use, and processing load.

If the current Android WebView does not support the relevant frame rate controls, the app retains the game's original frame rate.

---

### 8. Battle information and alert enhancements

This update continues to improve battle information and alerts, including:

* Added land base air raid information
* Added predictions for the top 3 possible enemy fleet compositions
* Improved enemy fleet and combined fleet information displays
* Improved synchronization of battle phases, fleet status, and HP bars
* Added vibration alerts for moderate and heavy damage
* Strengthened the animated pulsing indicators for damaged ships
* Improved battle prediction execution efficiency

---

### 9. Anchorage repair enhancements

The anchorage repair page now lets you select the fleets actually participating in anchorage repair, with further improvements to repair status and timer displays.

Opening the page from an anchorage repair hint on the home page automatically takes you to the corresponding fleet, making it easier to check current repair progress.

---

### 10. Menu and settings interface improvements

The settings page has been reorganized by function, with further refinements to its structure.

Also added or improved the following:

* Freely customize what the top information bar displays
* Long-press the top information bar to enter edit mode
* Freely choose the items to display
* Drag to change the display order
* Restore defaults with one tap
* Drag to reorder the side menu
* Place the menu bar on the right side of the screen
* Apply recommended proportions for the game area and menu
* Improved some filter controls and page layouts
* Completed interface text in Simplified Chinese, Traditional Chinese, and Japanese

In addition to the existing basic resources, the top information bar now supports:

* Senka and ranking
* Anchorage repair timers
* Furniture boxes
* Mamiya
* Irako
* Medals
* First-class medals
* Action reports
* Various new-model armament materials
* Other commonly used items and resources

This makes it easier to check quantities of frequently used resources and items according to your needs.

---

## II. Performance improvements

### 1. Game rendering improvements

Further separated the refresh processes for the game WebView and client interface elements such as the toolbar, reducing the impact of toolbar and other interface updates on game rendering.

Main improvements:

* Dropped frames
* Unsmooth animations
* Input lag
* Interference between interface refreshes

---

### 2. Game data processing improvements

Larger game responses are now preferentially preprocessed in the background, reducing the impact of data parsing on main interface rendering.

Successive state updates generated within a short period are also combined to reduce unnecessary repeated refreshes and interface rebuilds.

---

### 3. Battle prediction performance improvements

The main battle prediction calculations now run in the background, reducing the impact of enhanced-mode calculations on the game display and client interface interactions.

---

### 4. Compatibility mode performance improvements

Improved display composition in Android compatibility mode, reducing the extra performance overhead experienced on some devices when using this mode.

---

## III. Fixes

This update fixes or improves the following:

* Fixed possible incorrect battle result predictions in “Battle prediction” for striking force and combined fleet formations, and improved recognition and calculation logic for special fleet formations
* Fixed possible errors or crashes when opening the quest center before the quest catalog had finished loading
* Fixed some quests failing to match correctly because different quest data sources used different ID formats
* Fixed incorrect prerequisite and follow-up quest relationships in some cases
* Fixed inconsistent fonts, body text colors, and ID labels in quest details
* Fixed data capture potentially not being enabled promptly when first opening the game page
* Fixed possible event ordering or state refresh errors when receiving game data continuously
* Fixed possible edge cases when automatic frame rate adjustment and game data capture ran together
* Fixed failure to fall back correctly after some rendering mode switches failed
* Fixed synchronization errors in some battle statuses, enemy fleets, and land base air raid information
* Improved network setting input validation and added hints for addresses, ports, protocols, and IPv6 formats
* Improved the layout, fonts, colors, and display effects of parts of the UI
* Fixed several known issues and further improved overall stability

---

## IV. Known issues and future development plans

Most issue reports received so far concern **Huawei-family devices (including Honor)**. Bugs appear relatively less frequently on devices from other brands.

This client is developed and adapted primarily according to the official Android and Flutter development documentation.

However, Huawei-family devices may include extensive customization of the underlying system, WebView, and some system components, creating differences from a standard Android environment. As a result, some features may encounter compatibility issues that are difficult to reproduce consistently or diagnose on these devices.

I am doing my best to optimize and adapt the app for these issues, but differences in device models, system versions, and underlying implementations mean that some problems may not be fully resolvable for now. Thank you for your understanding.

If you encounter a problem while using the app, the following information is welcome:

* Device model
* System version
* Steps leading to the problem
* Relevant screenshots
* Client diagnostic logs

All of this information can help with further investigation.

---

### About the “Nozaki timer”

Unfortunately, my own game account currently does not have Nozaki.

Although the feature's code is largely complete, I cannot fully test it yet because I lack an actual account environment with her.

I may therefore need to find a player who owns Nozaki to help test it. After confirming that the timing logic and actual operation work correctly, I can further refine and make this feature available.

---

### Future development directions

Future development will continue to focus on:

* Continuously improving the mobile gameplay experience
* Improving compatibility across devices and system versions
* Improving client performance and stability
* Refining existing helper features
* Gradually adding more useful features

Thank you very much for all your issue reports, suggestions, and support.

As this is a personal development project, I will continue improving the client as much as I can within my abilities, and hope to make playing and managing Kantai Collection on mobile more convenient.
