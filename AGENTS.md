# Working on SomethingNeedDoing

SND is a vendored WoW microframework. Prefer direct implementation and clear ownership over wrappers, convenience synonyms or speculative extension points. Use engineering judgment; this file defines durable boundaries, not a step-by-step script.

## Authoritative files

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

## API and ownership

- Every shared interface needs at least two independently useful consumer implementations before stabilization. Two toy tests do not qualify. Use the third add-on to challenge generalization. Lifecycle migrations do not validate production settings/options behavior; label mocks honestly.
- Before adding any public API, demonstrate why existing events, scopes, Results, selectors or custom components cannot express two concrete uses clearly. Keep gameplay clocks, queries, route graphs, native integration policy and checkpoint policy in consumers.
- Keep Lua 5.1, the declared client target and the consuming TOC namespace. No process-wide “latest version wins” registry or dependence on another installed add-on.
- State follows `Update → Select → Watch`: small plain snapshots, pure selectors and scope-owned observers. Cancel hidden views and create a fresh scope on reopening. Preserve consumer request generations for asynchronous identity.
- Settings have one owner: declare settings before readiness; omit the adapter for new databases or supply a legacy adapter, mutate through `app:Set`, `app:SetMany` or profile commands and observe with `SelectSettings`. Never mirror a live profile into a second writable store. Transfer every write path together, including previews, drag commits and profile replacement. TOCs determine account/character persistence; adapters preserve schema and recovery policy.
- Fallible operations return `true, value` or `false, {code, message}`; successful commands return `true, nil`. Declaration-only methods such as Settings and Appearance return no value. Check the boolean. Programmer errors raise; callback errors are reported and contained. Never format arbitrary error objects. Validate dense arrays and copy declarations before installing them.
- Validate before publishing. Failed adapters cannot change live globals; unknown future schemas remain untouched. Reentrant writes fail rather than becoming hidden queued work.

## Lifecycle and presentation

- Readiness means restoration succeeded, not that player identity or world APIs are available. Ordinary callbacks wait for readiness.
- Scoped logout subscribers run once before disposal and may read committed state. Their failures, recursive delivery or failing panel cleanup must not prevent cancellation. Work scheduled during logout is canceled; WoW controls disk persistence.
- Unused font/layout services must not install listeners. Passive measurements do not activate media tracking. Pre-ready and late activation must both work; disposed instances cannot acquire new resources.
- Give external callbacks guarded lifetimes, even when the external API offers unregistering. Partial attachment failure must cancel acquired subscribers and remain retryable. Secure hooks retain inert native dispatchers, never canceled subscriber references.
- Declare appearance before readiness. Themes are copied plain definitions: shared semantic colors and borders, optional consumer tokens. `theme`, `font` and `fontSize` settings drive the common path. Do not add inheritance, global registries or alternate selection mechanisms.
- Register owned surfaces with `ui:Style`, typography with `fonts:Apply`, and semantic colors with `ui:Color`. Fonts preserve explicit product colors. Custom views use `scope:Watch(app:SelectAppearance(...), ...)` to remeasure after fonts settle; the standard options panel handles this itself. Keep gameplay geometry/artwork in its renderer.
- Use `SetMany` for related changes such as mode+format or placement coordinates. Legacy adapters stage `patch` atomically. A consumer may retain a read-only settings projection, but every write path—including gestures and context menus—must use the commands. Profile replacement must invalidate stale gestures even when the profile name is unchanged.
- Use ordinary `key` bindings and the existing custom-component parent/scope contract. Reuse frames across opens. Never rebuild menus under input or let stale color/profile/editor callbacks write new settings. Preview values are transient.
- Do not change protected frames, own Blizzard state, add automatic gameplay retries or collect telemetry.

## Verification and repository hygiene

Run the README commands. Add only the smallest regression that protects a real failure boundary, with its reason beside the test. Do not duplicate this rationale in a separate test catalog. Rerun optional consumer checks for state, settings, scope or component changes when sibling sources exist; otherwise report the missing evidence.

Keep source, consumer-facing documentation/examples, package metadata and necessary verification infrastructure. Historical audits and review transcripts belong in PRs or Git history, not permanent parallel specifications. Keep caches, generated archives and scratch work out of source control and verification files out of the consumer package.

Keep version, author, description, Apache-2.0 license and load order consistent. Follow the user's current commit/PR authorization; this file adds no release ceremony. Report source inspection, offline checks and in-game observation separately. Passing mocks cannot establish native rendering, input, combat/taint safety or coexistence.

When changing a public API—including return values, usage or error handling—update API.md and the affected README.md examples and executable examples in the same change. Update this file where its guidance is affected; keep API details in the user documentation rather than duplicating them here.
