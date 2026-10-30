import 'package:flutter/painting.dart';

// 卡片档的同类取值各组件不一，且两档外观要求逐像素不变，所以这里只收扁平侧。
const flatAccentColor = Color(0xffd4a85f);
const flatMutedColor = Color(0xff8197a5);
const flatDoneColor = Color(0xff4cc06a);
const flatDividerColor = Color(0xff1b3142);

const flatRowFontSize = 11.0;
const flatSmallFontSize = 10.5;
const flatRowSpacing = 2.0;
const flatSectionGap = 4.0;

/// Below this a side-by-side fleet column can no longer hold its title.
const flatSideBySideFleetsMinWidth = 240.0;
const flatHeaderHeight = 24.0;
const flatActionIconSize = 17.0;
const flatEditRowHeight = 32.0;
