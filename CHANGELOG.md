# Changelog

## 0.6.1

### Public API changes

- The built-in font selector previously drew every name in the menu font. Each choice now previews its own typeface. A missing font falls back to readable text.
- Options with a subheader gain a little space below the title and a thin divider above the form. Existing declarations pick up both changes automatically. No migration is required.

### Internal improvements

- Remove the circular indicator drawn by Forever’s native menu so selected choices show a single gold check.
- Run the framework and consumer checks with upstream Lua 5.1.4, the Lua release identified in the Forever client.

## 0.6.0

### Public API changes

- Previously, remembering an active profile per character required a custom adapter. Set `characterProfiles = true` on a fresh account-wide settings global, then call `profiles:BindCharacter(identity)` once the name and realm are available. New characters use Shared. An optional `initialProfile(fields)` seeds Shared from existing settings. `profiles:Characters(name?)` lists its known users. Existing adapters and ordinary profile databases need no migration.
- Generated sections fill across rows by default. Set `section.flow = "column"` to keep related controls in column order at wide and narrow widths. Existing forms retain their layout.
- Previously, only the right-hand header could stay visible above the form. Pass `subheader={width=180, create=createProfilePicker}` to place a scoped component directly beneath the title. Existing header declarations need no changes.
- Add-on menus can opt into Forever menu styling with `app.ui:StyleMenu(rootDescription)` after populating the menu. Forever options selectors use the same opaque surface, native hover and single gold selection mark. Existing menu generators need no migration.

### Internal improvements

- Copy a built-in profile database once when staging its active values. A valid account near the saved-data size limit can now switch characters and reload.
- Ignore menu clicks delivered after dismissal or after a newer menu replaces the choices. The current menu still handles native mouse-wheel selections.
- Exercise profile migration, character switching, menu reuse and responsive form layout in the offline suites.

## 0.5.10

### Public API changes

An open options panel now restores its selected page, controls and preview when the game interface reappears. Previously the shell could return with an inactive page. Calling `panel:Open(pageID)` while the interface is hidden remembers the requested page and activates its components on reveal. Calling `panel:Close()` before then cancels the pending open. Signatures and saved data formats are unchanged. No migration is required.

### Internal improvements

- Restore each declared SavedVariables global with the same size and depth limits used to save it. Previously, individually valid globals could prevent the add-on from starting on the next login.
- Preserve the original profile database when a nested setting encounters a malformed parent, including an explicit `false`.
- Keep unrelated version 1 data intact when the example settings adapter edits or resets its declared fields.
- Release a canceled slash command even after Forever has imported it. The same spelling can be registered again, and a saved reference to the old handler stays inert.
- Show the committed checkbox or slider value after an adapter rejects or normalizes a change.
- Restore a transient color preview as soon as another add-on takes over the shared color picker.
- Reuse the timer dispatch order while a set of timers is running. Adding, replacing or canceling a timer still takes effect at the same point in the frame.
- Exercise SpellStats’ slash command, font-size slider and spell preview in consumer CI. Check release tags against the runtime version and changelog.

## 0.5.9

### Public API changes

Custom controls now release their subscriptions when their visibility predicate hides them. Previously those subscriptions could last until the page closed. Showing the control again calls its factory with the same parent and a fresh component scope. Existing factories can keep their signatures and rebind callbacks to the scope they receive.

### Internal improvements

- Keep literal page and control IDs distinct from the IDs of generated tabs and fields, including when IDs contain colons or percent signs.
- Restore the committed slider position when the settings adapter rejects a drag.
- Retain registered font roles through a transient native font error so the next refresh can recover.
- Reuse the Modern close button and finish its setup when the options window opens again after a construction error.

## 0.5.8

### Public API changes

**No public API changes.**

### Internal improvements

- Top-align the options title and header preview so a tall preview keeps the title at its usual inset. The preview moves below the title when space is tight.

## 0.5.7

### Public API changes

- A slider previously displayed its formatted value beside the track. Add `editable = true` to let users type a value in stored units and press Enter to save it.
- Custom components previously appeared in page sections. Pass `header = {width = 46, create = createPreview}` to `app:Options` to keep one beside the title while the body scrolls. The factory uses the same `Refresh`, `Layout` and `Hide` methods as a page component.

Both additions are optional. Existing declarations need no migration.

### Internal improvements

- Use Blizzard’s standard red close button on Forever-themed options windows.

## 0.5.6

### Public API changes

Single-page options declarations now open directly on their controls. Panels with multiple pages still show navigation tabs. Existing declarations work without migration.

### Internal improvements

- Give the Forever window its native dialog trim and use game artwork for its slider track and thumb.
- Left-align dropdown selections in the Forever preset and keep each slider’s formatted value beside its track.
- Give fitted pages equal side margins and reserve the scrollbar gutter when content overflows.

## 0.5.5

### Public API changes

Previously, a failed screen-position tracker could abort the first `panel:Open()`. The options window now falls back to native screen clamping and opens with its controls available. Calls and return signatures are unchanged. No migration is required.

### Internal improvements

- Include the failed event or frame script in tracker attachment diagnostics.
- Exercise opening options through a slash command, closing the panel, and reopening it on clients that refuse duplicate event registration or a layout hook.

## 0.5.4

### Public API changes

A scoped subscriber now reuses an event already registered on the app frame. Previously, a client that refused repeat registration could reject the subscription. Existing callers need no migration.

### Internal improvements

- A refused bootstrap or logout registration reports the event and releases the partial registration so creation can be retried.
- Exercise shared subscriptions and app lifecycle events with a frame that refuses duplicate registrations.

## 0.5.3

### Public API changes

Calls and schemas are unchanged; no migration is required. Before, an already-default `profiles:Reset()`, equal-value `CopyFrom()`, or same-profile `Switch()` could leave previews and gestures alive. After, every successful profile command advances the settings revision and emits `OnSettingsChanged`, even with empty `change.keys`. Use `change.reason` for gesture invalidation; `profileChanged` retains its identity/bind meaning. Equal-value `Set`/`SetMany` and value-only selectors remain deduplicated.

`layout` handle `Refresh()` now returns `false, {code="unavailable", message=...}` for native failures or unresolved geometry instead of throwing. Check the existing Result and retry when geometry is available. `scope:Event()` now also returns `unavailable` when native registration returns false, without retaining a subscriber; the existing Result check remains valid.

### Internal improvements

- Reject dropdown responders from obsolete settings revisions or canceled pages, including profile menus.
- Resume containment after hiding during a drag; guard reentrant placement and validate readable dimensions/scales before arithmetic or clearing anchors.
- Add five regression contracts demonstrated failing before the fixes, and run all 34 contracts on Lua 5.1 and LuaJIT. Run commit-pinned consumer domain checks in CI.
- Include the 0.5.2 fix preserving Blizzard's slash registry, previously available as a tag. Native rendering, input and combat/taint checks remain separate from offline evidence.

## 0.5.2

### Public API changes

`app:Slash` calls and successful Results are unchanged. When Blizzard's command registry is missing, registration now returns `false, {code="unavailable", message=...}` instead of creating a replacement global. Keep the existing registration Result check; no migration is needed.

### Internal improvements

- Stop reassigning Blizzard's `SlashCmdList` global during registration. Even a same-value assignment can taint native chat dispatch and block protected commands such as `/pvp`.
- Retain the native registry for registration and cancellation, touching only the add-on's entries.
- Cover global-write rejection, readiness, cancellation and missing-registry recovery. Offline tests detect the unsafe write; final combat/taint behavior still requires the game client.

## 0.5.1

### Public API changes

**No public API changes.** Existing options declarations and commands need no migration. Previously tab selection hid/reopened the shell, and a native cleanup failure could leave the named page scope active; a later open then raised `scope name already active`. Tabs now replace the page in place, and reopening cancels any stale view before attaching a fresh private scope. Recursive opens/page switches return a failed Result during the active transition.

### Internal improvements

- Cancel and detach page observers before native editor/menu cleanup; report cleanup errors while continuing to release the remaining resources.
- Close only open dropdown menus, avoiding native selection updates on already-closed controls.
- Guard reentrant transitions and clean up partially opened pages after native show or observer failures.
- Reproduce the reported scope-collision error against 0.5.0 and cover interrupted hide, native cleanup failure, tabs, settings writes, repeated reopening and frame reuse.

## 0.5.0

### Public API changes

Add shared `ui:Control`, `layout:Row` and `layout:Columns` APIs for generated options and custom views. Previously custom views had to select native templates, activate input and manually place every field. Now they can request a stable parent/id control and call `layout:Row(parent, {width=480, label=label, control=control})`, checking both Results. `layout:Columns` returns count/width directly. Controls retain consumer-owned values and callbacks; no persistence migration is needed.

Options now accept panel/section `layout` declarations and per-control `width`; buttons accept `align`. Before, all fields used a fixed 230-unit column and sections were single-column. After, `layout={columns=2,minColumnWidth=220}` creates responsive sections, `{type="color",key="tint",label="Tint",width=36}` keeps a compact aligned swatch, and `align="stretch"` creates grouped action rows. Defaults preserve existing declarations.

With calls unchanged, narrow screens now reflow the panel instead of shrinking it; long captions wrap at the selected font size and increase row height. Custom component Layout methods now reject non-finite/negative heights. These are compatible additions with presentation changes, not a saved-data or signature migration. Existing custom views may opt into the shared constructors and geometry incrementally. See API.md and the updated executable example for ownership and error handling.

### Internal improvements

- Use one measured row implementation for bound fields, checkbox labels, descriptions and actions; include labels in checkbox hit regions.
- Reflow section columns and navigation at the available width while reusing frames and preserving page scroll offsets.
- Grow profile action rows around wrapped captions and retain the native input/menu lifetimes.
- Exercise public construction recovery, disabled state, focus release, compact controls, long captions, viewport changes and hide/reopen. Native rendering and mouse routing still require in-game checks.

## 0.4.3

### Public API changes

**No public API changes.** Existing color declarations now render as labeled swatches aligned with neighboring fields, instead of action buttons in the label column.

### Internal improvements

- Explicitly enable mouse input for owned options controls and register left-button clicks for tabs, actions and checkboxes.
- Report failed tab commands and exercise tab/close clicks through an input-aware fixture, including hide/reopen.
- Keep saved color swatches in sync after acceptance, cancellation and page changes.

## 0.4.2

### Public API changes

Existing options declarations need no migration. Untitled sections previously reserved a blank heading row; now they flow without one. Wide fields now place the label beside the control, and the selected tab has an accent underline.

Profile page sections previously did not render; now they follow the built-in commands:

```lua
-- Before: built-in profile commands only.
local profiles = SND.Pages.Profiles()
-- After: optionally append ordinary sections.
profiles.sections = {{controls={{type="description", text="Profiles store appearance."}}}}
```

Existing custom panels can now share native control styling with `ui:Style(frame, "dropdown" | "checkbox" | "slider" | "scrollbar")`; see API.md for required frame templates. Previously those panels had to maintain their own decorative textures.

### Internal improvements

- Theme dropdown, checkbox, input, slider and scrollbar chrome consistently while retaining native menu behavior.
- Dim disabled controls, measure field labels and avoid empty heading rows.
- Keep native dropdown state changes in the active palette; reuse partial control artwork after construction failures.
- Stack profile actions in narrow panels and preserve visible controls during value refresh, so slider drags are not interrupted.
- Verify page reuse, profile sections, compact rows and selected-tab state offline. Native input and rendering still require client verification.

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
