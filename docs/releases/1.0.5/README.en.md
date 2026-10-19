# ヤハギ v1.0.5

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.5/README.md) ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.5/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.5/README.ja.md) ｜ English ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.5/README.ko.md)

[Return to this release / Download the app](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.5)

---

**This update primarily adds native Android notifications, game frame reloading, background game retention, OOI connections, new ship alerts and an unowned inventory, a land base summary, Battle prediction, and KCWiki data contributions, while further improving native direct connection, resource caching, and runtime stability.**

**Also, thank you to GitHub user @Kutinana for voluntarily creating an iOS port. However, that version is independently ported and built by a third party. I do not have an iOS device, so I cannot test it, and it may differ in version from the Android version I develop, contain unknown bugs, or lack features.**

## I. New features and enhancements

### 1. New native Android notification center

Added “Settings → Notifications” to manage expedition, repair dock, construction, Akashi anchorage repair, morale recovery, and sparkling reminders in one place.

* View notification permissions, exact alarm permissions, and notification channel status.
* Receive reminders on time, 30 seconds early, or 60 seconds early.
* Akashi anchorage repair supports “First repair after 20 minutes,” “All repairs complete,” and “Both stages.”
* The notification shade can display task progress, percentages, and live countdowns together.
* Obsolete reminders are automatically canceled after instant construction, instant repair, or fleet status changes.
* Reminders already handed over to Android can continue working after the app is cleared through ordinary background cleanup.

Also added a “Keep game in background” switch, enabled by default. When you move Yahagi to the background after entering the game, it uses a persistent notification to raise the survival priority of the game process and WebView, reducing the likelihood of the system reclaiming them.

This feature may increase battery use and can be turned off under “Settings → Screen and sound.”

### 2. Yahagi / OOI connection options

Added a game connection selector under “Settings → Network”:

* **Yahagi connection:** Uses the official DMM login entry point; recommended by default.
* **OOI connection (experimental):** Opens the `ooi.moe` login page, where users choose mode 1, 3, or 4 themselves.

This version adds KCSAPI capture and game display adaptation for OOI mode 1. After switching connections, Yahagi features such as fleets, quests, battles, logs, notifications, and resource caching remain available.

The OOI login page is provided by a third party. Yahagi **does not read, save, or automatically fill in accounts, passwords, cookies, or login tokens**. Availability and compatibility depend on the third-party service and the user's network environment.

### 3. Game refresh and native direct connection improvements

The toolbar refresh action now offers:

* **Refresh game page:** Reloads the entire page.
* **Reload game:** Reloads only the KanColle game frame. This is faster, but may cause cat errors or network errors.

Native direct connection mode now takes a snapshot for pop-ups, making problems such as pop-ups being covered or black overlay screens less likely when opening air power, line of sight, and other pop-ups.

Also improved:

* Recovery from the background and page initialization retries;
* Detection of DMM's new game entry point;
* Game display scaling and size restoration;
* Remnants of the top bar and clipping at the bottom;
* Scaling being reset during loading.

In-app screenshots, settings save messages, network messages, cache messages, and error messages have also been moved to the top capsule area to avoid obscuring the game display.

### 4. New ship alerts and unowned inventory

Inventory now has “Owned / Unowned” and “Ships / Equipment” switches to show the current account's collection, along with new ship locking reminders.

* Unowned ships are grouped by remodel chain, without counting different remodel forms separately.
* Filter by ship class or equipment type, and reset filters with one tap.
* Add ship families that do not need reminders to an exclusion list, saved separately for each account.
* Recognizes new ships obtained from drops, event rewards, quest rewards, and construction.
* When a new ship is obtained in battle, locking reminders are delivered after returning to port through an in-game message, a system notification, and vibration, avoiding interference with the results animation.
* Unowned equipment is determined from the current inventory and ships' equipment slots. It is for viewing only and does not trigger reminders.

“Unowned” here means that the current account does not own that ship family; it does not represent a historical first acquisition in the ship encyclopedia.

### 5. Land base summary on the home page

Added a land-based air squadron status card to the home page, showing:

* Action states such as sortie, air defense, rest, standby, and evacuation;
* Air power, proficiency ranges, and effective combat radius;
* Equipment, aircraft counts, and slot status for all 4 squadrons;
* Warnings for missing aircraft, relocation, yellow fatigue, and red fatigue;
* Current HP and damage status after land base air raids.

### 6. POI Battle prediction improvements

The POI prediction engine now fully replays battle phases from the start-of-battle state, reducing the propagation of incorrect states from an earlier phase into later calculations.

This update focuses on improvements to:

* Normal fleets, combined fleets, enemy combined fleets, and 7-ship striking forces;
* Phase ordering for day battles, night battles, aerial battles, land-based air squadrons, support, and opening phases;
* Separation of NPC friendly fleet and player fleet states;
* Multiple-hit attacks and damage control activation;
* Determining single-use consumption of Repair Teams and Repair Goddesses;
* Battle ranks, MVPs, and abnormal target detection.

When a phase is unknown or data is insufficient, the engine prioritizes marking results as “Unconfirmed” to avoid presenting seemingly certain but potentially incorrect results.

Full mode also adds pre-battle enemy portraits and **25% / 50% / 75%** damage markers on both sides' HP bars, making it easier to judge heavy damage, moderate damage, light damage, and healthy states.

### 7. Fleet status and heavy damage alert enhancements

* Tap “Minimum morale” in the home page fleet summary or fleet center to switch to a countdown until Cond 49. The display mode is saved automatically.
* Tap the air power indicator to view 3 values: “Minimum,” “Maximum,” and “Without proficiency bonuses.”
* Added opening anti-submarine warfare checks for several ship types, including Hyuuga Kai Ni, coastal defense ships, light carriers, and escort carriers.
* Heavy damage alerts now record risks during the battle results phase and issue an explicit warning after you choose to advance; they no longer give false alarms when retreating or returning to port.

### 8. Senka center and resource cache improvements

The senka center now lets you switch sortie statistics between “This month / Today,” and fixes missed boss-route records on some maps with multiple routes.

Also improved state transitions and projected senka calculations for daily settlement, month changes, and quarterly and yearly senka quests.

Resource cache changes:

* Fixed complete caches being incorrectly treated as expired after a long time without online validation.
* Renamed the previous “Expired” status to “Pending validation.”
* Files pending validation remain locally stored and are not automatically deleted.
* Integrity checks show separate counts for missing, damaged, and pending-validation files.

### 9. Frame rate, input, and interface adjustments

* App menus, lists, and page scrolling use the highest refresh rate supported by the current screen.
* The KanColle game itself continues to use independent 30 / 60 FPS controls.
* Auto mode runs at up to 60 FPS; low-power mode is fixed at 30 FPS.
* Removed the uncapped high-refresh-rate game mode. Existing settings are automatically migrated to “Auto.”
* Improved input stability on foldable devices, during window resizing, and when the keyboard appears.
* Removed the blue highlight caused by long-pressing the game display in native direct connection mode.

### 10. KCWiki data contributions

To support KCWiki's longstanding contributions to the community and players, Yahagi has officially become a **KCWiki data partner site**.

Added KCWiki data contributions under “Settings → Data.” In this version, it is enabled by default and can be turned off at any time.

When enabled, it only sends:

* Map routing;
* Quest prerequisites;
* Battles;
* Friendly fleets;
* Land-based air squadrons / land base air raids;
* Equipment improvement data.

It does not send:

* DMM login tokens;
* Cookies;
* Complete request headers;
* Login forms;
* Yahagi's local settings.

The settings page shows counts for queued, successfully uploaded, failed, and discarded submissions.

Turning it off stops the collection, packaging, and sending of KCWiki-specific data, without affecting the game or local helper features.

> **Please note: KCWiki's receiving server currently still uses unencrypted HTTP.**
> If you do not wish to participate in data contributions, you can turn it off under “Settings → Data.”

## II. Performance and stability improvements

* Notification countdowns and on-time reminders are now handled by Android, reducing background refreshes and extra wakeups.
* Background game retention and task progress share the same foreground service, reducing duplicate persistent notifications.
* KCWiki uploads use a separate queue, so server errors do not block game state updates or battle records.
* Parsing of large game data can automatically recover after a timeout, preventing subsequent events from remaining stuck for a long time.
* Native WebView now clears invalid tasks more thoroughly during page initialization, pop-up overlays, and foreground/background transitions.
* App UI and game frame rates are controlled independently, improving interface smoothness while managing heat and power consumption.

## III. Fixes

This version mainly fixes:

* Top bar remnants, bottom clipping, and scaling failures with DMM's new entry point.
* Occasional initialization timeouts, black screens, and incorrect pop-up layering when native direct connection resumes from the background.
* “Reload game” failing because of cross-origin restrictions.
* Expedition, repair dock, construction, anchorage repair, and morale reminders disappearing early, duplicating, or going missing.
* Old tasks remaining in the notification shade after instant construction or instant repair.
* Incorrect cache size totals and large numbers of resources incorrectly marked as expired.
* The logbook potentially recording the same construction again after restarting.
* Old quest snapshots restoring quests that had already been removed.
* Missing senka records for some boss nodes on maps with multiple routes.
* Incorrect damage positions for the 7th ship in a 7-ship striking force.
* NPC friendly fleet damage being incorrectly applied to the player fleet.
* Multiple-hit attacks triggering damage control repeatedly, and Repair Teams or Repair Goddesses being reused across nodes.
* Some incorrect targets, MVPs, and battle ranks in combined fleets, night battles, and special phases.
* Keyboard obstruction, compressed pages, and unstable input dialog layouts on foldable devices.
* The game page refreshing when toggling the KCWiki switch.
* Unowned ship grouping, land-based air squadron status, air power formulas, and various interface issues.

## IV. Known issues and usage suggestions

* OOI is an experimental third-party connection. Long-term availability and compatibility with every mode cannot be guaranteed. If problems occur, try switching back to the Yahagi connection for comparison first.
* Notification permissions, exact alarm permissions, and manufacturer power-saving policies may affect reminder delivery. After restarting the device or force-stopping the app, it is recommended to open Yahagi once to synchronize tasks.
* Keeping the game in the background increases battery use to some extent and cannot guarantee that WebView will never be reclaimed by the system.
* “Battle prediction” is a local helper calculation. Do not use it as a complete replacement for checking actual HP, evacuation, and damage control status.
* Android split screen, multiple windows, and picture-in-picture have not yet been fully adapted. Full screen is recommended.
* Google account login to DMM may still be subject to WebView security restrictions. Other available login methods are recommended.

Further development will continue to improve notification reliability, battle rules, OOI compatibility, native direct connection, local caching, and mobile performance based on testing feedback.

Thank you very much to all admirals for your continued testing, issue reports, feature suggestions, and support.

**Yahagi remains a personally maintained hobby project, and I will continue improving the mobile KanColle experience within my abilities.**
