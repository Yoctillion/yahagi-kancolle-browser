/// Compatibility for the bundled merge that kept Japanese codes but copied
/// relation codes unchanged. Each mapping is verified by the same game id in:
/// https://github.com/kcwikizh/kcQuests/blob/a05f43e01ee559add52a14454381a9fb3b2e5a7d/dist/quests-scn.json
/// Only apply an alias while that id still has its verified Japanese code.
/// Missing source entries and the unverified `22606Am1` typo stay unresolved.
const questCatalogRelationAliases = <String, ({int gameId, String code})>{
  '2606Cm1': (gameId: 382, code: 'L2606C1'),
  '2606Bm1': (gameId: 1048, code: 'L2606B1'),
  '2605F3': (gameId: 1150, code: 'L2605F2'),
  '2605B2': (gameId: 1031, code: 'L2605B5'),
};
