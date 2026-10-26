# Working on SomethingNeedDoing

SND is a vendored WoW microframework. Prefer direct implementation and clear ownership over wrappers, convenience synonyms or speculative extension points. For consumer integration, follow the API and ownership guidance here alongside the add-on’s own client, persistence and gameplay rules. Repository maintenance instructions below apply to changes within SND.

## Authoritative files

Paths below are relative to the SND source root. Prefer the full pinned source tree, including examples, tests and tooling. If a vendored copy omits a referenced file, use the same path in [upstream SND](https://github.com/elithrar/SomethingNeedDoing) at the consumer’s pinned tag or commit, not current main.

- [API.md](API.md): public signatures, Result contracts, callback timing and persistence boundaries. Change it with behavior, not ahead of evidence.
- [package.json](package.json): version, author, license, consumer package files and ordered runtime files. [Embed.xml](Embed.xml) loads those files in WoW; `tools/check.py` checks drift.
- [examples/Consumer.lua](examples/Consumer.lua) and [examples/SettingsAdapter.lua](examples/SettingsAdapter.lua): executable consumer usage. Prefer improving these to creating more overlapping guides.
- [tests/run.lua](tests/run.lua): focused contracts, each with its failure-risk justification. [tests/wow.lua](tests/wow.lua) models only native boundaries. [tests/consumers.lua](tests/consumers.lua) optionally loads sibling add-on domain modules; its header records source baselines.

| File | Responsibility |
| --- | --- |
| `src/Core.lua` | Namespace, readiness, disposal, plain-data copies and private ownership helpers |
| `src/Scope.lua` | Events, additive hooks, guards, keyed timers and slash commands |
| `src/State.lua` | Transactions, selectors, revisions and watch delivery |
| `src/Settings.lua` | Validation, default profile storage, legacy adapters and atomic settings commands |
| `src/UI.lua` | Theme roles, appearance observation, fonts and owned screen geometry |
| `src/Options.lua` | Pooled controls, pages, custom components and transient editors |
| `src/Diagnostics.lua` | Bounded memory-only diagnostics |

`SND._`, underscore-prefixed app members and fixture internals are private. Never use them in consumer examples or expose a helper just because a test can access it.

## Work from contracts and implementations

- Start with the consuming TOC for client/interface, load order and SavedVariables scope. Read the affected API.md contract, the owning source file above and the nearest executable example before changing behavior. For an integration, trace the actual event or user action through its state owner to the visible result.
- Verify unfamiliar native methods, events, return values and template scripts against the supported client revision of [Blizzard UI source](https://github.com/Gethe/wow-ui-source): generated definitions in `Blizzard_APIDocumentationGenerated`, then the relevant template/mixin and call sites. Reuse the consumer's pinned source fixtures or CI revision; record new evidence with the affected check. Do not substitute the repository's default branch or another WoW flavor. Blizzard call sites may use privileges unavailable to add-ons.
- Mocks are boundary models, not API authority. Check the native object type and inherited methods: a generic Frame does not support every Button script, and a void `SetFont` return does not prove failure—see readback handling in `src/UI.lua`. Compare real consumer implementations when available; the domain mocks in `tests/consumers.lua` do not establish complete UI compatibility.

## API and ownership

- When extending SND, first check whether existing events, scopes, Results, selectors or custom components solve the requested behavior. Add API only when it makes the implementation clearer. Keep gameplay clocks, queries, route graphs, native integration policy and checkpoint policy in consumers.
- Keep Lua 5.1, the declared client target and the consuming TOC namespace. No process-wide “latest version wins” registry or dependence on another installed add-on.
- State follows `Update → Select → Watch`: small plain snapshots, pure selectors and scope-owned observers. Cancel hidden views and create a fresh scope on reopening. Preserve consumer request generations for asynchronous identity.
- Settings have one owner: declare settings before readiness; omit the adapter for new databases or supply a legacy adapter, mutate through `app:Set`, `app:SetMany` or profile commands and observe with `SelectSettings`. Never mirror a live profile into a second writable store. Transfer every write path together, including previews, drag commits and profile replacement. TOCs determine account/character persistence; adapters preserve schema and recovery policy.
- Fallible operations return `true, value` or `false, {code, message}`; successful commands return `true, nil`. Declaration-only methods such as Settings and Appearance return no value. Check the boolean. Programmer errors raise. Transaction callback exceptions return failed Results without publishing; notification callback exceptions are reported without rolling back a successful commit. See API.md for callback-specific contracts. Validate ordinary user input at the UI boundary before calling programmer-checked commands. Recovery guards must clear after native failures so the next interaction can retry. Never format arbitrary error objects. Validate dense arrays and copy declarations before installing them.
- Validate before publishing. Failed adapters cannot change live globals; unknown future schemas remain untouched. Never execute imported configuration as Lua. Reentrant writes fail rather than becoming hidden queued work.

## Lifecycle and presentation

- Readiness means restoration succeeded, not that player identity or world APIs are available. Ordinary callbacks wait for readiness.
- Scoped logout subscribers run once before disposal and may read committed state. Their failures, recursive delivery or failing panel cleanup must not prevent cancellation. Work scheduled during logout is canceled; WoW controls disk persistence.
- Unused font/layout services must not install listeners. Prefer events and keyed, coalesced work; keep frame allocation, font resolution and repeated text measurement out of animation callbacks. Pre-ready and late activation must both work; disposed instances cannot acquire new resources.
- Give external callbacks guarded lifetimes, even when the external API offers unregistering. Complete capability probes before publishing ownership; on attachment failure, cancel acquired subscribers and leave registration retryable (see `src/UI.lua` and `src/Scope.lua`). Secure hooks retain inert native dispatchers, never canceled subscriber references.
- Declare appearance before readiness. Themes are copied plain definitions: shared semantic colors and borders, optional consumer tokens. `theme`, `font` and `fontSize` settings drive the common path. Do not add inheritance, global registries or alternate selection mechanisms.
- Register owned surfaces with `ui:Style`, typography with `fonts:Apply`, and semantic colors with `ui:Color`. Fonts preserve explicit product colors. Custom views use `scope:Watch(app:SelectAppearance(...), ...)` to remeasure after fonts settle; the standard options panel handles this itself. Keep gameplay geometry/artwork in its renderer.
- Use `SetMany` for related changes such as mode+format or placement coordinates; adapters stage `patch` atomically. Profile replacement must invalidate stale gestures even when the profile name or selected values are unchanged.
- Use ordinary `key` bindings and the existing custom-component parent/scope contract. Reuse frames across opens. Never rebuild menus under input or let stale color/profile/editor callbacks write new settings. Preview values are transient.
- Secret-value restrictions, forbidden objects and combat/protected actions are separate contracts. Check before inspecting values or changing UI; `pcall` does not make a prohibited operation valid. Do not change protected frames, replace Blizzard scripts, add automatic gameplay retries or collect telemetry.

## Verification

For consumer changes, run the add-on’s checks and exercise the affected integration. For SND changes, follow the framework checks below.

Run the SND README commands. Add only the smallest regression that protects a real failure boundary, with its reason beside the test. Exercise the original entry point and recovery: after a native failure, restore the boundary and verify the next action updates actual text, geometry or committed state, not merely that `Open()` succeeds. Cover relevant hide/reopen, profile replacement and late-font transitions; use `tests/run.lua` for existing failure-injection patterns. Rerun optional consumer checks for state, settings, scope or component changes when sibling sources exist; otherwise report the missing evidence.

## SND repository maintenance

Keep source, consumer-facing documentation/examples, package metadata and necessary verification infrastructure. Historical audits and review transcripts belong in PRs or Git history, not permanent parallel specifications. Keep caches, generated archives and scratch work out of source control. Vendored source may include tests and tooling; only runtime files belong in the TOC/Embed.xml load order.

Keep version, author, description, Apache-2.0 license and load order consistent. Follow the user's current commit/PR authorization; this file adds no release ceremony. Report source inspection, offline checks and in-game observation separately. Passing mocks cannot establish native rendering, input, combat/taint safety or coexistence.

When changing a public API—including return values, usage or error handling—update API.md and the affected README.md examples and executable examples in the same change. Update this file where its guidance is affected; keep API details in the user documentation rather than duplicating them here.
