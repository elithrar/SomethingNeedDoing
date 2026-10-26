# Extraction audit: XPIsland, FindAnUpgrade, AsTheCrowFlies

This is a source audit against the proposed [SND API](API.md), not a completed extraction or a promise of unchanged behavior from copying files. All three add-ons target Forever interface 16001. Their existing models, state ownership, and tests define the migration baseline.

## Audited revisions

| Add-on | Release | Exact source |
| --- | --- | --- |
| XPIsland | 0.6.7 | [`f2b9dcdc`](https://github.com/elithrar/XPIsland/tree/f2b9dcdc4da2d8c07815934746622035ad6329f6) |
| FindAnUpgrade (FAU) | 0.1.5 | [`89fcaeca`](https://github.com/elithrar/FindAnUpgrade/tree/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d) |
| AsTheCrowFlies (ATCF) | 0.1.7 | [`3d02ab66`](https://github.com/elithrar/AsTheCrowFlies/tree/3d02ab66b5ff836d9215f09674e2a6c371982224) |

The audit inspects runtime modules, manifests, repository contracts, and relevant tests. It does not measure native performance, rendering, taint, or live interaction. The previously completed release checks establish a baseline for these revisions; no new add-on behavior is changed by these documents.

**Classification:** Move = reusable mechanism after decoupling; Split = shared mechanism with add-on policy retained; Keep = bespoke domain implementation; New = proposed SND functionality with no complete existing donor.

## Recommendation

Use **FAU as the foundation for options construction and native-control lifecycle**, **ATCF for named-profile operations and transient editor ownership**, and **XPIsland plus FAU for font/measurement regression contracts**. No single add-on is already a general framework. All three still embed product state and manually positioned controls in their UI modules.

FAU's [options construction][f-options] publishes only a complete panel and reuses deterministic object slots after a failure. Its `FlushMenus` waits for open menus to close rather than regenerating beneath input. It also has read-only control handling and an adaptive scrolling body. Those make it the strongest options infrastructure donor.

ATCF's [settings module][a-settings] has a clearer profile boundary: validated load, switch, duplicate, copy, reset, limits, and future-schema protection. Its [options module][a-options] also handles picker ownership, caption truncation, and transient cleanup. These should inform an adapter and shared controls, rather than replacing other add-ons' storage layouts.

XPIsland's [font pipeline][x-ui] checks real native font readback, reconciles a shared fallback family, measures at effective scale, and avoids font work in animation. Its UI is tightly coupled to XP/PvP presentation, and its options panel scales a fixed body instead of using FAU/ATCF's scrolling layout; copying that shell would be a weaker foundation.

## Shared extraction map

| Concern | Existing evidence | Decision and SND destination | What stays with the add-on, and why |
| --- | --- | --- | --- |
| Registration/bootstrap | [XP Core][x-core] `Initialize` and event dispatcher; [FAU Core][f-core] `Initialize`; [ATCF Core][a-core] `Initialize` | **Split:** `NewAddon`, matching-load restoration, registration ownership, `OnReady`. | Supported-client decisions, character readiness, world-entry handling, and gameplay initialization. XP currently needs world entry and a readable GUID; FAU/ATCF initialize at add-on load. A common hook must not erase that difference. |
| Settings writes | XP `ApplyProfile`; FAU `Change`/`ChangeSearchDefault`/`Defaults`; ATCF `ApplyProfile`/`BindFilters` | **Split:** schema validation, read-only errors, atomic candidate publication, change notification. | Defaults, migrations, persistence references, and effects of a setting. FAU clears source caches for some changes; ATCF may replan; XP reconciles auto-collapse and stock-bar ownership. |
| Named profiles | [XP Model][x-model] `Database`/`SelectProfile`/`Duplicate`; [ATCF Settings][a-settings] `Profiles`/`SwitchProfile`/`CopyProfile`/`ResetProfile` | **Split:** common operations and profile page; use ATCF's validation as a reference. | Character assignment, storage scope, saved schema, limits, and whether named profiles exist at all. FAU has no current named-profile store. |
| Options shell | [FAU Options][f-options] `Frame`/`Text`/`Build`/`Create`/`Layout`; [ATCF Options][a-options] `Create`/`Layout`; [XP Options][x-options] `Create` | **Move:** lazy, retryable shell; scrolling body; stable pages; common controls. **New:** declarative section layout and bindings. | Which controls exist, explanatory text, semantic defaults, and feature-specific custom components. Existing absolute-coordinate constructors cannot be moved unchanged. |
| Tabs/page state | [FAU UI][f-ui] `Tab`, [SearchViews][f-views] `CreateViews`; XP `Page`; ATCF `Page` | **Move:** button chrome, selected underline, keyboard/focus and page lifetime. | FAU query/scroll state per search view and ATCF navigation back-stack. Settings page selection is not gameplay navigation. Replace boolean/magic page selectors with stable IDs only in the options layer. |
| Buttons, sections, inputs, scrollbars | FAU `Dialog`/`VerticalBar`, Options factories; ATCF `StyleButton`/`ControlArt`; XP local options factories | **Move:** `ui:Style` and internal control constructors; reuse native assets. | Action callbacks, enabled predicates, icons with domain meaning, and content-specific geometry. Prefer additive, idempotent style hooks; do not replace scripts on arbitrary frames. |
| Borders and colors | [FAU UI][f-ui] `Border`; [ATCF UI][a-ui] `Dialog`/`Section`/`RefreshButton` | **Move:** theme tokens and explicit border roles, including native NineSlice edge ownership. | FAU quest classification tints and accessibility-sensitive Blizzard texture edits (`Apply`/`Restore`). Those are domain integration, not ordinary SND chrome. |
| Font resolution | XP `Font`/`ApplyFont`/`WatchFonts`; FAU `Media`/`FontEntries`/`Font`/`WatchFonts`; ATCF `ResolveFont`/`Font` | **Move:** per-instance font service, saved preference preservation, SharedMedia callbacks, native fallback. | Which roles use bold/outline and which sizes are adjustable. Preserve existing defaults: XP/FAU use Game tooltip; ATCF requests Expressway. Do not pool mutable font state across apps. |
| Text measurement and captions | XP `Measure`/`FitText`/`AnchorText`; FAU counterparts and `FontCaption`; ATCF `Caption`/`WrappedHeight` | **Move:** measured sizing, scale-aware caches, UTF-8-safe truncation, caption tooltips. | Whether a particular label wraps, shrinks, or truncates. ATCF's route totals and XP's compact stat formatting are product decisions. |
| Menu refresh | FAU Options `FlushMenus`/`SyncMenus`; ATCF UI `SyncMenus`; XP Options `RefreshFonts` | **Move:** owned native menu adapters and deferred regeneration while open. | The menu's choices and effects. Use FAU's release-aware behavior instead of making unconditional `GenerateMenu` the shared default. |
| Color picker lifecycle | [XP Options][x-options] `CloseColor`/`Color`; [ATCF Options][a-options] same | **Move:** picker ownership, native hide-before-Okay/Cancel handling, cancellation on profile/page/hide, stale callback guards. **New:** staged preview semantics in API.md. | Color meaning and repaint behavior. The recent XP fix proves why closures must not write to an inactive profile; staging previews is a deliberate behavior contract to validate, not a verbatim extraction. |
| Screen bounds/popups | [FAU Adapter][f-adapter] `Rect`/`Cursor`, [Stack][f-stack] `Place`; ATCF UI `PlaceMenu`; XP Model `Placement` | **Split:** coordinate conversion, usable bounds, side selection, clamping and display invalidation into `layout`. | XP expanded-footprint reservation and upward expansion; FAU native-tooltip avoidance; ATCF docking/tucking. Clamping a window is shared; choosing where a product belongs is not. |
| Drag/resize ownership | [ATCF UI][a-gestures] `GestureGeometry`/`FinishMove`/`FinishResize`/`CancelStaleGestures`; XP UI drag scripts | **Split:** capture starting settings identity and geometry; cancel stale gestures before layout. | Dock position, result-height mode, snap thresholds, saved coordinate schema. Full docking is deferred until a second consumer needs the same behavior. |
| Events/post-hooks/scripts | Core event frames; XP Played hook; FAU source/tooltip hooks; ATCF `TakeTaxiNode` observer | **Move:** additive registration, subscriber lifetime, native hook deduplication and guards into `Scope`. | Event payload interpretation, hook targets, compatibility checks, and retry timing. Hooks do not expose return values or become removable just because SND has `Cancel()`. |
| Timers/coalescing | XP `DeferSample`/collapse timers/shared ticker; FAU Search `Changed`/`Wake` and Character `Mark`/`Flush`; ATCF `Search`/provider stepping | **Split:** keyed timers, guards, cancellation, no idle driver. | Authoritative clocks, XP reconciliation order, request budgets, dependency revisions, and the choice to resume a planned route. Generic debounce must not replace those algorithms. |
| Slash commands/messages | XP `/xpisland` and local `say`; FAU `Slash`/`Print`; ATCF `/atcf` dispatcher/status fields | **Split:** collision-aware registration and optional diagnostic output. | Command grammar, session reset, waypoint actions, and user-facing status. Do not reinterpret an existing error/status as a debug message. |
| Logging | XP/FAU chat messages; ATCF status/providerStatus; FAU observation recorder | **New:** bounded structured diagnostics. | FAU `Recorder`/`ObservationData` are explicit gameplay evidence collection with schema, consent and export rules. They must not become SND logs or automatic telemetry. |
| Value safety | XP `Model.Number`; FAU `Readable`/`Number` and adapter checks; ATCF `Ordinary`/`Number` | **Move:** finite/readable primitives after contract unification. | API-specific validators. FAU `Adapter.Call` returns one readable result, ATCF returns up to four, and some callers pack all results; these are not interchangeable functions despite the same name. |
| Copy dialog | [FAU Copy][f-copy] full owner/generation/focus/chord lifecycle | **Defer:** plausible optional text-copy component after another consumer needs it. | Value construction and native clipboard uncertainty. A key chord is not confirmation of an OS clipboard write. Keep it out of the initial core. |
| Search/list pooling | FAU Search cards and Stack icons; ATCF result rows | **Split later:** low-level reusable control allocation only after common needs emerge. | Ranking, filtering, reward layouts, route cards, virtualization policy, and cache identity. A shared list framework would exceed current evidence. |

## What remains bespoke in each add-on

### XPIsland

| Modules/behavior | Keep because |
| --- | --- |
| [Model.lua][x-model]: sessions, `Sample`, `Award`, `Hint`, `Reconcile`, rate/kill history, XP message parsing | These define authoritative XP accounting, attribution, recovery, and estimation. Neither SND settings nor logging should own these records. |
| [Played.lua][x-played] | Server-played-time synchronization has request ambiguity, level anchors, invalidation, and retry semantics specific to XPIsland. Only hook/timer plumbing is reusable. |
| [Progression.lua][x-progression] | Pet identity, honor, rank and renown are domain snapshots with client-specific interpretation. |
| Core sampling/loading/connectivity/level-up logic | Connected-session time, level-event ordering, rested traits, and choosing XP versus PvP mode are product behavior. |
| Core `Integration` | Stock tracking bar suppression coordinates combat, Edit Mode and Ellesmere ownership. SND must not automatically hide or restore Blizzard frames. |
| UI bar segments, highlights, animation, tooltips and auto-collapse interaction | These implement the island's distinctive display and timing. SND can style text and schedule owned work without becoming the XP renderer. |
| Settings adapter | Preserve `XPIslandDB` account profiles and per-character assignment, plus separate `XPIslandSession`/`XPIslandPlayed`. The latter two are not profile data. |

### FindAnUpgrade

| Modules/behavior | Keep because |
| --- | --- |
| Character.lua, QuestState.lua | Snapshot families, exact equipment identity, active/offered/completed quest evidence and event deduplication encode quest-domain correctness. |
| Catalog.lua, SearchModel.lua, SearchViews.lua, Search.lua query/state portions | Metadata freshness, shortlist visibility, native-versus-recorded rewards, request budgets and dependency-driven refresh cannot be inferred by a generic UI library. The recent Shortlist fix belongs here. |
| Providers.lua, Chains.lua, Questie.lua, Sources.lua | Availability proof, faction/starter restrictions, prerequisite graphs, provider identity and Questie interoperability are add-on semantics. |
| Ranking.lua, Rewards.lua | Reward usability, equipped comparisons, money/currency/reputation and ranking are feature logic. |
| NativeTooltip.lua, Hover.lua, Stack.lua inspection/transit portions | Blizzard/Questie tooltip coexistence, comparison identity, hover handoff and native content ownership remain specialized. Shared chrome or geometry does not make the complete tooltip lifecycle generic. |
| Shortlist.lua | Per-character IDs, capacity, legacy recovery and unknown-schema preservation are user data with their own policy. |
| Recorder.lua, ObservationData.lua, export formatting | Explicit evidence recording and structured exports are a distinct product feature, not framework diagnostics. |
| Launcher.lua | A minimap launcher could eventually be an optional component, but the initial core does not need another minimap abstraction. |
| data/, generated Lua catalogs, fau_tools/, receipts/classification/provenance | Source authority, deterministic imports and release tooling remain repository-owned. No database or upstream source data belongs in SND. |
| Settings adapter | Preserve account-wide FindAnUpgradeDB, rename recovery from QuestBriefDB, observations, and independent per-character Shortlist. Do not invent named profiles as a side effect of adopting SND. |

### AsTheCrowFlies

| Modules/behavior | Keep because |
| --- | --- |
| [Model.lua][a-model] search, spatial math and estimates; Routes.lua | Destination matching, Dijkstra search, eligibility, candidate limits, ground penalties and offered itineraries define navigation behavior. |
| [Navigation.lua][a-nav] | Walking/flying/paused/nearby/arrived states, boarding identity, flight duration sampling, teleport/death recovery are a domain state machine. |
| Adapter.lua map/taxi/NPC operations | UiMapID/world coordinate projection, taxi discovery and offered-itinerary reconciliation are distinct from screen-space layout. |
| Providers.lua and Data/ | QuestieDB contract parsing, NPC classification, spawn grouping, generated taxi graph and build provenance stay local. |
| Overlay.lua | Minimap bearing and world-map flight paths require world geometry and route identity. Screen-border helpers do not replace them. |
| Core planning/search/indexing/arrival workflow | SND may cancel delayed work; ATCF still decides when indexing completes a waiting comparison and when active navigation must be preserved. |
| UI docking, edge handle, route cards, guidance, search fields | Extract the primitive controls and gesture ownership, while retaining the actual tuck/show/dock and route composition policies. |
| Settings.Character, Sample, Timing | Build-scoped discoveries, learned flight durations, saved places and route intent are character-domain data, not appearance profiles. |
| Settings adapter | All three TOC variables are per-character. Keep that scope; ATCF's `Default` profile must not silently become XPIsland's account-shared `Shared` profile. |

## Reactive state follow-up

The [state API](API.md#3a-small-reactive-state) now proposes explicit Update/Select/Watch propagation. [Three executable exercises](STATE-EXERCISES.md) load actual domain modules from the pinned revisions above and test small UI-state bridges. Propagation, defensive snapshots, revision checks, and subscription ownership move to SND; domain authority, metadata invalidation, search generations, checkpoint timing, and gameplay state machines stay local. This refines the propagation boundary without changing the bespoke classifications above. The exercise model is not a shipped runtime or completed consumer migration.

## Tests to move, adapt, or retain

Transfer assertions and scenarios with their attribution, not the entire add-on mock runtime. SND needs its own small client test adapter. Keep end-to-end regressions in consumers to catch bad integration even when the shared component passes.

| SND contract | Existing test donors | Consumer tests that remain |
| --- | --- | --- |
| Font fallback/readback, late media, measurement | [XP tests][x-tests]: `font_startup_test.lua` including `--fail-paths`, `font_selection_test.lua`, `text_layout_test.lua`; [FAU tests][f-tests]: `font_test.lua`, `reference_widgets_test.lua`; [ATCF tests][a-tests]: runtime font/caption scenarios | Final island/stat, reward card, route-card layout and performance assertions. |
| Shell retry/controls/menu lifetime | FAU `options_test.lua`, `reference_ui_test.lua`, `reference_widgets_test.lua`; ATCF runtime short-screen/options scenarios | Recorder/search-specific options behavior and add-on-specific enabled predicates. |
| Profiles, read-only state, editor ownership | ATCF model/runtime profile and future-schema scenarios; XP runtime stale-picker regression | Actual saved-schema migrations, character assignments, session preservation and feature refresh after switching. |
| Geometry/gestures | ATCF runtime resize/dock/profile-change cases; XP layout cases; FAU `stack_layout_test.lua` geometry assertions | Expanded-island placement, docking/tucking semantics, native tooltip avoidance and map projections. |
| Async lifetime and cancellation | XP tooltip/duration cases; FAU `copy_runtime_test.lua`/`search_lifecycle_test.lua`; ATCF indexing-comparison regressions | Metadata invalidation, request identity, XP event ordering, active-route preservation. |
| Idle resource bounds | XP `frame_work_test.lua`/`stress_test.lua`; FAU repeated-open/view cases; ATCF frame-allocation scenarios | Existing real feature workload thresholds. A shared scheduler must not increase idle work. |

New tests required: two or three consumers active together, different bundled SND revisions, slash-name collision, no shared mutable Font objects, repeated canceled hook subscriptions without callback retention, staged settings failure without partial publication, nested-setting notifications, read-only adapters, and logging bounds. Native acceptance must cover supported display sizes/scales, real menu/picker input, combat restrictions, and coexistence.

## Migration sequence and acceptance

1. **Implement a small shared contract suite first.** Use native Forever fixture evidence for templates/hooks/fonts and retain Lua 5.1. Start with values, fonts, theme roles and scope ownership. Do not rewrite gameplay loops.
2. **Adopt presentation primitives in FAU first.** It is the reference shell and has focused widget/constructor tests. Replace small factories and fonts, then the options shell; leave the reward browser and tooltip engine local. Require equivalent UI behavior and no extra frame growth or idle work.
3. **Add the profile adapter and migrate ATCF options.** Preserve per-character stores, future-schema behavior, filter ownership, color editors and ongoing route state. Do not move navigation or map projection.
4. **Migrate XPIsland options and fonts.** Preserve account profile assignments, world-entry initialization, the authoritative shared clock and all bar animation contracts. Validate stock UI ownership independently of SND.
5. **Adopt scopes incrementally, then evaluate optional components.** Replace one timer/hook family at a time and rerun its original interaction. Add copy dialogs, docking or reusable list machinery only when a second consumer establishes the same contract.

Pin the exact SND revision in each consumer's release inputs. Vendor the files so users do not need another installed add-on, and verify bundled hashes in packaging. A later SND release does not silently change already published add-ons. Avoid a process-wide "newest library wins" singleton for stateful UI services.

Each migration must keep SavedVariables scope and valid settings intact, preserve unrecognized future data, retain the add-on's semantic regression tests, and pass its packaging/release guards. Preserve applicable source licenses and notices when implementation is extracted; this audit grants no new license. The SND runtime license and vendoring automation still need to be chosen before copying implementation.

## Explicit non-goals

- No generalized gameplay state machine, quest/taxi data platform, search engine, or cache invalidation framework.
- No global replacement of Blizzard functions/scripts, automatic protected-frame manipulation, or implied taint guarantee.
- No flattening every module called Model, Adapter, UI or Options into SND. Classify individual responsibilities.
- No merged settings database, automatic profile sharing, silent default-font changes, or profile import by evaluating Lua.
- No migration code or add-on behavior changes in this documentation task.

[x-core]: https://github.com/elithrar/XPIsland/blob/f2b9dcdc4da2d8c07815934746622035ad6329f6/XPIsland/Core.lua
[x-model]: https://github.com/elithrar/XPIsland/blob/f2b9dcdc4da2d8c07815934746622035ad6329f6/XPIsland/Model.lua
[x-ui]: https://github.com/elithrar/XPIsland/blob/f2b9dcdc4da2d8c07815934746622035ad6329f6/XPIsland/UI.lua#L16
[x-options]: https://github.com/elithrar/XPIsland/blob/f2b9dcdc4da2d8c07815934746622035ad6329f6/XPIsland/Options.lua#L229
[x-played]: https://github.com/elithrar/XPIsland/blob/f2b9dcdc4da2d8c07815934746622035ad6329f6/XPIsland/Played.lua
[x-progression]: https://github.com/elithrar/XPIsland/blob/f2b9dcdc4da2d8c07815934746622035ad6329f6/XPIsland/Progression.lua
[x-tests]: https://github.com/elithrar/XPIsland/tree/f2b9dcdc4da2d8c07815934746622035ad6329f6/tests
[f-core]: https://github.com/elithrar/FindAnUpgrade/blob/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/FindAnUpgrade/Core.lua
[f-ui]: https://github.com/elithrar/FindAnUpgrade/blob/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/FindAnUpgrade/UI.lua
[f-options]: https://github.com/elithrar/FindAnUpgrade/blob/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/FindAnUpgrade/Options.lua#L284
[f-adapter]: https://github.com/elithrar/FindAnUpgrade/blob/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/FindAnUpgrade/Adapter.lua#L24
[f-views]: https://github.com/elithrar/FindAnUpgrade/blob/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/FindAnUpgrade/SearchViews.lua
[f-stack]: https://github.com/elithrar/FindAnUpgrade/blob/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/FindAnUpgrade/Stack.lua#L164
[f-copy]: https://github.com/elithrar/FindAnUpgrade/blob/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/FindAnUpgrade/Copy.lua
[f-tests]: https://github.com/elithrar/FindAnUpgrade/tree/89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d/tests
[a-core]: https://github.com/elithrar/AsTheCrowFlies/blob/3d02ab66b5ff836d9215f09674e2a6c371982224/AsTheCrowFlies/Core.lua
[a-settings]: https://github.com/elithrar/AsTheCrowFlies/blob/3d02ab66b5ff836d9215f09674e2a6c371982224/AsTheCrowFlies/Settings.lua#L49
[a-options]: https://github.com/elithrar/AsTheCrowFlies/blob/3d02ab66b5ff836d9215f09674e2a6c371982224/AsTheCrowFlies/Options.lua
[a-ui]: https://github.com/elithrar/AsTheCrowFlies/blob/3d02ab66b5ff836d9215f09674e2a6c371982224/AsTheCrowFlies/UI.lua
[a-gestures]: https://github.com/elithrar/AsTheCrowFlies/blob/3d02ab66b5ff836d9215f09674e2a6c371982224/AsTheCrowFlies/UI.lua#L356
[a-model]: https://github.com/elithrar/AsTheCrowFlies/blob/3d02ab66b5ff836d9215f09674e2a6c371982224/AsTheCrowFlies/Model.lua
[a-nav]: https://github.com/elithrar/AsTheCrowFlies/blob/3d02ab66b5ff836d9215f09674e2a6c371982224/AsTheCrowFlies/Navigation.lua
[a-tests]: https://github.com/elithrar/AsTheCrowFlies/tree/3d02ab66b5ff836d9215f09674e2a6c371982224/tests
