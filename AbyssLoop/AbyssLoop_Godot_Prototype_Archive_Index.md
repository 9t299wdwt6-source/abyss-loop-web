# Обновление архива Abyss Loop — Stage 87

Текущая локальная итерация улучшает читаемость ландшафта: четыре детерминированные визуальные области, клеточная фактура и направленная подсветка придорожной зоны. Игровые правила, ID и сохранения не изменены. Stage87 regression включает 9 source guards и 5 reference-grid сценариев. Godot runtime и свежий Web export Stage87 не подтверждены.

---

# Abyss Loop — индекс сборок

**Последняя локальная итерация разработки:** Stage 87 — визуальная читаемость биомов и придорожных клеток. Проект `0.61.0`; source/numerical regression добавлен; Godot runtime и свежий Web export Stage87 не подтверждены.

- **Stage 87 — визуальная карта биомов:** четыре косметические палитры, детерминированные фактуры и подсветка грани клетки, соприкасающейся с дорогой. Игровые правила размещения не менялись. Подробнее: `STAGE87_BIOME_TERRAIN_VISUAL_BUILD_REPORT_RU.md`.

- **Stage 86 — процедурные дорожные контуры:** четыре семейства получили детерминированные контурные варианты, каждый seed создаёт замкнутую ортогональную дорогу ровно из 34 клеток; старые сохранения без `route_geometry_seed` остаются на прежнем прямоугольном контуре. Stage86 source/numerical regression: 17/17; 2 048 независимых seed/profile сценариев. Подробнее: `STAGE86_PROCEDURAL_ROUTE_CONTOURS_BUILD_REPORT_RU.md`.
- **Stage 85 — полная сетка ландшафта:** 19×14, 34 дорожных клетки, 232 клетки вне дороги на каждом контуре; `m:col:row` для новых ID, совместимость `col:row`, зона roadside и геометрические сектора. Подробнее: `STAGE85_FULL_LANDSCAPE_MAP_BUILD_REPORT_RU.md`.
- **Stage 84 — квадратная сетка карты:** карта 19×14, 34 дорожных квадрата, адаптивная ширина клетки и четыре ортогональных профиля; 80 legacy-позиций остаются действительными для совместимости. Подробнее: `STAGE84_SQUARE_GRID_LANDSCAPE_MAP_BUILD_REPORT_RU.md`.

- **Stage 79 — Loop Hero-style инвентарь и экипировка:** предметы появляются в начале 12-ячеечного рюкзака; заполнение вытесняет старейший предмет; drag-and-drop меняет очередь; правый клик быстро надевает предмет; экипировка сохраняется транзакционно при завершении забега. Подробнее: `STAGE79_LOOP_HERO_INVENTORY_FLOW_BUILD_REPORT_RU.md`.
- **Stage 77 — тактический прогноз тайлов:** обнаружение синергий в обратном порядке установки, прогноз локальных угроз и эффектов надетой ландшафтной экипировки, подсказки о тайнах до размещения; 18/18 целевых source guards. Подробнее: `STAGE77_TACTICAL_TILE_FORECAST_BUILD_REPORT_RU.md`.
- **Stage 78 — сравнение предметов и тайник добычи:** 12 ячеек рюкзака + 6 ячеек походного тайника; экипировка из любого контейнера без потери вытесненной вещи; расширенное сравнение статов; snapshot migration и валидация тайника. Подробнее: `STAGE78_EQUIPMENT_COMPARISON_AND_FIELD_CACHE_BUILD_REPORT_RU.md`.

- **Stage 76 — контекстная добыча и рука карт:** четыре контекстных аффикса повышают шанс трофея только для совпадающего биома; ручной обмен выбранной карты за 1 кристалл, не более одного раза за цикл; обмен атомарно сохраняется и откатывается при ошибке записи. Подробнее: `STAGE76_CONTEXTUAL_LOOT_AND_TILE_HAND_BUILD_REPORT_RU.md`.
- **Stage 75 — редкая добыча и дорожные карты:** «Обоз забытых исследователей», «Охотничья веха», ограниченные подготовки редкости/шанса выпадения, три синергии и две формации. Подробнее: `STAGE75_RARE_LOOT_AND_ROAD_CARDS_BUILD_REPORT_RU.md`.
- **Stage 74 — формации дорожных карт:** пять трёхузловых формаций и экипировка картографа. Подробнее: `STAGE74_ROAD_FORMATIONS_AND_CARTOGRAPHER_GEAR_BUILD_REPORT_RU.md`.
- **Stage 73 — исправление GDScript-разбора:** явные типы и исправленные ссылки тестов инвентаря. Это сборка, запуск которой пользователь подтвердил.
- **Stage 72 — контр-экипировка, телеграфы и предпросмотр карт:** защита от негативных статусов и тактические предупреждения. Подробнее: `STAGE72_TELEGRAPH_COUNTERPLAY_AND_TILE_FORECAST_BUILD_REPORT_RU.md`.
- **Stage 71 — тематические трофеи и синергии тайлов:** четыре вида трофеев, постоянный бестиарий, бонус родного ландшафта и четыре пары тайлов. Подробнее: `STAGE71_BIOME_TROPHIES_AND_TILE_RELATIONS_BUILD_REPORT_RU.md`.




## Stage 81 update — unified equipment drop probability and quality

- Unified item-drop chance is calculated by `LootSystem`: common enemy 18%, elite at least 45%, cache 35% (hard cap 85%), boss 100% with named reward handled separately. Echo charges and prepared drops use bounded bonuses and are consumed only after a successful eligible drop.
- Rarity on a successful drop uses normalized weighted distribution (70% common / 24% rare / 5.2% epic / 0.8% relic baseline). Equipment, preparation and source-quality bonuses have individual and total caps; the maximum total rarity bias is 25 percentage points.
- Elite items retain their rolled rarity and receive a separate bounded stat premium, instead of forcing every elite drop into a nonstandard rarity. UI and event logs distinguish item-drop chance from conditional rarity chance.
- Full static/regression suite: 107/107 PASS. Godot 4.7.2 runtime is not confirmed. The latest available web build is historical Stage68C and does not contain Stage81; new web export was not published.
- Evidence: `STAGE81_LOOT_DROP_PROBABILITY_AND_RARITY_BALANCE_BUILD_REPORT_RU.md`, `ROADMAP_STATUS_STAGE81_RU.md`, `LOOT_RARITY_BALANCE_RUNTIME_CHECKLIST_STAGE81_RU.md`, `tests/loot_rarity_balance_regression.py`.

## Stage 80 update — overflow item resource

- Current development handoff: Stage 80, `Пыль утраченных вещей` (Echo Dust), produced by backpack overflow and awarded in the atomic expedition settlement.
- The persistent resource is capped at 1,000,000 and is saved compatibly; old profiles default to zero. The last 1,000 settled run IDs act as a duplicate-reward ledger.
- The Mineral Recycler now consumes Echo Dust for upgrades. Source-level regression is `tests/stage80_ejected_loot_resource_regression.py`; Godot runtime is not confirmed until the exact build passes the 4.7.2 runtime gate.


## Stage 82 update — inventory identity and checkpoint normalization

- Run-item insertion now rejects IDs already present in the backpack or another equipment slot before any eviction or resource side effect. A duplicate no longer counts as a successful reward.
- Manual equip checks duplicate equipped IDs. Unequip permits moving its own slot's instance while refusing collisions with a different slot or backpack.
- Checkpoint restore normalizes all six supported equipment slots and removes duplicate ID copies from the backpack, preserving valid equipped gear first.
- Added Stage82 regression and runtime smoke assertions. Full static suite: 108/108 PASS; engine/runtime remains unconfirmed because Godot 4.7.2 is unavailable in this environment.
- Evidence: `STAGE82_INVENTORY_IDENTITY_AND_SETTLEMENT_AUDIT_BUILD_REPORT_RU.md`, `ROADMAP_STATUS_STAGE82_RU.md`, `INVENTORY_IDENTITY_RUNTIME_CHECKLIST_STAGE82_RU.md`, `tests/stage82_inventory_identity_regression.py`.


## Stage 86 update — seeded procedural road contours

- RouteView, placement validation, sector assignment and save validation query one seed-aware TileSystem contour generator.
- New runs persist `route_geometry_seed`; old snapshots that omit it resolve to seed zero and retain their fixed legacy contour.
- Four profile families vary through bounded outward detours without changing the 34-cell road budget, orthogonal closure or one-cell outer margin.
- Stage86 regression: 17/17 PASS; independent reference model: 2,048 seed/profile cases; full Python static suite: 112/112 PASS. Godot runtime and Web export remain unverified.
- Evidence: `STAGE86_PROCEDURAL_ROUTE_CONTOURS_BUILD_REPORT_RU.md`, `ROADMAP_STATUS_STAGE86_RU.md`, `PROCEDURAL_ROUTE_CONTOURS_RUNTIME_CHECKLIST_STAGE86_RU.md`, `tests/stage86_procedural_contour_regression.py`.

## Stage 85 update — full landscape grid

- All 232 non-road cells of the 19×14 grid are available. The 34-cell road is excluded for each of four supported contours.
- Existing `col:row` saves remain supported; modern IDs use `m:col:row` and snapshot `field_schema: 3`.
- Landscape sector assignment follows the active road contour; `roadside` and deep `landscape` zones are validated separately.
- Stage85 source/numerical regression is 17/17 PASS and full Python static suite is 111/111 PASS; Godot 4.7.2 runtime and current Web export are still unconfirmed.
- Evidence: `STAGE85_FULL_LANDSCAPE_MAP_BUILD_REPORT_RU.md`, `ROADMAP_STATUS_STAGE85_RU.md`, `FULL_LANDSCAPE_MAP_RUNTIME_CHECKLIST_STAGE85_RU.md`, `tests/stage85_full_landscape_regression.py`.

## Stage 84 update — square-grid landscape map

- The map display uses a 19×14 square-cell grid (266 visual cells). The 34-cell road is an orthogonal closed loop, exactly one grid cell wide; four presets change its footprint while retaining 34 road tiles.
- Landscape placement grew from 33 to 80 logical `col:row` slots without deleting prior IDs; all 80 are projected onto unique display cells away from the road. The 10×8 logical schema remains for save compatibility.
- Route drawing, hero movement, hit-testing and landscape projection share the same grid geometry. Regression tests cover six viewport sizes and all four contours.
- Static suite: 110/110 PASS. Runtime drawing/input and current Web export remain unconfirmed until Godot 4.7.2 is actually run.
- Evidence: `STAGE84_SQUARE_GRID_LANDSCAPE_MAP_BUILD_REPORT_RU.md`, `ROADMAP_STATUS_STAGE84_RU.md`, `SQUARE_GRID_MAP_RUNTIME_CHECKLIST_STAGE84_RU.md`, `tests/stage84_square_grid_map_regression.py`.

## Latest development stage

| Stage 90 | `ROADMAP_STATUS_STAGE90_RU.md` | `STAGE90_DISCOVERY_READABILITY_BUILD_REPORT_RU.md` | `DISCOVERY_READABILITY_RUNTIME_CHECKLIST_STAGE90_RU.md` |
