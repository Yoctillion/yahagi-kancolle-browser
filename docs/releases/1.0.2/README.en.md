# ヤハギ v1.0.2

[简体中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.2/README.md) ｜ [繁體中文](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.2/README.zh-Hant.md) ｜ [日本語](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.2/README.ja.md) ｜ English ｜ [한국어](https://github.com/yamatosaki/yahagi-kancolle-browser/blob/master/docs/releases/1.0.2/README.ko.md)

[Back to this release / Download installation files](https://github.com/yamatosaki/yahagi-kancolle-browser/releases/tag/1.0.2)

---

## 1. New features and enhancements

### 1. Inventory page

Added an Inventory page that brings together all ships and equipment actually owned by the current account.\
This page is for viewing data only and offers no actions that change the game's state.

### 2. Anchorage repair indicators

Added status indicators for Anchorage repair (Akashi repair) to the repair details page, making it easier to check the current anchorage repair status.

### 3. Additional settings

Added the following settings:

- Background sound
- Toolbar mode
- Keep screen on
- Other related display and usage settings

### 4. High frame rate mode (experimental)

Added a high frame rate mode that uses rAF (requestAnimationFrame) to increase the page rendering frame rate.
When enabled, it attempts to run at 60 FPS or the refresh rate supported by the device's screen, making some animations and interface elements smoother.
This feature is still experimental, and its actual effect may vary between devices.

### 5. Battle prediction calculation modes (experimental)

To address occasional incorrect S / A / B / C / D ratings in battle result predictions, this update adds two calculation modes:

- **Enhanced mode**\
  Uses more complete battle simulation and judgment rules for more accurate predictions, with a theoretical increase in processing overhead.\
  Actual testing so far has found no noticeable additional performance impact. **This is the recommended mode.**
- **Lightweight mode**\
  Simplifies parts of the battle calculation process to reduce processing overhead, but predictions may be less accurate than in Enhanced mode.

Battle prediction is still being improved. Special battle mechanics may produce results that differ from the game's final judgment.

### 6. More fleet information on the home page

The fleet section on the home page can now show more complete ship status information, including:

- Current HP
- Main stats
- Equipment
- Fuel
- Ammunition

This further reduces the need to open detail pages to check information.

### 7. Improved fleet page visuals

Added or adjusted the following visuals on the fleet page:

- HP bars around ship portraits
- Animated pulsing when ships are moderately or heavily damaged
- Animated sparkle in the portrait area when a ship's morale value is above 50
- Changed Average morale to Minimum morale, making it easier to check the fleet's lowest current morale

### 8. Stronger pre-sortie checks

Added checks for ship equipment status.
A warning appears before a sortie when a ship:

- Has no equipment
- Has unfilled equipment slots

This helps reduce accidental sorties with no equipment or incomplete equipment loadouts.

## 2. Fixes and improvements

- Fixed truncated enemy fleet names in Battle prediction. Titles now adapt automatically to the card's actual width.
- Fixed the Information panel width setting having no effect.
  - This setting applies only in landscape mode.
  - In portrait mode, the panel automatically fits the screen width without manual adjustment.
- Updated Battle prediction judgment rules to fix:
  - Sunk enemy ships incorrectly returning to full HP during the night battle phase
  - Inconsistencies between sunk status and HP bars
  - Incorrect node displays in some event maps
  - Other battle state synchronization issues
- Fixed air power calculations on the fleet page.
  - The previous formula omitted aircraft proficiency modifiers, causing inaccurate air power values in some situations.
  - Proficiency is now included in the calculation.
- Improved some UI layouts and visual presentation.
- Fixed several known bugs.
