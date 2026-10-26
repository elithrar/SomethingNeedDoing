# SomethingNeedDoing: initial API surface

**Status: proposed, unimplemented.** This document stubs the initial contract; the examples are design sketches, not a working SDK. API names and adapter shapes may change before the first release. See [the extraction audit](EXTRACTION-AUDIT.md) for source candidates and migration boundaries.

SND supplies registration, small reactive state, settings bindings, consistent options panels, window chrome, fonts, screen geometry, owned callbacks, and diagnostics. Add-ons retain gameplay models, API-specific interpretation, persistence migrations, and product behavior.

## 1. Packaging and instance ownership

The first implementation target is **WoW Forever, interface 16001, Lua 5.1**. Retail or other clients require explicit adapters and native-contract tests; a familiar API name does not establish compatibility.

Bundle a pinned copy under each consuming add-on, loaded before that add-on's modules through its TOC. The bootstrap exports a factory into the TOC namespace. It does not register a standalone add-on, shared SavedVariables, or a global singleton.

```lua
local ADDON, ns = ...
local SND = ns.SomethingNeedDoing

local app = SND:NewAddon(ADDON, {
    version = "0.1.0",
})
ns.app = app
```

`NewAddon(name, spec) -> app` creates an isolated instance. Duplicate registration within the same namespace is a programmer error. Named frames, Font objects, and slash registrations are prefixed with the consuming add-on's identity. Independently bundled SND versions must coexist without sharing font preferences, event subscribers, or caches.

## 2. Lifecycle

```lua
app:OnReady(function(self)
    -- Saved settings are restored; player/world APIs may still be unavailable.
end)

local world = app:Scope("world")
world:Event("PLAYER_ENTERING_WORLD", function(initialLogin, reloading)
    -- The add-on decides when its character-dependent initialization is ready.
end)
```

| API | Contract |
| --- | --- |
| `app:OnReady(callback) -> subscription` | Once, after the matching `ADDON_LOADED` and successful settings restoration. A late subscriber is queued for the next frame. |
| `app:IsReady() -> boolean` | Settings/bootstrap readiness, not player identity, world readiness, or API availability. |
| `app:Scope(name) -> scope` | Create an active owner for subscriptions and work. Duplicate live names are rejected; a canceled name can be reused with a new identity. |
| `app:Slash(command, callback) -> subscription, error` | Register an explicit slash command; callback receives the unmodified argument string. Reject collisions rather than overwriting another owner. |

Settings declarations must happen before restoration. Ordinary scoped subscriptions become active after `OnReady`; internal bootstrap uses its own event owner. Logout disposes owned runtime work without rewriting domain checkpoints. There is no implicit restart, enable/disable lifecycle, or guarantee that a module is safe merely because `OnReady` ran.

Registration mistakes raise developer-facing errors. Recoverable runtime failures return `nil, { code = "...", message = "..." }`; boolean mutation methods return `false, error`. Callback exceptions are reported to diagnostics and the native error handler, with cleanup completed and no automatic retry.

## 3. Settings declarations and writes

```lua
app:Settings({
    savedVariables = { "ExampleDB" },
    adapter = ns.SettingsAdapter,
    fields = {
        font = { type = "font", default = "Game tooltip" },
        fontSize = { type = "integer", default = 14, min = 10, max = 18 },
        scale = { type = "number", default = 1, min = 0.5, max = 1.5 },
        locked = { type = "boolean", default = true },
        ["colors.text"] = { type = "color", default = { 0.93, 0.94, 0.97 } },
    },
})

app:OnSettingsChanged(function(self, change)
    if change:Touches("font", "fontSize", "scale") then
        ns.UI:RefreshAppearance()
    end
end)

local size = app:Get("fontSize")
local ok, err = app:Set("fontSize", 16)
```

| API | Contract |
| --- | --- |
| `app:Settings(spec)` | One declaration per app; names must already be declared in the consumer's TOC. Multiple variables support existing profile layouts. |
| `app:Get(path) -> value` | Validated active settings; table values are defensive copies. Reading before readiness is an error. |
| `app:Set(path, value, expectedRevision?) -> boolean, error` | Validate, prepare, commit, then notify. Unknown fields, unreadable values, invalid types, and read-only stores fail without mutation. |
| `app:OnSettingsChanged(callback) -> subscription` | Receive committed changes; listener failures cannot roll back a successful commit. |
| `change:Touches(...) -> boolean` | Whether any named field changed. Profile switches also carry `profileChanged = true`. |

Initial field types: `boolean`, finite `number`, finite `integer`, bounded `string`, `enum` with explicit values, `font` as a saved preference name, and RGB `color` with components in `[0,1]`. Dotted paths access nested settings; literal dots in field names are not supported initially. Reject invalid interactive input; legacy normalization/clamping belongs to the migration adapter. Missing fonts retain their requested preference while the renderer falls back.

Change records contain `revision`, `reason` (`set`, `switch`, `duplicate`, `copy`, `reset`, or `bind`), `keys` as a set of paths, and `profileChanged`. No-op writes emit nothing. Reentrant writes from listeners are rejected with `reentrant`; schedule intentional follow-up work explicitly (see section 3a). Options refreshes must not feed writes back into controls.

### Persistence adapter stub

The adapter is add-on-owned. SND reads only declared globals after restoration; it does not choose account/character scope or infer a schema from field defaults.

```lua
local Adapter = {}

function Adapter:Restore(savedByName, fields)
    -- -> state, normalizedSavedByName OR nil, error
    -- Validate/migrate copies; preserve unrecognized future data verbatim.
end

function Adapter:Prepare(state, operation, fields)
    -- -> candidate OR nil, error
    -- candidate = { state = nextState, saved = nextSavedByName }
    -- Pure staging: do not mutate current state or restored globals.
end
```

`state` supplies `values` (the active settings table), `readOnly`, `activeProfile` (optional name), and a `profiles` descriptor containing names and supported operations. It can carry opaque adapter-owned data for the existing database layout. SND validates the complete candidate before replacing declared globals and its current state, without yielding or calling listeners between assignments. All callbacks run afterward. `Prepare` receives `{ kind = "set", path = ..., value = ... }` or one of the profile operations below. The adapter remains responsible for preserving unrelated fields and SavedVariables aliases.

On restore, normalized globals are installed only for a writable state. Future schemas remain untouched and can expose read-only defaults; an adapter may instead return an explicit incompatible-schema error and prevent readiness. Identity-dependent stores can expose defaults read-only with `needsCharacter = true` until the add-on calls `BindCharacter`. Thus SND does not move XPIsland's player initialization from world entry to file load.

## 3a. Small reactive state

**Design rule: every interface needs at least two consumer implementations.** Exercise shared contracts against concrete behavior in at least two add-ons before stabilizing them; use all three where applicable. Mock integrations provide design evidence, not completed migrations or live-client acceptance. See [the executable exercises and findings](STATE-EXERCISES.md).

State propagation is explicit: **Update → Select → Watch**. There is no metatable-based property tracking, global store, automatic effect retry, or reactive gameplay state machine.

```lua
local search = app:State({ query = "", searching = false, matches = {} })
local results = search:Select(function(snapshot)
    return { searching = snapshot.searching, matches = snapshot.matches }
end)

-- Create a fresh scope each time this view opens; cancel it on hide.
local view = app:Scope("search-view")
view:Watch(results, function(value, previous, revision)
    ns.SearchUI:Render(value)
end)

local ok, err = search:Update(function(draft)
    draft.query = "Ironforge"
    draft.searching = true
    draft.matches = {}
end)
```

### Six entry points, one ownership model

| API | Contract |
| --- | --- |
| `app:State(initial, spec?) -> state` | Create an app-owned, memory-only plain-data store. Optional `spec.validate(candidate) -> boolean, error` validates initial data and each candidate. It cannot normalize or mutate committed data. |
| `state:Read() -> snapshot, revision` | Defensive copy and monotonically increasing store-local revision, starting at zero. |
| `state:Update(mutator, expectedRevision?) -> boolean, error` | Copy current state, run the mutator, validate, commit once, then notify. Optional revision rejects stale writes before running the mutator. |
| `state:Select(project) -> selection` | Describe a pure projection of this store. A selection is not another mutable store and has no scheduler or permanent subscription. |
| `scope:Watch(selection, callback) -> subscription` | Deliver the current selected value once on activation, then changed values after commits. Callback receives `(value, previous, revision)`; previous is nil on initial delivery. Scope/handle cancellation detaches it. |
| `app:SelectSettings(project) -> selection` | Project directly from committed active settings, using the same Watch contract. No mirrored settings store. Project receives `(values, context)` where context contains `activeProfile`, `readOnly`, and `needsCharacter`. |

State may be declared before readiness; watches declared then activate after successful restoration. Watches registered after readiness deliver the initial value synchronously before returning. Do not capture the not-yet-returned subscription handle inside that first callback. A hidden view cancels its scope and creates a fresh one on reopen; initial delivery catches up without replaying missed changes. State lifetime is the app lifetime; selectors subscribe only while watched. App teardown releases stores and subscriptions.

### Update and equality rules

- Data consists of readable nil/boolean/string/finite-number values and acyclic plain tables with string or finite integer keys. No frames, functions, userdata, metatables, secret values, or shared-reference identity contracts. Domain objects and large catalogs stay outside. A nil field is absent, as in Lua.
- The mutator edits a private draft and must not yield or perform side effects. Return `false, error` to reject; a nil return accepts the draft. Exceptions, validation failure, and stale revisions leave state and revision untouched. Retained drafts, reads, selector inputs, validator inputs, and callback values cannot mutate live state.
- A structurally equal candidate is a successful no-op: no revision increment or notification. Scalars compare by value; plain tables compare recursively by keys and values, ignoring insertion order. Selections use the same rule, so returning a small new record does not trigger spurious renders. Nil is a valid selected value. No configurable comparator in v0.
- All active projections for that store reevaluate on a commit; only changed selections notify. Selectors are pure and cannot query mutable external state as an undeclared dependency. Publish a small domain-owned revision or derived value when external data changes. There is no automatic dependency tracking between stores or selector chaining in v0.
- One Update is one transaction. Keep fields that must change together in the same store. No cross-store transaction, batching API, or implicit next-frame coalescing. Distinct stores are appropriate when their changes are independent.
- Writes during any SND mutator, validator, selector, or change callback are rejected with `reentrant`, including writes to another state/settings store in the same app. This replaces the earlier queued-settings-write proposal: success must mean committed, not merely queued. When an intentional follow-up is required, schedule it explicitly through `scope:After(0, key, callback)` and retain the consumer's loop prevention.
- Watchers run synchronously in registration order after publication. A watcher failure is reported and cannot roll back a commit or prevent other watchers from running. A failed projection retains its last successful value and can retry on the next commit. Cancellation during delivery suppresses later canceled subscribers; registration during delivery takes its initial snapshot immediately and joins subsequent commits. No yielding callbacks.

Use small display snapshots, not per-frame copies of an XP history, navigation graph, or quest catalog. Animation interpolation stays in the renderer; domain clocks and reconciliation stay in the model. This first design deliberately trades copying and structural comparison for predictable ownership. Benchmark actual store sizes before promoting it to a production runtime.

### Settings, editors, and UI bindings

```lua
local appearance = app:SelectSettings(function(values, context)
    return { font = values.font, scale = values.scale,
        profile = context.activeProfile, readOnly = context.readOnly }
end)
view:Watch(appearance, function(value)
    ns.UI:ApplyAppearance(value)
end)
```

`SelectSettings` uses the existing settings revision and transaction owner. Watchers see the fully committed profile and values. Equal-value profile switches notify only projections that include identity/status; the existing `OnSettingsChanged` still provides operation reasons and `profileChanged`. Both notification APIs read the same commit, and writes from either are rejected during dispatch. Do not register both to perform the same refresh.

Extend `app:Set(path, value, expectedRevision?)` with the same stale-revision check. A settings watcher receives the revision that an editor can capture at opening; any intervening committed change invalidates that edit. SND's built-in editor already owns this token. Color previews stay outside committed state and continue using the explicit preview callback. Preview cancellation, menus, and gesture cleanup follow the existing profile rules.

Built-in options controls remain bound with `key`; they do not need a second state binding language. The shell reevaluates `enabled(app)` and `visible(app)` on committed settings changes. These predicates must read settings only; custom components watch domain state through their supplied scope. Custom component scopes activate while their page is visible, cancel on hide, and are replaced on reopening. The shell calls the retry-safe `create(parent, app, scope)` again to rebind reused frames to the new scope, then Refresh/Layout. Consumers must not keep an old canceled scope in a reused frame script. Native menu safety still defers actual layout/menu rebuilding until release; reactivity does not permit rebuilding under input.

### SavedVariables boundary

State is not automatically persisted. Settings already use the declared globals and Restore/Prepare adapter above; they are one state owner, not a settings store copied into another reactive store. TOC declarations remain authoritative for account versus character scope. No SND-owned global database is introduced.

For domain SavedVariables, initially retain the existing loader/command/checkpoint owner. Validate and commit there, then publish a small read-only UI projection through a consumer-owned state store. A failed domain command must not publish a success projection. Treat a failed projection update as an integration error and reconcile from the authoritative model; this bridge is not a cross-store transaction. No module may mutate the same SavedVariables through both a legacy owner and SND.

The previously discussed `SavedVariables`/`Store` convenience registry is **not yet part of v0**. FAU recovery/capacity and XP checkpoint behavior require substantially different policies; a unified persistence adapter needs two complete migrations before its signatures are stable. Future-schema preservation, schema migrations, recovery records, character identity, and when to checkpoint remain explicit consumer responsibilities. Successful in-memory assignment never promises a disk flush; WoW controls persistence at logout/reload.

## 4. Profiles

```lua
app.profiles:BindCharacter(characterIdentity)
app.profiles:Switch("Shared")
app.profiles:Duplicate("Solo")
app.profiles:CopyFrom("Shared")
app.profiles:Reset()
```

| API | Contract |
| --- | --- |
| `profiles:List() -> names` | Defensive copy in deterministic display order. |
| `profiles:Active() -> name or nil` | Current named profile; single-settings adapters may return nil. |
| `profiles:Capabilities() -> descriptor` | Supported operations and current read-only/identity status. |
| `profiles:BindCharacter(identity)` | Adapter-defined character association, invoked only when the consumer has a valid identity. |
| `profiles:Switch(name)` | Select an existing profile. |
| `profiles:Duplicate(name)` | Copy the active profile into a new name and activate it. |
| `profiles:CopyFrom(name)` | Replace active settings from another profile, retaining the active name. |
| `profiles:Reset()` | Reset the active settings to validated defaults. |

Mutation methods return `boolean, error`, use the settings transaction path, and reject unsupported operations. Name rules, limits, character assignments, and migrations belong to the adapter. No delete/import/share API is proposed for v0.

Successful profile transitions close owned transient editors, invalidate callbacks bound to the old settings identity, cancel stale drag/resize gestures, commit, and refresh. Failed validation leaves the current profile and UI intact. Color previews live in an editor overlay; Okay commits once, Cancel discards. Closing or switching profiles cancels unaccepted previews without writing through old profile references. This improves the current add-ons' preview-then-rollback implementation and needs new tests.

A color control may supply a separate `preview(value)` repaint callback; cancellation sends the original value. `app:Get` and `OnSettingsChanged` remain committed-only. Consumers must not persist values from a preview callback. Editors snapshot the settings revision and reject an outdated commit if another write has replaced their starting state.

## 5. Options shell and controls

```lua
local options = app:Options({
    title = "Example",
    width = 640,
    height = 500,
    pages = {
        {
            id = "appearance", label = "Appearance",
            sections = {
                {
                    title = "Typography",
                    controls = {
                        { type = "font", key = "font", label = "Font" },
                        { type = "slider", key = "fontSize", label = "Font size", step = 1 },
                        { type = "slider", key = "scale", label = "Scale", format = "percent", step = 0.01 },
                        { type = "checkbox", key = "locked", label = "Lock position" },
                    },
                },
            },
        },
        SND.Pages.Profiles(),
    },
})
app:Slash("/example", function() options:Toggle() end)
```

`app:Options(spec) -> panel` returns a lazy shell. `panel:Open(pageID)`, `Close()`, `Toggle()`, `SelectPage(pageID)`, `Refresh()`, and `IsShown()` are the initial methods. Mutating methods return `boolean, error`. One options shell per app initially.

Pages have stable IDs and retain their own scroll offsets. Sections flow vertically with measured labels; there is no general CSS/grid engine in v0. The header, tabs, and close control remain accessible while the body scrolls on short screens. Narrow screens scale the shell as needed. Construction is retryable and reuses existing frame/text objects; a failed build is never published as a usable panel.

Initial controls: `checkbox`, `slider`, `number`, `text`, `select`, `font`, `color`, `button`, and `description`. Bound controls declare `key`; labels, hints, units, menu choices, and button actions come from the consumer. Numeric bounds come from the field schema; display formatting never changes stored units. `enabled(app)` and `visible(app)` are pure predicates. Reset/copy confirmation is supplied by the profile page, not by silently changing model semantics.

Custom escape hatch: `{ type = "custom", id = "preview", create = function(parent, app, scope) ... end }`. The factory returns a component with `Refresh()`, `Layout(width) -> height`, and `Hide()` methods. It creates children only under its supplied parent and owns callbacks through its supplied scope. Failed construction must be retry-safe; named components are reused, not rebuilt on every refresh.

Open menus are not regenerated underneath input. Selection/font changes queue menu regeneration until release. Page switches, hiding, and geometry changes close only owned menus, release edit focus, and cancel owned transient editors. Hiding options does not stop unrelated gameplay work.

## 6. UI, typography, and screen geometry

```lua
app.ui:Style(window, "dialog")
app.ui:Style(button, "button")
app.fonts:Apply(title, "heading")
app.fonts:Apply(label, "body")

local keep = app.layout:KeepOnScreen(window, { margin = 12 })
local placement = app.layout:PlacePopup(menu, button, {
    preferredSide = "right", fallbackSide = "left", margin = 8,
})
```

| API | Contract |
| --- | --- |
| `ui:Style(frame, role) -> boolean, error` | Apply named theme roles: `dialog`, `section`, `button`, `tab`, `input`. Idempotent; preserve caller content and scripts. |
| `ui:Border(frame, kind) -> boolean, error` | Explicit `default`, `none`, `tooltip`, `dialog`, or `thin` edge; preserve background and restore owned native edges. |
| `fonts:Apply(object, role) -> boolean, error` | Assign role family/size (`heading`, `body`, `muted`, `control`, `menu`). Semantic color is supplied by the theme; muted text need not be smaller. |
| `fonts:Entries() -> entries` | Stable font choices including unavailable saved preferences. |
| `fonts:Measure(text) -> width, height` | Measured in the text object's local UI units, using actual native font readback and effective scale. |
| `fonts:Refresh()` | Reconcile only invalidated font applications and measurements. |
| `layout:KeepOnScreen(frame, spec) -> handle, error` | Keep an owned, unprotected frame within usable UIParent bounds; recheck on geometry changes. |
| `layout:PlacePopup(popup, anchor, spec) -> handle, error` | Place beside an anchor, try the alternate side, then clamp; re-evaluate when visible geometry changes. |

Layout margins are UIParent logical units. Geometry calculations normalize effective scales before comparison; cursor pixels, local frame units, and UIParent units cannot be mixed. Screen awareness means usable UIParent bounds, including native notch handling, not hard-coded physical monitor dimensions. These helpers do not save placement, choose a dock side, show hidden frames, or override an active native drag. Handles support `Refresh()` and idempotent `Cancel()`.

Only add-on-owned, non-forbidden, unprotected frames are accepted for automatic geometry changes. SND does not silently defer protected mutations or promise taint safety. Blizzard frame suppression, combat policy, and product-specific placement rules remain consumer-owned.

Font application accepts native `SetFont` void returns when readback proves success. It handles missing media, late SharedMedia registration, fractional height readback, per-object rejection, and a final inherited native Font fallback. A family downgrade triggers a bounded remeasure pass across affected controls. Saved preferences remain unchanged. Font selection, probing, object creation, and text measurement do not belong in animation callbacks.

Initially the font service binds to the optional schema keys `font` and `fontSize`; absent keys use native defaults. Content roles may follow `fontSize`, while options control/menu roles retain readable fixed sizes. Committed font changes invalidate the service automatically. More elaborate role configuration is deferred until implementation establishes the common needs.

The initial theme uses the existing gray dialog border, dark controls, gold hover/selection accents, and native control artwork. App-specific font defaults and content sizing survive migration; adopting SND does not change ATCF's Expressway preference into XPIsland's tooltip font by accident.

## 7. Events, hooks, and scheduling

```lua
local scope = app:Scope("reward-preview")
scope:Event("GET_ITEM_INFO_RECEIVED", function(itemID, success)
    if success then ns.Preview:RefreshItem(itemID) end
end)
scope:After(0.15, "refresh", function() ns.Preview:Refresh() end)
scope:PostHook("QuestInfo_Display", function(template, parent)
    ns.Preview:Observe(template, parent)
end)
scope:Cancel()
```

| API | Contract |
| --- | --- |
| `scope:Event(event, callback) -> subscription, error` | Callback receives native payload only, without an injected event name or self. |
| `scope:PostHook(globalName, callback)` | Observe a global function through `hooksecurefunc`; receives original arguments, not return values. |
| `scope:PostHook(table, methodName, callback)` | Equivalent table-method overload; original self remains in the native argument list. |
| `scope:HookScript(frame, scriptName, callback)` | Additive script observer; receives native frame and arguments. Never replace another owner's script. |
| `scope:After(seconds, key, callback) -> handle, error` | Schedule once; the same key replaces earlier pending work in this scope. Zero means next-frame work. |
| `scope:Every(seconds, key, callback) -> handle, error` | Positive-period recurring work. Callback receives elapsed time; no catch-up burst after a stall. |
| `scope:Guard(callback) -> callback` | Wrap a callback for an external asynchronous API; becomes inert when the scope is canceled. |
| `scope:Cancel()` | Terminal and idempotent: remove owned subscribers, cancel work, invalidate guards, release callback references. |

All subscriptions and timer handles expose idempotent `Cancel()`. Cancellation during dispatch suppresses later callbacks belonging to canceled subscriptions. Registration never unregisters another add-on's events. Secure/script hooks cannot truly be removed: an inert dispatcher remains, with subscribers detached; repeated attach/detach must not stack native hooks.

There is no generic `Call(fn)` that discards errors or silently changes return arity. Scope guards reject obsolete owners, but request IDs, content identity, provider revisions, retry budgets, and which events invalidate data still belong to the add-on. Use a fresh scope for a new request generation where appropriate.

Recurring work uses an owned scheduler with no permanently ticking idle driver. Preserve authoritative add-on clocks and existing coalescing semantics when adopting it. Missing optional hook targets return `unavailable`; the consumer decides whether an `ADDON_LOADED` retry is warranted.

## 8. Diagnostics and value guards

```lua
app.log:Debug("Profile changed", { profile = "Solo" })
app.log:Warn("Selected font unavailable", { font = requested })
app.log:Error("Preview failed", { questID = questID })
```

`log:Debug`, `Info`, `Warn`, and `Error` append bounded records. `log:Entries()` returns a snapshot; `log:Clear()` clears this app's buffer; `log:SetLevel(level)` controls capture. Initial default: Info and above, 200 records, bounded message/field lengths, scalar context only, consecutive identical records coalesced with a count. Debug is opt-in. Logs are memory-only; chat output/export are explicit consumers, not automatic SavedVariables or upload behavior.

`SND.Values.Readable(value) -> boolean` and `SND.Values.Number(value) -> boolean` are the initial shared guards. Readability is checked before comparison/formatting; Number also rejects NaN and infinities. Guarding a table does not recursively validate its fields. Diagnostic serialization skips restricted values and never dumps arbitrary tables, frames, or full SavedVariables. The framework does not infer whether an ordinary readable value is sensitive.

This diagnostic service is **new work**: the current add-ons have messages and status fields, not an existing reusable logger. Gameplay recording (such as FAU reward observations) is not logging and stays outside SND.

## 9. Initial implementation gates

1. Extract theme/fonts and owned lifecycle primitives with tests before migrating consumers. Validate the small state contract using at least two concrete consumer integrations; retain all three design exercises as fixtures.
2. Build the retryable options shell and declarative bindings; preserve native menus and color-picker callback ordering.
3. Add profile adapters for each current schema without converting account/character scope.
4. Adopt screen helpers where coordinate contracts match; keep bespoke docking, animation, tooltip collision policy, and world-map projection outside the core.
5. Run the shared contract suite under Lua 5.1, each consumer's existing suite, mixed-version/coexistence tests, and the supported-client live checklist.

Required scenarios include future schemas, unavailable identity, failed construction/retry without frame growth, stale color callbacks, profile changes during dragging, late/missing fonts, menus open during refresh, fractional scales, narrow/short displays, repeated hook registration, timer replacement/cancellation, and hidden idle CPU. Source/mocks cannot establish native rendering, combat/taint safety, or actual coexistence.

Deferred: general widget DSL, layout engine, deep observable proxies, cross-store transactions, generic domain persistence registry, cache/query framework, automatic gameplay retries, profile import/export, docking, minimap launchers, tooltip inspection, and release tooling. Optional components can grow after two consumers demonstrate a shared contract.
