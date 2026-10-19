import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_strings.dart';

void main() {
  test(
    'English resource counts use singular and plural and preserve package names',
    () {
      const strings = GameModsStrings(Locale('en'));
      expect(strings.supplied(1), '1 complete replacement resource provided');
      expect(strings.supplied(2), '2 complete replacement resources provided');
      expect(strings.resources(1), '1 resource');
      expect(strings.resources(2), '2 resources');
      expect(strings.source('原始包名.zip', 1), '原始包名.zip overrides 1 resource');
      expect(strings.source('原始包名.zip', 2), '原始包名.zip overrides 2 resources');
    },
  );
}
