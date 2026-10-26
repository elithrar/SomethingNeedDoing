# Working on SomethingNeedDoing

SND is a vendored WoW microframework. Keep it small enough that a capable engineer can understand the ownership model without a second abstraction layer. Favor judgment and direct implementation over elaborate plans, wrappers, generators, or speculative extensibility.

## Read the authoritative files

- [API.md](API.md) defines the supported public contract, callback timing, persistence boundaries and limitations. Update it with any public behavior change.
- [package.json](package.json) owns package metadata and the ordered runtime file list; [Embed.xml](Embed.xml) is WoW's load entry point. `tools/check.py` catches version/load-order drift.
- [examples/Consumer.lua](examples/Consumer.lua) and [examples/SettingsAdapter.lua](examples/SettingsAdapter.lua) are executable usage examples. Prefer linking these over duplicating large examples in documentation.
- [STATE-EXERCISES.md](STATE-EXERCISES.md) records current consumer evidence and unresolved gaps. [EXTRACTION-AUDIT.md](EXTRACTION-AUDIT.md) is historical source evidence, not permission to copy whole consumer modules into SND.
- [tests/README.md](tests/README.md) explains why each test exists. Native behavior must be checked against the supported client, not guessed from our mock.

## Find the implementation by responsibility

| File | Owns |
| --- | --- |
| `src/Core.lua` | Namespace bootstrap, readiness, bounded plain-data copying, errors and private ownership helpers |
| `src/State.lua` | Explicit transactions, selectors, watch delivery and revision checks |
| `src/Settings.lua` | Field validation, staged SavedVariables adapters, profile commands and settings projections |
| `src/Scope.lua` | Events, additive hooks, guards, keyed timers, cancellation and slash commands |
| `src/UI.lua` | Chrome, fonts, measurements and screen-space geometry |
| `src/Options.lua` | Pooled shell, bound controls, profile page, transient editors and visible-page scopes |
| `src/Diagnostics.lua` | Bounded, memory-only diagnostics |

`SND._`, app members beginning with `_`, and test fixture internals are private. Consumers must not depend on them. Do not add public escape hatches merely because a test can reach an internal object.

## Stable usage shape

The framework is local to the consuming TOC namespace:

```lua
local ADDON, ns = ...
local app = ns.SomethingNeedDoing:NewAddon(ADDON)
local status = app:State({ message = "Ready" })
app:OnReady(function()
    local view = app:Scope("status-view")
    view:Watch(status:Select(function(value) return value.message end), function(message)
        app.log:Info(message)
    end)
end)
```

Follow `Update → Select → Watch`. Update small plain-data snapshots after authoritative domain commands succeed. Selectors are pure projections. Watches belong to scopes; cancel a view scope on hide, and create a fresh one on reopen. Initial watch delivery provides the latest snapshot. Use an optional revision for stale editors; use consumer-owned request generations for async search identity.

Settings have one owner: declare their adapter before restoration, write through `app:Set`/profile commands, and observe with `SelectSettings`. Do not mirror profile settings into another mutable State. TOC declarations decide account versus character scope. OnReady means restoration succeeded, not that player identity or world APIs are ready.

Use `key` bindings for standard options controls. For bespoke content, use a custom component's supplied parent and visible-page scope; reuse frames when its factory is invoked again. Keep world geometry, gameplay algorithms, checkpoint policy, queries and animation clocks in the consumer.

## Preserve these invariants

- **Every interface needs at least two implementations.** Before stabilizing a shared interface, demonstrate it in two independently useful consumer integrations. Exercise all three add-ons where relevant. Two toy tests are not two integrations.
- Keep Lua 5.1 and the explicit client target. No dependency on another installed add-on or process-wide “latest version wins” library state.
- Validate staged state before publication. Failed adapters cannot mutate live globals. Unknown future schemas must remain untouched; restoration may fail explicitly rather than guess.
- Fallible APIs and persistence adapters return `true, value` / `false, { code, message }`. Commands have a nil success payload. Do not infer failure from the payload, or add wrapper/combinator APIs without two concrete uses. Programmer errors raise; asynchronous callback errors are reported. See API.md for the exact boundary.
- Validate dense arrays before ipairs; copy declaration tables before installation. Never format arbitrary error objects or rely on shared-reference identity in copied state.
- Success means committed. Reentrant writes from transactions or notifications fail; schedule intentional follow-up explicitly through the existing scope scheduler.
- Preserve cancellation during dispatch and release callback references. Secure hooks cannot be unhooked; retain inert dispatchers, not subscribers.
- Never regenerate an open native menu. Color previews are transient and must not persist; old callbacks cannot target a new profile/editor.
- No automatic protected-frame changes, domain persistence, cache invalidation, gameplay retries or telemetry. Do not infer ownership of Blizzard frames.
- No new API until an existing primitive demonstrably cannot express two concrete uses clearly. Prefer one precise operation over several convenience synonyms.

## Verification and completion

Run the commands in README. For a behavior change, add or adjust the smallest test that catches a meaningful failure; state the risk in the test's `why` text. Avoid implementation-mirroring tests, broad snapshots and test count targets. Reuse the existing native-boundary fixture; do not make it silently accept unfamiliar client methods.

For state, settings, scope or component changes, rerun the three-consumer exercise when the pinned sibling repositories are available. If unavailable, report that specifically; do not claim consumer validation from the self-contained suite. For native UI changes, distinguish source evidence and offline checks from actual in-client observation.

Keep author, description, license, version and load order consistent with package metadata. Preserve Apache-2.0 and any third-party notices if code is imported. Avoid unused generated files, prototype runtimes, caches and release archives in source control. Commit according to the current user request; this file does not impose an approval or release ceremony.

Report the concrete behavior changed, relevant checks and material remaining gaps. Do not describe mocks as production migrations or offline tests as proof of native rendering/taint safety.
