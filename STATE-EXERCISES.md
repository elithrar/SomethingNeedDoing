# State API: three consumer exercises

These are executable **mock migrations**, not production migrations. They load actual domain modules from the three revisions in [the extraction audit](EXTRACTION-AUDIT.md) and connect them to a small offline state model. None of the add-ons has been modified. The model is deliberately not packaged as SND, and its simplified error strings are not the proposed public error records.

**Every interface needs at least two implementations.** Here that means independently useful consumer integrations, not two copies of framework internals or two tests of the same toy counter. These exercises provide three initial design probes. Stabilization still requires at least two complete consumer integrations against the real runtime, followed by native-client acceptance.

## Reproduce

Keep the four repositories as sibling directories. Use the exact add-on commits listed in EXTRACTION-AUDIT.md. From SomethingNeedDoing:

```sh
lua5.1 exercises/run.lua
```

Alternatively install `lupa` in a development Python environment and run `python exercises/run.py`; this explicitly selects Lupa's Lua 5.1 runtime. No dependencies are needed by the Lua runner itself. No network access, SavedVariables disk writes, or WoW client is used by the exercises.

Files: [state model](exercises/state_model.lua), [consumer exercises](exercises/run.lua), [optional Python runner](exercises/run.py).

## XPIsland: publish display values after authoritative sampling

**Source:** `XPIsland/Model.lua` NewSession/NewTracker/Sample and `Core.lua` Sample/RefreshAppearance/ApplyProfile at the audit revision.

**Migration sketch:** keep the existing model, sample ordering, session clock, histories, and checkpoint code. After an accepted sample, publish the small `{xp, cap, level}` display record with one Update. A visible view watches `{xp, cap}`. Appearance watches SelectSettings rather than copying profile values into that display record. Existing highlight/animation commands remain explicit: two events can have equal state but still represent separate effects.

**Executed:** load the real Model.lua; sample 100 then 150 XP; publish and observe one changed render. Change only level and prove the selected record does not render again despite allocating a fresh projection table. Reject a stale revision, detach the hidden view, and prove reopening reads the current value.

**Poor fit found:** reference equality would repaint on every freshly constructed record. Deep observation of the tracker would capture metatables, histories and mutable accounting internals. Mirroring settings creates two authorities, especially on profile switch.

**Targeted changes:** structural equality for small plain-data records; SelectSettings; optional revision checks. Do not add proxy instrumentation or an animation API. The exercise's stale-revision case tests the state primitive; the actual profile/color-picker integration remains a required settings-adapter test.

## FindAnUpgrade: membership is not metadata freshness

**Source:** `Shortlist.lua` Load/Toggle/Remove; `SearchViews.lua` ShortlistQuery; `Search.lua` DataChanged/CharacterChanged/Refresh/OnHide at the audit revision.

**Migration sketch:** retain Shortlist as the SavedVariables authority initially. A successful Toggle publishes IDs to a small view-input store. Character/catalog changes publish a domain-owned metadata revision even when IDs are unchanged. A watcher marks the existing search view dirty; its existing scheduler preserves request budgets, native-menu release, and hidden-view behavior. Query calculation is an effect in that controller, not an impure selector that silently reads Character/Catalog.

**Executed:** load actual Model.lua and Shortlist.lua. Normalize a duplicate legacy list while retaining its recovery record; publish a successful addition; propagate metadata invalidation with unchanged IDs; detach and reopen a view; reject writes to a future schema without modifying its original data; allow removal from an oversized legacy list while rejecting a new addition.

**Poor fit found:** watching only IDs reproduces the conceptual cause of stale shortlist content. A generic `#ids <= 20` validator incorrectly rejects valid operations on oversized legacy lists. Immediate rendering on every notification would bypass menu safety and debounce rules.

**Targeted changes:** document explicit external dependencies, initial watch delivery, and consumer-owned scheduling. Preserve the existing command policy for capacity. No generic cache invalidation, validator DSL, or implicit debounce option is warranted.

## AsTheCrowFlies: comparison state is independent of navigation

**Source:** `Navigation.lua` New/Start and `Core.lua` Search/Plan/provider indexing completion at the audit revision.

**Migration sketch:** leave Navigation and the route graph as the authority. Group query, search status, matches and search generation in one small comparison store. A single Update clears old results while publishing searching=true. Completion checks the captured generation before publishing matches. Provider completion resumes a pending plan only when its captured generation still matches. These are explicit consumer decisions; a watcher never starts navigation merely because results exist.

**Executed:** load actual Model.lua and Navigation.lua and start a real model route. Issue two mock searches; reject the older completion, accept the current one, assert coherent UI snapshots, and verify navigation stays walking. Edit a pending comparison and verify its generation no longer qualifies for resume.

**Poor fit found:** a broad store revision is too coarse for async request identity: an unrelated status change can invalidate a valid request. A scope's lifetime alone is too coarse when several requests share one view. Generic effects that react to provider readiness risk restarting an active route.

**Targeted changes:** keep generation checks in the consumer; use one Update for related UI fields. The existing Guard/After primitives are sufficient for lifetime and timer ownership. No framework request-token or cross-store transaction API yet.

## Small API changes justified by the exercises

| Decision | At least two concrete uses | Cost/boundary |
| --- | --- | --- |
| Initial delivery on Watch; cancel on hide | XP display, FAU shortlist, ATCF comparison panel | No separate mount-read-subscribe sequence or pause/resume methods. |
| Structural equality for selected records | XP appearance/display, ATCF result status; FAU IDs/dependency record | Copy/compare small records. Large models stay outside. |
| Optional expected revision on Update/Set | XP color edits, ATCF options/gestures | Primitive exercised; actual editor integration still pending. Async searches continue using domain generations. |
| SelectSettings over the existing owner | XP account profile, ATCF character profile; FAU single settings | One additional entry point; no mirrored reactive profile store. Settings projection integration still pending. |
| Reject writes during notification | XP appearance refresh, FAU control refresh, ATCF search rendering | Precise synchronous result, no invisible queued failures. Explicit scheduling for intentional follow-up. |
| Atomic updates and owned watches | XP display pair, ATCF search status/results, FAU view inputs | No batching, middleware, computed-store graph, or UI binding DSL. |

The core addition is six entry points: State, Read, Update, Select, Watch, SelectSettings. Set gains an optional revision argument. Existing settings, scopes, controls and timers carry the rest. No new global store registry or SavedVariables API is added in this iteration.

## Verification and remaining gates

The offline run passed **36 assertions** under Lua 5.1, including atomic validation/exception failure, draft/read isolation, no-op suppression, changed-record equality, stale edits, hidden/reopened views, notification failure isolation, rejected reentrant writes, cancellation during dispatch and cyclic-data rejection. The run uses original domain modules; mocked controllers/render counters stand in for the real UI. This verifies the exercise model's selected semantics, not an implemented SND SDK.

The offline model represents one app and omits bootstrap readiness, SelectSettings/profile adapters, secret-value checks, native rendering, scope timers, detailed diagnostic/error objects, and performance limits. It is not a second production state implementation and must not be vendored into an add-on. Full Core event handlers, real native-menu release, color-picker callback ordering, and async timer queues are source-reviewed rather than executed here.

Before stabilizing the API:

1. Implement SelectSettings with XP and ATCF profile adapters; test equal-value switches, failed migration, read-only transitions, preview cancellation, and same-commit notification ordering.
2. Implement visible-page scope rebinding in FAU and ATCF custom components; verify repeated open/hide does not retain callbacks or allocate frames. Test registration/cancellation during dispatch in the real app-scoped scheduler.
3. Port one real controller path each in FAU and ATCF, including native menu deferral and stale provider completion. Keep original consumer regressions.
4. Measure copy/compare work using realistic XP display updates, FAU shortlist inputs and ATCF result summaries. Define supported size/depth limits from those measurements; no performance claim is made here.
5. Verify supported-client rendering, protected-frame behavior, SavedVariables restoration, and multiple independently bundled SND versions in WoW.

General domain persistence remains the clearest material gap. The existing settings adapter supports settings persistence; the runtime state API intentionally does not promise atomic domain storage plus UI publication. Two full domain-storage integrations must establish migration, recovery and checkpoint semantics before adding a stable adapter. Until then, a consumer's existing domain owner commits first and publishes a validated UI projection afterward, with explicit error handling.
