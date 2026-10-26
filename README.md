# SomethingNeedDoing

[![Tests](https://github.com/elithrar/SomethingNeedDoing/actions/workflows/test.yml/badge.svg)](https://github.com/elithrar/SomethingNeedDoing/actions/workflows/test.yml)

SomethingNeedDoing (SND) is a microframework for building World of Warcraft
add-ons. It provides the parts you tend to write more than once:

- Options panels with bound controls, tabs, profiles, fonts and window chrome.
- A small state API for updating a model and propagating changes to its views.
- Scoped events, hooks and timers that stop calling your code when their owner
  goes away.
- Settings adapters for existing SavedVariables, slash commands, screen bounds
  and bounded logging.

The goal is to make those parts consistent and easy to use, while leaving the
add-on's behavior in the add-on. SND grew out of
[XPIsland](https://github.com/elithrar/XPIsland),
[FindAnUpgrade](https://github.com/elithrar/FindAnUpgrade) and
[AsTheCrowFlies](https://github.com/elithrar/AsTheCrowFlies): three different
consumers with enough shared plumbing to justify a small library.

Version **0.3.0** targets **WoW Forever, interface 16001, and Lua 5.1**. It has no
required third-party dependencies. LibSharedMedia is used when available.

## Contents

- [Installation](#installation)
- [Examples](#examples)
- [API](#api)
- [Design Notes](#design-notes)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Installation

Copy `src/`, `Embed.xml` and `LICENSE` into
`YourAddon/Libs/SomethingNeedDoing/`, and load SND before your add-on's modules:

```text
## Interface: 16001
## Title: YourAddon
## SavedVariables: YourAddonDB
Libs\SomethingNeedDoing\Embed.xml
SettingsAdapter.lua
Core.lua
```

Pin the SND version or commit you ship. Each add-on gets its own instance,
loaded into the namespace WoW supplies to its files. Users don't need to install
SND separately, and one add-on updating its copy doesn't update another's.

[package.json](package.json) records the version, license, author and Lua load
order. It's metadata: you don't need Node.js, npm or LuaRocks to use SND in WoW.

## Examples

### An options panel

Here's the common case: a couple of saved settings and a panel to edit them.
Copy [examples/SettingsAdapter.lua](examples/SettingsAdapter.lua) to the
`SettingsAdapter.lua` entry in the TOC above, then put this in `Core.lua`:

```lua
local ADDON, ns = ...
local app = ns.SomethingNeedDoing:NewAddon(ADDON)

app:Settings({
    savedVariables = { "YourAddonDB" },
    adapter = ns.CreateSettingsAdapter("YourAddonDB"),
    fields = {
        scale = { type = "number", default = 1, min = 0.5, max = 2 },
        font = { type = "font", default = "Game tooltip" },
    },
})

local options = app:Options({
    title = "YourAddon",
    pages = {{
        id = "appearance", label = "Appearance",
        sections = {{
            title = "Appearance",
            controls = {
                { type = "slider", key = "scale", label = "Scale", step = 0.05 },
                { type = "font", key = "font", label = "Font" },
            },
        }},
    }},
})

local registered, err = app:Slash("/youraddon", function()
    local opened, failure = options:Toggle()
    if not opened then app.log:Warn(failure.message) end
end)
if not registered then app.log:Warn(err.message) end
```

The controls read their bounds and defaults from the field declarations. A
successful edit validates and commits the setting before notifying its views.
You can observe those same settings to update the rest of your add-on:

```lua
app:OnReady(function()
    local view = app:Scope("appearance")
    view:Watch(app:SelectSettings(function(values)
        return values.scale
    end), function(scale)
        ns.window:SetScale(scale) -- Your add-on's owned, unprotected window.
    end)
end)
```

`OnReady` runs after the add-on's SavedVariables have been restored. It doesn't
mean that player identity or world APIs are ready; those still belong to your
add-on's initialization.

The example adapter handles one settings table. For an existing add-on, provide
an adapter for its existing schema and migrations. SND doesn't choose whether
your settings are account-wide or per-character: your TOC does.

### Updating state

SND's state API has an explicit flow: `Update → Select → Watch`. An update
publishes one coherent snapshot; a watcher only runs when its selected value
changes.

```lua
local search = app:State({ query = "", searching = false, results = {} })

app:OnReady(function()
    local view = app:Scope("search-view")
    view:Watch(search:Select(function(value)
        return { searching = value.searching, results = value.results }
    end), function(value)
        ns.SearchUI:Render(value)
    end)

    -- Cancel this scope when the view closes. Create a fresh one on reopen.
    ns.SearchUI:SetOnClose(function() view:Cancel() end)
end)

local ok, err = search:Update(function(draft)
    draft.query = "Ironforge"
    draft.searching = true
    draft.results = {}
end)
if not ok then
    app.log:Warn("Could not update search", { code = err.code })
end
```

`SearchUI` and its close callback are consumer code. The watcher receives the
current value when activated, so a reopened view catches up immediately. Small
selected tables compare by value; returning a fresh table doesn't force a
redraw when its contents are unchanged.

Keep your catalog, route graph or XP history in its existing model. Publish the
small amount of state the UI needs after a domain operation succeeds.

### Owning callbacks

Use a scope when several callbacks belong to the same view or operation:

```lua
local preview = app:Scope("reward-preview")
local subscribed, err = preview:Event("GET_ITEM_INFO_RECEIVED", function(itemID, success)
    if success then ns.Preview:RefreshItem(itemID) end
end)
if not subscribed then app.log:Warn(err.message) end

local scheduled, timerOrError = preview:After(0.15, "refresh", function()
    ns.Preview:Refresh()
end)
if not scheduled then app.log:Warn(timerOrError.message) end

-- Closing the preview cancels its subscriptions and pending work.
-- Call preview:Cancel() from the preview's close handler.
```

Scheduling another `After` with the same key replaces the pending callback.
Scopes also own recurring timers, additive hooks and guards for external async
callbacks. Secure hooks can't be removed from WoW; cancellation detaches your
subscriber from an inert dispatcher.

Scoped `PLAYER_LOGOUT` callbacks run once before disposal, while committed
settings remain readable. Use them for consumer-owned checkpoints or native
timer cleanup. SND then cancels owned work, including work scheduled during logout.

## API

The [API reference](API.md) covers signatures, errors and lifecycle details.
The main entry points are:

| Area | API |
| --- | --- |
| Bootstrap | `NewAddon`, `OnReady`, `IsReady` |
| State | `State`, `Read`, `Update`, `Select`, `scope:Watch` |
| Settings | `Settings`, `Get`, `Set`, `SelectSettings`, profile commands |
| Options | `Options`, `Open`, `Close`, `SelectPage`; controls bind by `key` |
| Ownership | `Scope`, `Event`, `PostHook`, `HookScript`, `After`, `Every`, `Guard`, `Cancel` |
| Presentation | `ui:Style`, `ui:Border`, `fonts:Apply`, `fonts:Measure`, layout helpers |
| Diagnostics | `Slash`, `log:Debug`, `Info`, `Warn`, `Error` |

Custom options components receive a positioned parent and a scope for the visible
page. Implement `Refresh`, `Layout(width)` and `Hide`, and reuse your frames when
the page opens again. You don't need a separate UI binding language.

### Handling errors

Fallible operations use a small Result tuple: `true, value` or `false, error`.
Commands return `true, nil`; operations that create a timer, hook or layout
handle return that handle as the second value:

```lua
local ok, timer = preview:After(0.15, "refresh", function() ns.Preview:Refresh() end)
if not ok then
    app.log:Warn(timer.message, { code = timer.code })
    return
end
-- timer:Cancel() cancels this operation; preview:Cancel() cancels the whole scope.
```

Errors have a stable `code` and a diagnostic `message`. Invalid declarations and
wrong argument shapes raise programmer errors. Async callback exceptions are
reported through diagnostics and WoW's error handler. Getters and infallible
registrations keep their direct return values. See the
[full contract](API.md#result-and-exception-contract) and
[0.2 migration notes](CHANGELOG.md) before upgrading a 0.1 consumer.

## Design Notes

A few decisions are worth making explicit:

- **One owner for settings.** Observe committed settings with `SelectSettings`;
  don't copy them into a second mutable store. Profile changes and field writes
  use the same transaction path.
- **Explicit propagation.** There are no observable proxies or inferred
  dependencies. If quest metadata changes without changing the quest IDs,
  publish that dependency explicitly. Request generations and cache policy stay
  with the consumer.
- **Success means committed.** Invalid updates leave the previous state intact.
  Reentrant writes from a watcher fail rather than queue invisibly. Schedule an
  intentional follow-up through the existing scope scheduler.
- **Small snapshots.** State uses defensive copies and structural equality.
  Trees are bounded at 32 levels and 20,000 entries per copy; those are safety
  limits, not an invitation to put a quest database in a reactive store.
- **Persistence stays deliberate.** Settings adapters stage changes before
  replacing globals and preserve unknown future schemas. Domain checkpoints
  remain consumer-owned. Assigning SavedVariables doesn't force a disk flush.
- **Native UI has its own lifecycle.** Open menus keep input ownership, color
  previews remain transient, and protected frames aren't automatically moved.
- **Every interface needs at least two implementations.** Shared APIs should
  earn their place through concrete consumers. The three-add-on exercise is how
  we check that, rather than adding abstractions for hypothetical add-ons.

SND doesn't own gameplay state machines, world-map geometry, animation clocks or
provider data. Those are the parts that make your add-on your add-on.

## Testing

With Lua 5.1 and Python 3 installed, run:

```sh
python3 tools/check.py
lua5.1 tests/run.lua
lua5.1 tests/consumers.lua
```

The focused contract suite is self-contained. Each test includes a short
justification explaining the failure it prevents. The metadata check catches
version, load-order and local documentation-link drift.

The optional [consumer checks](tests/consumers.lua) require sibling checkouts of
XPIsland, FindAnUpgrade and AsTheCrowFlies. They load real domain modules with
mock controllers and UI. They are design evidence, not complete migrations of
the add-ons' settings or options. Source baselines are recorded beside the checks.

If you're using Python with Lupa instead of a Lua executable, use
`python tests/run.py` and `python tests/run.py tests/consumers.lua`. Both select
Lua 5.1 explicitly. CI runs the self-contained suite; it doesn't require access
to private consumer repositories.

Offline contract and consumer-mock checks cover the runtime. Native rendering,
menu/picker input, combat restrictions and mixed-version coexistence still need
in-game acceptance on the target client. The mocks aren't migrations of the
shipping add-ons.

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
