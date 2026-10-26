# Changelog

## 0.4.1

### Public API changes

**No public API changes.**

### Internal improvements

- Point agent guidance to native API definitions, source implementations and recovery tests.
- Explain how consumers discover guidance from their root AGENTS.md; remove the two-implementation requirement.
- Include documentation, examples, tests and tooling in the source package; keep WoW's runtime load order unchanged.

## 0.4.0

### Public API changes

**Breaking: `fonts:Apply` no longer changes text color.** Register a semantic color explicitly when it should follow the theme.

```lua
-- Before: typography also supplied the muted color.
local ok, err = app.fonts:Apply(label, "muted")
if not ok then return false, err end

-- After: typography and theme color have separate ownership.
local ok, err = app.fonts:Apply(label, "muted")
if not ok then return false, err end
local colored, colorError = app.ui:Color(label, "muted")
if not colored then return false, colorError end
```

**Default profiles and generated options.** New databases can omit the settings adapter. `Options()` generates Settings and Profiles pages; fields can supply a display `label`.

```lua
-- Before: supply a persistence adapter and explicit pages.
app:Settings({
    savedVariables = {"ExampleDB"},
    adapter = ns.SettingsAdapter,
    fields = {font = {type = "font", default = "Game tooltip"}},
})
local panel = app:Options({pages = ns.OptionsPages})

-- After: SND supplies storage and controls for a new database.
app:Settings({
    savedVariables = {"ExampleProfiles"},
    fields = {font = {type = "font", default = "Game tooltip", label = "Font"}},
})
local panel = app:Options()
```

Existing databases still require their migration adapters; omitting `adapter` does not convert a legacy schema. Explicit options pages remain supported.

**Atomic settings patches.** `SetMany(values, expectedRevision?)` validates and commits related fields together, with one revision and notification. Change records use reason `patch`; custom adapters must handle the corresponding operation.

```lua
-- Before: separate writes expose an intermediate position.
local ok, err = app:Set("window.x", x)
if not ok then return false, err end
local moved, moveError = app:Set("window.y", y)
if not moved then return false, moveError end

-- After: either both coordinates commit or neither does.
return app:SetMany({["window.x"] = x, ["window.y"] = y}, revision)
```

```lua
-- Before: Prepare receives a single-field operation.
local operation = {kind = "set", path = "window.x", value = x}

-- After: SetMany sends one patch to Prepare.
local operation = {kind = "patch", values = {["window.x"] = x, ["window.y"] = y}}
```

Adapters apply the complete patch to a copied candidate before returning it. Older adapters may reject unsupported patches; `Set` is unchanged.

**Shared themes and appearance observation.** Add `Appearance`, `SelectAppearance`, `ui:Color`, `ui:Themes` and the `SND.Themes.modern` / `forever` presets. Registered `ui:Style` surfaces now follow the selected theme. Declare an enum setting named `theme` to allow selection; custom definitions can supply renderer tokens.

```lua
-- Before: styling uses the framework's fixed palette;
-- the consumer coordinates custom palette and font-layout updates.
local ok, err = app.ui:Style(window, "dialog")
if not ok then return false, err end

-- After: declare before readiness; built-in themes are also the default.
app:Appearance({
    defaultTheme = "modern",
    themes = {modern = SND.Themes.modern, forever = SND.Themes.forever},
})
local ok, err = app.ui:Style(window, "dialog")
if not ok then return false, err end
local choices = app.ui:Themes() -- {label, value} entries for a select control
view:Watch(app:SelectAppearance(function(value) return value end), function(appearance)
    ns.UI:Layout() -- Consumer-owned geometry, after fonts settle.
end)
```

The appearance snapshot contains `themeID`, `theme` and `fontRevision`; standard options subscribe automatically. `Appearance` returns no value. Styling and color registration retain the Result tuple contract.

**Custom font sizing and emphasis.** `fonts:Apply` accepts optional `{size, flags}` and the new `emphasis` role. Explicit sizes survive refresh; emphasis tries the family's bold face, then regular with `OUTLINE`.

```lua
-- Before: custom sizes/flags require consumer-managed native application.
local path = label:GetFont()
label:SetFont(path, 18, "OUTLINE")

-- After: SND retains the sizing through font changes.
local ok, err = app.fonts:Apply(label, "body", {size = 18, flags = "OUTLINE"})
if not ok then return false, err end

-- Or request the new emphasis role instead of a fixed outline style.
local ok, err = app.fonts:Apply(label, "emphasis", {size = 18})
if not ok then return false, err end
```

### Internal improvements

- Recover shared font fallback after transient failures; explicit `fonts:Refresh()` retries resolution and appearance observers remeasure settled fonts.
- Support Escape dismissal, bounded button/dropdown captions and full-caption tooltips in the options shell.
- Report empty profile input without exceptions and clear superseded confirmations.
- Clear caption and hover state after failures, hiding or disabling; unwind partial hook registration before retrying.

## 0.3.0

### Public API changes

**No public API changes.** Existing method names, arguments and Result tuples are unchanged.

### Internal improvements

- Fix scoped logout delivery: callbacks run once before disposal while committed settings remain readable; callback or panel cleanup failures cannot stop remaining cleanup.
- Start font tracking on first use; keep measurement passive and detach replaced media callbacks.
- Keep layout listeners only while handles are active; roll back partial registration failures.
- Consolidate executable consumer checks under tests and remove redundant audit and test documents.

## 0.2.0

Breaking changes from the Lua correctness and developer-experience review:

- Fallible resource APIs (`Slash`, scoped events/hooks/timers, and layout helpers) now return `true, handle` or `false, error`. Previously they returned a handle or nil. Commands retain their boolean first result; successful commands have no payload.
- Both settings adapter methods return `true, { state = ..., saved = ... }` or `false, error`. Restore previously returned state and saved data separately; Prepare returned the candidate directly. Read-only restoration may omit saved data.
- Ordered declarations must be dense arrays. Scope names, revisions, timer keys, schema bounds and profile descriptors now reject malformed arguments explicitly. Validators require literal true for acceptance.
- Bound settings must be declared before Options; incompatible control/field types and missing slider bounds fail before panel registration.
- Declaration and adapter tables are copied at registration. Mutate settings through their commands; do not alter an options spec or adapter method table after registration. Callback upvalues remain consumer-owned.

Validated fixes:

- A selector returning extra Lua values could pass them into the snapshot copier's private arguments. Only the first result is now consumed.
- Sparse lists were silently truncated by ipairs. Invalid declarations now fail before registration and permit a corrected retry.
- Options/adapter tables were retained by reference. Later caller edits could corrupt an already registered panel or restoration path.
- Arbitrary error objects could invoke a throwing __tostring outside the recovery boundary. Errors are now normalized into fresh string-only records without metamethod invocation.
- Profile descriptors and non-finite/index arguments could fail deep inside unrelated code. They are checked at their boundaries.
- The example persistence adapter treated a saved false as missing data. It now preserves that invalid record and exposes read-only defaults.
- Immediate native event registration failures now return a failed Result, rather than a canceled handle that looked successful.
- Cleanup errors are reported without interrupting remaining owned cleanup.

Thirteen focused contract tests and the three real-runtime consumer mocks pass under Lua 5.1. Each focused test records its failure-risk justification in tests/run.lua. Native WoW acceptance remains outstanding.

## 0.1.0

Initial implementation of reactive state, settings/profile adapters, owned callbacks,
options panels, fonts, geometry and memory-only diagnostics.
