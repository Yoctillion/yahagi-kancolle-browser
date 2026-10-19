# ヤハギ v1.0.7

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.7/README.md) ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.7/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.7/README.ja.md) ｜ English ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.7/README.ko.md)

[Back to this release / Download installation files](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.7)

---

This update is an **emergency special release**.

As **ACGP is currently no longer working normally**, many admirals have recently asked whether Yahagi can be used with **Shimakaze GO (岛风GO)**. Some admirals using Shimakaze GO have also encountered the **“Display region is restricted”** issue.

We have therefore urgently added a **workaround for the “Display region is restricted” issue**, and included some features that have already been developed and are ready for early release, bringing you **Yahagi v1.0.7**.

Please pay particular attention to the following:

**Shimakaze GO does not currently support Yahagi natively.**

This update only adds a compatibility workaround on Yahagi's side, allowing Shimakaze GO to work with Yahagi in some situations. It does not mean the two are fully integrated, and normal operation cannot be guaranteed in 100% of environments.

Several admirals have taken part in practical testing, and their feedback shows that **the new workaround already allows successful game login in Yahagi when used with Shimakaze GO**.

However, to **use all of Shimakaze GO's features fully** in Yahagi in the future, Shimakaze GO would still need to **add Yahagi to its supported application whitelist** to provide more complete and stable compatibility.

At this stage, Shimakaze GO functionality is therefore still **compatibility support / a temporary workaround**. Actual results may vary by device, network environment, and Shimakaze GO version.

---

## **Resolving “Display region is restricted” with Shimakaze GO / other proxies**

If you see **“Display region is restricted”** while using **Shimakaze GO**, first disable these options in Shimakaze GO:

* **Use remote cache (使用远端缓存)**
* **Full encyclopedia feature (全图鉴功能)**

These features may **conflict with Yahagi's local caching mechanism**, resulting in **“Display region is restricted”**.

If you have disabled Shimakaze GO's **Use remote cache** and **Full encyclopedia feature** but still see **“Display region is restricted”**, or encounter the same issue with another proxy tool:

Go to **Yahagi → Network settings**, enable **Bypass** at the very bottom of the page, and then refresh the game.

Based on testing feedback so far, enabling the workaround resolves **the vast majority of “Display region is restricted” cases**.

Admirals using Shimakaze GO are advised to first keep **remote cache and the full encyclopedia feature disabled** when using it with Yahagi. If “Display region is restricted” still appears, enable Bypass and try again to reduce cache conflicts and regional restriction issues.

---

In addition to this emergency compatibility work, v1.0.7 adds **fleet composition image generation, ship stat pop-up cards, account data isolation, a quest system upgrade, noro6 / DeckBuilder export improvements, and enhanced sidebar status displays**, along with adjustments to various interface and stability issues.

---

# **1. New features and core improvements**

## **1. New Fleet composition image feature**

Added **Composition image** to the Toolbox, allowing you to generate a high-resolution tall image of fleet and land-based air squadron configurations with one tap.

Main features:

* Freely select up to **4 fleets**, with support for seven-ship striking forces.
* Include **land-based air squadrons** from a selected map area at the same time.
* Display ship artwork, level, luck, equipment, improvement levels, proficiency, reinforcement expansion, aircraft counts, and more.
* Choose among three aircraft count displays: **Hidden / Current aircraft / Maximum aircraft**.
* Save a high-resolution PNG directly to the system photo gallery.

---

## **2. Ship stat pop-up cards in Battle prediction**

Tap a friendly or enemy ship in **Battle prediction** or the real-time battle panel to view detailed information.

The cards show:

* Current firepower, torpedo, anti-air, and armor stats.
* Current equipment and aircraft counts in each slot.
* Enemy ship stats calculated from both base values and equipment effects.
* elite / flagship status directly.
* Cards adjust automatically to their screen position and close automatically when switching pages or scrolling.

---

## **3. Complete data isolation between accounts**

Rebuilt the underlying data storage mechanism for users with multiple accounts.

The following data is now saved independently for each account:

* Fleet and inventory data
* Sortie and battle records
* Quest progress
* Construction / development records
* Remembered formations
* Expedition and improvement favorites
* New ship locking exclusion lists, and more

Common resources such as ship and equipment master data, map data, and the game cache remain shared to avoid taking up duplicate storage space.

Also improved account switching logic to reduce data mixing between accounts and incorrectly triggered notifications from a previous account.

---

## **4. Comprehensive quest system upgrade**

The quest system has undergone a major restructuring in this update.

Main changes:

* More detailed quest states:
  **Not accepted / In progress / Rewards ready / Estimated complete / Locked**
* Quest progress estimation logic is now more closely aligned with the **Poi quest plugin**.
* Added an **Accepted only** quick filter.
* Search supports multiple keywords across quest names, translations, rewards, notes, and IDs.
* When a quest is estimated to be complete, **“A quest has been completed”** appears immediately at the top.
* The left-side quest button shows the current number of quests awaiting reward collection.
* Improved full synchronization logic for the modern quest API, reducing quests missed when changing pages.

> ※ Quest completion is mainly estimated from Yahagi's local records. If you complete quests on another device, this device may not receive the full records, so the displayed results may differ somewhat from the actual state.

---

## **5. noro6 / DeckBuilder export improvements**

Rechecked the Air Superiority Simulator and DeckBuilder export features and improved their accuracy.

Main fixes and improvements:

* More complete export of ship modernization stat increases.
* Support for reinforcement expansion and special stat enhancement items.
* Accurate preservation of actual aircraft counts, including **slots with 0 aircraft**.
* Fixed equipment shifting into the wrong positions when empty slots were compacted.
* Improved export of land-based air squadron states, expanded bases, and squadron slots.
* Fixed some stats potentially becoming out of sync when changing equipment repeatedly.

Export results are now more closely aligned with noro6's original parsing logic.

---

## **6. Improved left-side menu displays**

Added more real-time status indicators to the left-side menu.

* **Quest button**
  Shows the current number of completed quests / quests awaiting reward collection.
  ※ This relies on Yahagi's local cached records. Actions on another device may cause the display to differ from the actual state.

* **Expedition button**
  Shows the number of expeditions currently in progress.

* **Repair button**
  Shows the number of ships currently under repair.

* **Construction button**
  Shows the number of ships whose construction is complete and which are waiting to be collected.

---

# **2. Detail improvements and bug fixes**

This update also improves several details:

* **Expedition notifications**
  When a fleet departs on another expedition, its previous natural morale recovery reminder is automatically removed to avoid unnecessary notifications.

* **Repair dock interface**
  Fixed line wrapping or truncation on the repair screen for ships with three-digit HP, such as Yamato Kai Ni and Musashi Kai Ni.

* **Land-based air squadron cards**
  Fixed text overflow on some narrow-screen and foldable devices.

* **Sortie preparation checks**
  Adjusted pre-sortie status checks and alert displays in the home page fleet summary.

* **Fonts and localization**
  Improved font fallback and added further localized displays for quests and some dialogs.

---

# **3. Known issues and usage advice**

* **Composition image generation** and **noro6 / DeckBuilder export** both rely on local home port data.
  Enter the game's home port and refresh the data once before using them.

* Saving composition images uses the system photo gallery / media storage functionality.
  Android 10 and later usually require no additional storage permission. On older Android versions, grant permission as prompted by the system.

* The **“Display region is restricted” workaround** includes protection against endless retries, allowing at most one automatic attempt per session.
  If your current network exit cannot reach the game service itself, you may remain on the restriction page. Check your proxy or network environment first in that case.

* Shimakaze GO remains **without native support for Yahagi**. If its APIs, caching mechanism, or access rules change in the future, compatibility may change as well.

---

Thank you to all admirals who provided feedback and assistance while testing this emergency release.

As v1.0.7 is a special version released ahead of schedule at short notice, some of its features were originally planned for later versions. Please continue to report any abnormalities, compatibility issues, or other bugs you encounter.
