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

const flatNodeIconSize = 16.0;

const flatHeaderHeight = 24.0;
const flatActionIconSize = 17.0;
const flatEditRowHeight = 32.0;

// 舰名行里的当前/最大血量，比无舰名行的 10 小一号，给舰名让宽度。
const flatNamedHpFontSize = 9.0;

// 航空战 / 夜战区块。
const flatAllyLossColor = Color(0xffe6a04a);
const flatEnemyLossColor = Color(0xffff8c78);
const flatSectionTitleColor = Color(0xff70c7bc);

/// Tinted ground that marks the jet strike stage among the air losses.
const flatJetGroundColor = Color(0xff2a3f52);
const flatAirPhaseFontSize = 9.5;
const flatAirHeadFontSize = 9.0;
