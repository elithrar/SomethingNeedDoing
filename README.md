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

Settings restore after `ADDON_LOADED`; player and world readiness remain the
add-on's responsibility. Existing databases need a
[migration adapter](examples/SettingsAdapter.lua). The TOC determines whether
saved profiles are account-wide or per-character.

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
shows custom themes and `SelectAppearance` observers for remeasuring custom views.

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

## Testing

With Lua 5.1 and Python 3 installed, run from the SND directory:

```sh
python3 tools/check.py
lua5.1 tests/run.lua
```

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
