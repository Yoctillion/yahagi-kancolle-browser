# ヤハギ v1.0.4

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.4/README.md) ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.4/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.4/README.ja.md) ｜ English ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.4/README.ko.md)

[Back to this release / Download the installer](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.4)

---

This update brings substantial upgrades to **Native Direct rendering, the built-in game resource cache, a complete Senka Center redesign, the Nozaki sparkling timer, multi-level sorting in the owned ship list, pre-sortie checks and map gauges, expedition rules, battle mechanics and Fleet Command Facility evacuation warnings, touch compatibility, and security protections**.

It also fixes several known issues and further optimizes **memory usage, device heat, stability during extended sessions, and compatibility across different Android devices**.

Based on actual usage feedback from the current test group, **“Native Direct + Full Cache” is currently one of the better-performing combinations overall**. Before this version's release, no crash reports had been received that could clearly be attributed to Native Direct mode itself, and most testers reported less device heat than before.

Please bear in mind that **Yahagi is fundamentally still a KanColle WebView browser client with integrated assistance features**. KanColle itself is an HTML5 game. When mobile devices continuously render animation, Canvas / WebGL, and audio and video resources through WebView for extended periods, they continue to use CPU, GPU, and memory resources, so **some device heat after a long play session is normal**. The aim of these optimizations is to reduce additional overhead as much as possible, rather than eliminate device heat entirely. Yahagi currently has no dedicated support for Android split-screen, multi-window, or picture-in-picture (PiP) modes. In these display modes, the app window's dimensions and aspect ratio may change frequently, and some interface layouts, WebView dimensions, and native view layers may not be recalculated in time. This may cause misplaced interface elements, display issues, or a black screen; in very rare cases, it may also cause an abnormal exit or crash. **For now, we recommend using Yahagi in full-screen mode whenever possible. Compatibility with these modes will be improved gradually as circumstances allow.**

**QQ test and feedback group: 1104904097**

---

# I. New and enhanced features

## 1. New “Native Direct” rendering mode

In addition to the existing **Standard, High Performance, and Compatibility modes**, this release adds a fourth rendering mode: **“Native Direct”** (Native Activity WebView).

This mode uses a **direct native WebView rendering approach** similar to GOTO's, further shortening the rendering path between Flutter and Android's native views. Reducing extra graphics compositing and intermediate-layer resource overhead can help reduce runtime memory pressure, device heat, and abnormal exits caused by resource pressure.

* **A more direct native rendering path**
  The game WebView is attached directly to a native Android Activity and displayed by the system's native View layer, bypassing Flutter Platform View embedding and multiple layers of graphics compositing. Compared with the existing Flutter WebView modes, this gives a simpler overall rendering path and can reduce the extra performance overhead introduced by intermediate layers.

* **Lower runtime memory pressure**
  By reducing the intermediate compositing layers between Flutter and Android's native views, this mode can generally reduce additional memory and graphics resource usage. It is particularly helpful for devices with limited memory, and may alleviate problems such as steadily increasing memory usage during long sessions, the system reclaiming background processes, and abnormal exits caused by resource pressure.

* **Good stability in testing so far**
  Following extended real-world use in the test group, no abnormal crash reports have yet been received that could clearly be attributed to this mode itself, and its overall stability has been good.
  Therefore, **Yahagi currently uses “Native Direct” as its default rendering mode**.

* **Relatively limited automatic screen sizing**
  Native Direct mode bypasses some of the Flutter layer's existing layout constraints and automatic screen-sizing logic. As a result, it may not determine the game display dimensions accurately on certain unusual devices, when the resolution changes, when a foldable device changes state, or when switching system windows. **In very rare cases, the game display may become abnormally enlarged**.

  In addition, because this mode displays content directly through a native Android Activity and WebView, **brief residual images or refresh delays may occasionally occur** when switching pages, changing orientation, or relaying out views. This is a normal phenomenon that may occur while native views and Surfaces are recomposited, and usually resolves quickly. **It does not affect game controls or game data**.

  If the display dimensions are incorrect, try the **“Reset display” button** or **reload the game page**. The app will briefly switch between landscape ↔ portrait to trigger the system's layout and dimension calculations again, which will usually restore the normal display.

  Later versions will continue to improve dimension detection and automatic screen sizing in native mode.

---

## 2. New built-in game resource cache system

This release adds Yahagi's own **local game resource cache system**, which works similarly to Shimakaze GO's local cache mode.

Frequently used static resources, including ship portraits, equipment, furniture, maps, and sound effects, can be saved directly on the device. When needed again, they are read locally first, reducing repeated downloads of the same resources from the official KanColle servers.

**Enabling the local cache system is strongly recommended.**

For long-term Yahagi users, the local cache can effectively reduce repeated data usage, while also reducing the extra processing, storage, and I/O pressure caused by WebView repeatedly downloading, parsing, and caching large amounts of static resources. This may help alleviate stuttering, increased resource usage, and abnormal exits during extended sessions.

In particular, **users who run KanColle for long periods, frequently switch game screens, or often use mobile data** are encouraged to choose **“Full Cache” mode** for more consistent resource loading and further reductions in data usage.

The game resources used by this feature still come directly from the **official KanColle resource servers**. **It does not rely on external proxies, HTTPS certificates, or third-party cache programs**. All cached data is managed locally on the device by Yahagi.

* **Less repeated data usage**
  Cached game resources can be read directly from local storage when used again, avoiding repeated downloads of the same files when opening screens such as the home port, fleet composition, resupply, and factory. This can significantly reduce repeated resource traffic on devices that frequently use mobile data.

* **Less performance overhead from repeated loading**
  Saving large amounts of infrequently changing static resources locally in advance reduces the extra overhead of repeated network requests, downloads, parsing, and caching during gameplay, making screen transitions and resource loading more consistent.

* **Less pressure on WebView's own cache**
  In normal mode, most game resources are handled by Android WebView's own caching mechanism. During extended use, its cache directory and related resource usage may gradually grow.

  With Yahagi's built-in cache enabled, a separate cache engine can centrally manage large amounts of static game resources. This reduces WebView's repeated caching of the same resources and the storage, I/O, and runtime pressure caused by continuous cache growth, lowering the likelihood of stuttering or abnormal exits after long sessions.

* **Two cache modes**

  * **No Local Cache**: Completely bypasses Yahagi's own cache system, retaining the original method of loading resources from the official servers over the network.
  * **Full Cache**: Uses the known game resource list to pre-download static resources such as ships, equipment, furniture, maps, and sound effects with one action. Resources that already exist and pass verification will not be downloaded again.

* **Smart incremental updates and network controls**
  Supports automatic checks for new or updated official resources. Missing resources can be filled in automatically over Wi-Fi. When using mobile data, the estimated download size is shown in advance, and downloading starts only after the user confirms. Downloads support **pause, resume, and resuming from the point of interruption**.

* **Cache maintenance and integrity checks**
  Check the current cache's **storage usage, resource count, and completeness** with one action. Missing or corrupted files are detected and repaired automatically, and Yahagi's local resource cache can be safely cleared at any time.

---

## 3. Complete Senka Center redesign

The Senka Center has been rebuilt into three separate pages: **“Senka information,” “Senka calendar,” and “Senka calculator.”** Responsive layouts have also been optimized for phones in portrait and landscape, tablets, and foldable devices.

* **Senka information and sortie statistics**

  * Combines server information, current senka, historical ranking trends, and the baseline for ranking changes.
  * Adds **“Sortie map senka statistics,”** automatically recording this month's sortie counts, boss encounters, S-rank victories, and A-rank victories for each map in real time, with options to favorite or hide commonly used maps.

* **Senka calendar**

  * A separate page displays a 6×7 monthly senka calendar, daily senka details, and the monthly cumulative total.
  * All senka values are shown to two decimal places.

* **Senka calculator**

  * Supports a custom **“Target senka,”** with real-time displays of projected senka progress and key figures such as selected EOs, selected quests, days remaining, base senka, senka needed per day, and today's remaining target.
  * Integrates EOs, quarterly senka quests, annual senka quests (AL Operation and Mobile Task Force Decisive Battle), and one-time senka quests (such as the “fireball cannon” quest).
  * Supports three states: **Unplanned / Planned / Completed (settled)**. It automatically synchronizes recognizable in-game clear states and calculates projected senka and the gap to the target in real time.

* **Safe base senka accumulation and manual correction**

  * Optimizes the base senka accumulation algorithm (admiral EXP gained × 7 / 10000), adding protection against out-of-order and duplicate snapshots to prevent abnormal EXP data from being counted twice.
  * Adds a **“Base senka accumulated this month”** correction option under “Settings → Data,” allowing manual value entry or a reset to zero with one action.
  * Corrections automatically adjust the related ranking-change baseline accordingly.
  * All senka-related times use **JST (Japan Standard Time)**.

---

## 4. Official launch of “Nozaki sparkling / timer”

Sparkling detection and timing are now officially integrated for the food supply ship **“Nozaki”** (unremodeled / Kai).

* **Smart fleet composition detection**
  Automatically detects Nozaki's position and status in Fleet 1 / Fleet 2 and applies the corresponding bonus for her form (unremodeled +2, Kai +3, with a 15-minute tick interval).

* **Real-time benefit estimates**
  Uses the fleet's current Cond values to calculate the time each ship needs to reach Cond 54, the estimated number of ticks, and fuel consumption in real time.

* **Status indicators and fleet switching**
  Displays states such as sparkling in progress, target reached, Nozaki herself, in repair dock, unable to sparkle, and conditions not yet met. Fleets can be switched quickly within the interface for viewing.

---

## 5. “Locked multi-level sorting” for the owned ship list

Sorting interactions in the owned ship list headers have been completely redesigned around **“tap for a temporary sort, long-press to lock a priority.”**

* **Quick single-column sorting**
  Tap any unlocked header to sort by that field in ascending / descending order.

* **Locked multi-level sorting**
  Long-press a header to lock that field as a sorting priority, showing its priority number and locked state. You can then add a second, third, or further sorting condition.

* **Long-press to unlock and restore with one action**
  Long-press a locked header to remove that condition; the remaining sorting priorities move up automatically. The filter bar gains a **restore sorting** button that preserves the current ship-type filter.

* Standardizes attribute column widths, text alignment, and horizontal scrolling behavior to improve overall list readability.

---

## 6. Enhanced pre-sortie checks and map gauges

The home page's pre-sortie check card now lets you switch between **“Ship checks”** and **“Map gauges.”**

* **Ship check mode**
  Checks each fleet for risks including missing resupply (insufficient fuel / ammunition), moderate / heavy damage, fatigue (red / orange faces), and repair ship anchorage repair status. Tap a warning to jump quickly to the relevant fleet.

* **Map gauge mode**
  Displays defeat counts and clear progress for regular and EO maps in real time (such as 1-6, 2-5, and 7-2), and supports displaying remaining event map gauge HP and percentages.
  You can also choose whether to show maps that have already been cleared.

---

## 7. Enhanced battle mechanic detection and Fleet Command Facility evacuation warnings

* **Fleet Command Facility (FCF) evacuation warnings**
  Improves detection of evacuation and escort towing information in battle results. Once an evacuation is confirmed, evacuated ships are automatically excluded from subsequent battle nodes, reducing false heavy-damage advance warnings caused by fleet-state desynchronization. The state resets automatically upon returning to port or starting a new sortie.

* **Battle mechanics and special attack checks**
  Adds or improves static condition detection and estimates for some activation probabilities for the following mechanics:

  * Opening anti-submarine warfare
  * Anti-air cut-ins
  * Anti-air rocket barrage
  * Carrier night attack cut-ins
  * Nelson Touch
  * Nagato / Mutsu special attacks
  * Colorado Touch
  * Yamato-class special attacks
  * Kongou-class / Haruna consort night battle assault
  * Queen Elizabeth-class special attacks
  * Richelieu-class special attacks
  * Submarine fleet special attacks, and more

---

## 8. Security protections and login compatibility adjustments

* **DMM PT top-up page blocking**
  Improves the DMM store and item purchase flow. You can view products, confirm purchases, and pay with the DMM PT balance already held in your account within the app.

* Blocks **“ポイントをチャージする”** and related redirects to external top-up pages to prevent accidentally opening a top-up page inside the app, while **preserving the normal purchase flow using existing DMM PT balances and the ability to return to the game**.

* **Previous login page restrictions removed**
  DMM accounts and other available login methods can now be used normally; login pages are no longer blocked across the board.

* **Google account login is not currently supported**
  Because Google places security restrictions on OAuth login environments, **Google account authentication cannot be completed directly within a standard Android WebView**. As a result, logging into DMM with a Google account still does not work normally in Yahagi.
  If your account also has another available DMM login method, please use that method instead.

---

## 9. Android touch compatibility improvements

* Optimizes PixiJS touch event mapping and InteractionManager compatibility handling in Android WebView.
* Fixes the mobile issue where **long-pressing the “Factory” button at the home port could not open Akashi's Improvement Arsenal**.
* Maintains normal responses to regular taps, dragging, and other in-game touch controls.

---

## 10. Improvements to improvement planning and Quest Center details

* **Improvement planning costs by stage**

  * Displays development material and improvement material costs separately for `0 → +6` and `+6 → MAX`.
  * Distinguishes costs for normal improvements and guaranteed-success improvements.
  * Shows fixed and additional costs at each star level.

* **Chinese translation fallback in the Quest Center**

  * Adds a local Simplified Chinese translation fallback mechanism.
  * Supplies Chinese descriptions for some limited-time and daily quests whose upstream translations are currently missing or incomplete.
  * Improves line break handling and formatting in quest details.

---

## 11. Frame rate setting adjustments and thermal management

* **Setting label changes**
  The Chinese power-saving setting is now consistently named **“低耗” (Low consumption)** and fixed at 30 FPS, to avoid confusion with Android's system-level battery saver mode.

* **Smart thermal management in Automatic mode**
  Automatic mode responds to Android's system power-saving state and the device's thermal state. When the device reaches a certain thermal state, it can proactively reduce the frame rate to 30 FPS to ease continued heating.

* **Automatic load reduction in the foreground / background**
  When the app enters the background, it temporarily reduces its runtime load and pauses some Dart performance sampling. User settings are restored automatically when it returns to the foreground.

* Further clarifies the difference between **60 FPS capped mode** and **high refresh rate display mode**.

---

## 12. Enhanced top information bar and diagnostic logs

* The top information bar supports custom displays for more resources and items, with improved shortcuts linking to features such as anchorage repair and the Nozaki timer.
* Diagnostic log additions include:

  * Previous process exit reason (PreviousExitReason)
  * Device runtime snapshot (DeviceSnapshot)
  * Standardized export filenames
  * Local storage path selection, and more

---

# II. Performance improvements

1. **Native Direct rendering optimizations**
   Attaching the Android native WebView directly reduces graphics compositing and resource overhead in the Flutter Platform View intermediate layer, lowering memory pressure and improving stability during extended use.

2. **Fast loading of local static resources**
   The built-in cache engine directly reads matching local images, audio, and other static resources, reducing repeated network requests and improving resource loading efficiency on screens such as the home port and fleet composition.

3. **Background data processing and state merging**
   Adds serial processing and idempotency checks for sortie events, senka statistics, and battle data, reducing repeated calculations and unnecessary interface refreshes caused by out-of-order or duplicate data.

4. **Thermal management and background load reduction**
   Dynamically adjusts some runtime workloads and frame rates based on device thermal state and whether the app is in the foreground or background, reducing heat and battery use during extended sessions.

---

# III. Bug fixes

This update fixes or improves the following issues:

1. Fixes possible stretching or black borders in the game display when unfolding / folding foldable devices.
2. Fixes abnormal native WebGL Surface rendering and display reset issues under certain conditions on some Android devices.
3. Fixes an issue that prevented dragging ships to reorder them on the fleet composition screen when sidebar auto-hide mode was enabled.
4. Fixes construction records in the Logbook occasionally failing to synchronize in time or going missing, and improves the reliability of log database writes.
5. Fixes inaccurate checks for some expedition great success conditions and incorrect great success rate displays.
6. Fixes possible double-counting of base senka with certain out-of-order EXP snapshots.
7. Fixes formatting problems caused by some `<br>` line break tags not being parsed correctly in quest detail text.
8. Fixes occasional native WebView layer occlusion when switching between the sidebar and full-screen pages.
9. Fixes text truncation, overflow, and layout issues in multiple UI elements at different resolutions and screen aspect ratios.
10. Fixes several known errors, further improving overall stability and compatibility across device models.
11. Improves the expedition evaluator, aligning it with Poi's expedition rules and correcting some checks for ship types, levels, morale, equipment, stats, and great success conditions.

---

# IV. Known issues and future development plans

Compatibility reports received so far remain concentrated mainly on **some Huawei-family and Honor devices**, with relatively few related reports from other brands.

Yahagi is developed and adapted primarily using the **standard development interfaces of Android, Flutter, and Android WebView**. Different phone manufacturers may customize the underlying system, WebView, window management, graphics rendering, and system components to varying degrees. As a result, compatibility issues on some devices may be strongly tied to a particular model or system version and may be difficult to reproduce reliably on other devices.

The new **“Native Direct” rendering mode** and **built-in game resource cache** are also significant adjustments aimed at memory pressure, graphics compositing overhead, repeated resource loading, and compatibility issues on some devices during extended mobile use.

If you encounter **crashes, display issues, incorrect feature detection, or other compatibility problems**, please report them through the test group and, where possible, export Yahagi's diagnostic logs at the same time. Complete logs can greatly improve the efficiency of locating and reproducing problems.

## Future development directions

Development will continue to focus mainly on the following areas:

* Continue optimizing controls and interaction when playing KanColle on mobile devices
* Improve compatibility across devices, Android versions, and WebView environments
* Continue improving client memory usage, device heat, and power consumption
* Refine existing assistance features and gradually add more practical tools
* Continue improving detection accuracy for KanColle mechanics, expeditions, and battle conditions
* Continue refining Native Direct rendering and the local cache system based on test feedback

Many thanks to all admirals for your continued **testing, issue reports, feature suggestions, and support**.

Yahagi remains a personally maintained hobby project. Many of its features have been refined little by little through your real-world usage feedback. I will continue to improve the user experience as much as I can within my abilities.
