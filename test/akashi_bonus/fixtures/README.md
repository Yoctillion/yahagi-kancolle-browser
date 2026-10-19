# Synthetic Akashi parser fixtures

These eight small HTML files are handcrafted parser examples for
`test/akashi_bonus/target_group_parser_test.dart`. Equipment numbers 300–305,
307 and 308 identify fictional examples, not a captured equipment dataset.
The test supplies its own minimal ship and equipment metadata in `testMaster()`.

The fixtures cover single bonuses, count tables, ship-specific conditions,
improvement levels, synergy, negative bonuses, unknown groups and absent bonus
sections. They are read as strings and parsed locally. Image URL attributes are
inert test input; the tests do not download images or make network requests.

Captured pages, game master snapshots and generated reference outputs remain
local-only and are excluded by `.gitignore`.
