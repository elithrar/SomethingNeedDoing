# SomethingNeedDoing

[![Tests](https://github.com/elithrar/SomethingNeedDoing/actions/workflows/test.yml/badge.svg)](https://github.com/elithrar/SomethingNeedDoing/actions/workflows/test.yml)

SomethingNeedDoing (SND) is a microframework for building World of Warcraft
add-ons. It provides:

- Options panels with bound controls, tabs, profiles, fonts and window chrome.
- Reactive state that propagates changes to views.
- Scoped events, hooks and timers.
- SavedVariables adapters, slash commands, screen bounds and logging.

SND grew out of [XPIsland](https://github.com/elithrar/XPIsland),
[FindAnUpgrade](https://github.com/elithrar/FindAnUpgrade) and
[AsTheCrowFlies](https://github.com/elithrar/AsTheCrowFlies).

**Targets World of Warcraft Forever only.** No required dependencies;
LibSharedMedia is optional.

## Contents

- [Installation](#installation)
- [Examples](#examples)
- [API reference](API.md)
- [Design Notes](#design-notes)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Installation

Vendor a pinned SND source tree into `YourAddon/Libs/SomethingNeedDoing/`.
Load `Embed.xml` before your add-on's modules in its TOC:

```text
## Interface: 16001
## Title: YourAddon
## SavedVariables: YourAddonDB
Libs\SomethingNeedDoing\Embed.xml
Core.lua
```

For agent-assisted development, point your root `AGENTS.md` to the vendored
[API.md](API.md) and [AGENTS.md](AGENTS.md). Keep them at the same pinned revision.

## Examples

For the full API reference, see [API.md](API.md).

### An options panel

Declare settings and SND supplies the controls and Profiles page. In `Core.lua`:

```lua
local ADDON, ns = ...
local app = ns.SomethingNeedDoing:NewAddon(ADDON)

app:Settings({
    savedVariables = { "YourAddonDB" },
    fields = {
        scale = { type = "number", default = 1, min = 0.5, max = 2 },
        font = { type = "font", default = "Game tooltip" },
    },
})

local options = app:Options()
local registered, err = app:Slash("/youraddon", function()
    local opened, failure = options:Toggle()
    if not opened then app.log:Warn(failure.message) end
end)
if not registered then app.log:Warn(err.message) end
```

Hiding the game interface pauses the options page and its preview. Showing the
interface again restores the selected page unless the panel was closed.

Slash registration uses Blizzard's existing command registry. It returns an
`unavailable` Result if that registry is missing; it never creates or replaces it.

Settings restore after `ADDON_LOADED`; player and world readiness remain the
add-on's responsibility. Existing databases need a
[migration adapter](examples/SettingsAdapter.lua). The TOC determines whether
saved profiles are account-wide or per-character.

To let alts share a preset while remembering individual selections, declare a
fresh account-wide global and set `characterProfiles = true`. Bind a stable
character name and realm once the player is known. New characters use Shared.
`app.profiles:Duplicate(name)` copies the active settings and selects the copy
for the bound character. `app.profiles:Characters()` lists who uses it.
The [character profiles example](examples/CharacterProfiles.lua) shows the login path.

Successful profile commands invalidate old edits even if their values are
unchanged. Custom movers should use `OnSettingsChanged` and the operation
`reason` to cancel gestures on reset/copy/switch; value-only watchers remain
deduplicated. Built-in menus and color editors reject stale callbacks.

### Appearance

Modern and WoW Forever themes apply across owned UI surfaces. Register frames,
fonts and semantic colors separately so font changes preserve product colors:

```lua
local styled, styleError = app.ui:Style(ns.window, "dialog")
if not styled then app.log:Warn(styleError.message) end

local applied, fontError = app.fonts:Apply(ns.title, "heading")
if not applied then app.log:Warn(fontError.message) end

local colored, colorError = app.ui:Color(ns.title, "accent")
if not colored then app.log:Warn(colorError.message) end
```

A `theme` setting selects the palette. The [executable example](examples/Consumer.lua)
shows custom themes, shared checkbox styling and `SelectAppearance` observers for remeasuring custom views. Custom options panels can use the `dropdown`, `checkbox`, `slider` and `scrollbar` style roles; see [API.md](API.md) for their native frame/template requirements.

For your own dropdown or context menu, call `app.ui:StyleMenu(rootDescription)` after adding its rows in the native generator. The Forever preset gives the popup an opaque background and marks the active choice with a gold check. Font selectors render each choice in its own typeface. Right-click the preview in the executable example to try the menu styling.

## Design Notes

**Settings have one writer.** Commands validate before publishing; views observe
committed settings. `SetMany` commits related fields together:

```lua
local ok, err = app:SetMany({ scale = 1.25, font = "Game tooltip" })
if not ok then app.log:Warn(err.message) end
```

**State propagation is explicit.** `Update → Select → Watch` publishes one
snapshot and redraws only when the selection changes:

```lua
local state = app:State({ count = 0 })
local view = app:Scope("counter")
view:Watch(state:Select(function(value) return value.count end), function(count)
    ns.Counter:SetText(count)
end)
local ok, err = state:Update(function(draft) draft.count = draft.count + 1 end)
if not ok then app.log:Warn(err.message) end
```

**Callbacks have an owner.** Cancel a view's scope when it closes to release its
subscriptions and pending timers. Reusing a timer key replaces pending work:

```lua
local ok, err = view:After(0.15, "refresh", function() ns.UI:Refresh() end)
if not ok then app.log:Warn(err.message) end
-- In the view's close handler:
view:Cancel()
```

Options reflow fields, section columns and tabs at the available width, preserving readable text. Captions wrap to fit. A single-page declaration opens directly on its controls. Sliders show their current value beside the track. The options window uses native screen clamping if its position tracker cannot attach. Tabs switch page content without closing the shell; interrupted cleanup does not leave the page lifetime registered or block reopening. Omit a section title for an uninterrupted list; assign `sections` to `SND.Pages.Profiles()` to append addon-specific shortcuts below its profile commands. See [the executable consumer](examples/Consumer.lua).

## Testing

CI and local checks use upstream PUC Lua 5.1.4 and Python 3. To build the
interpreter and compiler locally, unpack the official source archive, run
`make generic` in its directory, and put its `src` directory first on
`PATH`. [Lua 5.1.4 source](https://www.lua.org/ftp/lua-5.1.4.tar.gz)

From the SND directory, check that both version commands print `Lua 5.1.4`,
then run the syntax and contract checks.

```sh
lua -v
luac -v
python3 tools/check.py
find src tests examples -name '*.lua' -exec luac -p {} +
lua tests/run.lua
```

Consumer checks exercise
pinned XPIsland, FindAnUpgrade and AsTheCrowFlies modules and open SpellStats
options through its slash command. With those four repositories checked out
as siblings, run `lua tests/consumers.lua` locally.
These are offline logic/lifecycle checks; native rendering, input, combat/taint
and in-game performance still need the Forever client.

## Contributing

I'm trying a new way of accepting contributions on this repository, because the
variance in pull requests based on people's ability to prompt, review, and even
the model they're using generates a dramatic review burden. Instead:

**If you want to contribute to this, you should open an issue and concisely describe
the problem you're running into, and the feature you want to add or bug you want
to fix that solves it. If you've tested this out on a local copy, include the
concise prompt that you used, including any file changes that resolved this.**

In fact, I recommend simply copying this contributing section, or telling your
agent to follow this contribution guide when opening an issue.

**The goal here is that your problem, feature/bug, and prompt should be an input
into my agent instead, so that I can more carefully curate what gets added here
and ensure that documentation, AGENTS.md, and all tooling are moving in lockstep.**

I simply can't guarantee that a pull request is going to do all these things,
and it's often easier these days to address somebody's challenges from scratch,
or from good inputs rather than trying to review their outputs and fix them.

## License

Apache 2.0 licensed. See the [LICENSE](LICENSE) file for details.

### Shared form geometry

Set `layout` on an options panel or section; compact controls keep their place in the field column:

```lua
local panel = app:Options({layout={fieldWidth=220, minLabelWidth=160}, pages={
    {id="appearance", label="Appearance", sections={
        {controls={
            {type="color", key="tint", label="Tint", width=36},
            {type="slider", key="fontSize", label="Font size", editable=true},
        }},
        {layout={columns=2, minColumnWidth=200}, controls={
            {type="button", label="Preview", align="stretch", action=function() preview:Show() end},
            {type="button", label="Hide preview", align="stretch", action=function() preview:Hide() end},
        }},
    }},
}})
```

Set `flow="column"` on a section to keep each column’s controls together when the panel narrows. Declare bound settings first. Custom panels can use `ui:Control(parent, id, kind)` for reusable native controls, `layout:Row(parent, spec)` for measured placement, and `layout:Columns(width, spec)` for responsive columns. Check construction/row Results; column calculation returns count and width directly. Values, menus and callbacks remain with the consumer. See [the form API](API.md#form-layout-and-custom-controls) and [executable example](examples/Consumer.lua).

The font-size slider accepts an exact value with Enter. To keep a live sample visible while scrolling, pass `header={width=44, create=createFontSample}` to `app:Options`. The sample aligns with the top of the title and moves below it on narrow windows. The factory receives a pooled parent, the app and a fresh component scope on each reveal. Bind events to that scope so hidden components stop receiving updates. Its component implements `Refresh()`, `Layout(width)` and `Hide()`. The font sample appears on both pages of the [executable example](examples/Consumer.lua). Add `subheader={width=180, create=createProfilePicker}` to keep a compact selector beneath the title as the page scrolls. A thin divider separates the header from the form.
