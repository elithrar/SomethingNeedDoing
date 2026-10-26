# Three-consumer exercise: SND 0.2.0

[exercises/run.lua](exercises/run.lua) now loads the **real SND runtime**, the small native-boundary fixture in [tests/wow.lua](tests/wow.lua), and actual domain modules from the pinned revisions in [EXTRACTION-AUDIT.md](EXTRACTION-AUDIT.md). The disposable design-model implementation has been removed. Run instructions are in [README.md](README.md#develop-and-verify).

These are mock integrations, not changes to the shipping add-ons. The profile adapters implement representative existing storage shapes; they do not replace or execute every historical migration. All three runtime exercises passed under Lua 5.1.

## What was implemented and exercised

| Consumer | Actual source loaded | Mock integration and outcome |
| --- | --- | --- |
| XPIsland | `Model.lua`: NewSession, NewTracker, Sample | Real 100→150 XP sampling publishes a small display transaction. Closed view stops rendering. Account-profile adapter remains read-only until character binding, then writes the assignment. Switching between equal-valued profiles notifies an identity selector. |
| FindAnUpgrade | `Model.lua`, `Shortlist.lua`: Load, Toggle, Remove | Duplicate legacy IDs retain their recovery record. Successful commands publish membership. Explicit metadata revision refreshes unchanged IDs. Hidden/reopened view catches up. Future schemas remain intact, and an oversized legacy list can shrink while new additions are rejected. |
| AsTheCrowFlies | `Model.lua`, `Navigation.lua`: New, Start | Separate per-character profile globals commit together. Equal-valued profile switch notifies identity; missing target leaves state intact. An older search result is rejected by its generation, and current results do not interrupt the active walking route. |
| FAU and ATCF | Consumer-specific custom component sketches | Page scopes cancel on hide and rebind on reopen; no hidden notifications or duplicate subscriptions. Two independent consumers use the same custom component lifetime contract. |

## Gaps exposed and targeted resolutions

1. **Profile identity is independent of field equality.** The real settings selector exposes `activeProfile`, `readOnly` and `needsCharacter`. Both account and character profile mocks verify this, without a mirrored mutable settings store.
2. **Custom components lacked an allocated location.** A shared body parent made a custom component's placement ambiguous. SND now supplies a reusable per-control container at the layout position. The component still implements only Refresh, Layout(width), Hide; no new public method was necessary.
3. **Ordinary setting changes must not close native menus.** Contract tests caught an overly broad transient cleanup path. Ordinary writes retain menu ownership and defer refresh; profile transitions close owned transients.
4. **Persistent commands and reactive display are separate authorities.** FAU's capacity rule cannot become a blanket length validator without breaking legacy recovery. Keep its command owner and publish successful outcomes. No generic persistence API was added.
5. **Store revisions do not replace request generations.** ATCF preserves its domain generation check. An unrelated status update must not invalidate a current query, and provider readiness must not implicitly start navigation.

The small API was sufficient for these paths: State/Read/Update/Select/Watch/SelectSettings, plus existing settings/profile and scope operations. No reactive proxy, computed graph, request framework, additional widget binding DSL or cross-store transaction was needed.

## Material remaining limits

- General domain persistence is still consumer-owned. Publishing a UI projection after a saved-domain command is not an atomic cross-store transaction. Handle projection errors and reconcile from the authoritative model.
- State trees have explicit defensive bounds (32 levels, 20,000 entries per copy). These are safety limits, not a performance guarantee. Keep catalogs, routes, histories and per-frame interpolation outside; benchmark actual consumer workloads before migrating hot paths.
- Profiles, schemas and migrations in shipping add-ons still need their own integration regressions. The two profile adapters here establish the shared operation shape, not migration completeness.
- Native rendering, dropdown/picker interaction, client UI scale/notch behavior, protected-frame restrictions and mixed-version coexistence need in-game acceptance. A mocked Frame cannot establish those properties.
- Geometry helpers react to show, size and display changes. Consumers call a placement handle's Refresh after moving an anchor; there is no permanent position polling.

**Every interface needs at least two implementations** remains a stabilization rule. The exercised state/profile/component interfaces have concrete multi-consumer evidence; other UI services have focused native-boundary tests and source evidence, not two completed production migrations. Treat 0.2.0 as the initial implementation, with that distinction intact.

## 0.2 API/DX review before publication

All three integrations were rerun before publishing the breaking Result changes. XP's account/identity adapter and ATCF's per-character adapter now share `Restore`/`Prepare` success payloads (`{ state, saved }`). FAU uses the runnable single-settings adapter and keeps its domain shortlist command contract local. SND does not force external add-on models to adopt a new return convention.

ATCF's search mock now also runs through the real keyed timer scheduler: it checks `ok, timer`, rejects a stale external completion and preserves active navigation when the current scheduled search completes. XP checks the structured read-only error before character binding. FAU and ATCF still reuse the same visible-page ownership contract without additional widget methods.

The review covered bootstrap/readiness, state snapshots/selectors, field and profile adapters, options declarations/custom components, scope scheduling/hooks, typography/layout and diagnostics. Changes were limited to explicit Result tuples, dense-list validation, copied declarations and safe error normalization. Getters and infallible registrations retain direct values. No wrapper objects, map/unwrap combinators, new persistence registry or consumer-domain abstraction was needed.

Native client validation and full historical schema migrations remain outstanding; these mocks establish API fit, not in-game acceptance.
