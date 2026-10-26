-- Run from repository root with sibling checkouts at the audit revisions.
local T = dofile("exercises/state_model.lua")
local count = 0
local function check(condition, message)
    assert(condition, message); count = count + 1
end
local function loadAddon(name, files)
    local ns = {}
    for _, file in ipairs(files) do
        assert(loadfile("../" .. name .. "/" .. name .. "/" .. file))(name, ns)
    end
    return ns
end

-- XPIsland: use the actual XP model; publish only a small display projection.
local XP = loadAddon("XPIsland", { "Model.lua" }).Model
local tracker = XP.NewTracker(XP.NewSession("fixture", 100))
tracker:Sample(10, 100, 1000, "unknown", 1, false)
local display = T.State({ xp = tracker.xp, cap = tracker.cap, level = tracker.level })
local paints, scope = 0, T.Scope()
scope:Watch(display:Select(function(s) return { xp = s.xp, cap = s.cap } end), function()
    paints = paints + 1
end)
check(paints == 1, "XP: initial render")
tracker:Sample(10, 150, 1000, "unknown", 2, false)
check(display:Update(function(s) s.xp, s.cap, s.level = tracker.xp, tracker.cap, tracker.level end), "XP: publish")
check(paints == 2 and display:Read().xp == 150, "XP: model sample reaches UI")
display:Update(function(s) s.level = 11 end)
check(paints == 2, "XP: fresh projection table must not trigger unchanged fields")
local _, revision = display:Read()
display:Update(function(s) s.xp = 200 end)
local ok, reason = display:Update(function(s) s.xp = 999 end, revision)
check(not ok and reason == "stale" and display:Read().xp == 200, "XP: stale editor rejected")
scope:Cancel(); local before = paints
display:Update(function(s) s.xp = 250 end)
check(paints == before, "XP: closed view is detached")
local reopened = T.Scope()
reopened:Watch(display:Select(function(s) return s.xp end), function(value) paints = value end)
check(paints == 250, "XP: reopening reads latest state")

-- FAU: actual SavedVariables recovery/capacity model remains the authority.
local FAU = loadAddon("FindAnUpgrade", { "Model.lua", "Shortlist.lua" })
local shortlist = FAU.Shortlist
local legacy = { ids = { 101, 101, 102 } }
local normalized = shortlist:Load(legacy)
check(normalized.recovery == legacy and #shortlist:IDs() == 2, "FAU: preserve legacy recovery")
local search = T.State({ ids = shortlist:IDs(), metadataRevision = 0, query = "" })
local refreshes, view = 0, T.Scope()
local selection = search:Select(function(s) return { ids = s.ids, metadataRevision = s.metadataRevision } end)
view:Watch(selection, function() refreshes = refreshes + 1 end)
search:Update(function(s) s.query = "sword" end)
check(refreshes == 1, "FAU: unrelated field does not refresh this projection")
search:Update(function(s) s.metadataRevision = s.metadataRevision + 1 end)
check(refreshes == 2, "FAU: same IDs, changed context must refresh")
check(shortlist:Toggle(103), "FAU: domain command")
search:Update(function(s) s.ids = shortlist:IDs() end)
check(refreshes == 3 and #search:Read().ids == 3, "FAU: successful domain write propagates")
local future = { schemaVersion = 99, ids = { 999 } }
shortlist:Load(future)
check(not shortlist:Toggle(104) and future.ids[1] == 999, "FAU: future schema preserved")
view:Cancel(); before = refreshes
search:Update(function(s) s.metadataRevision = s.metadataRevision + 1 end)
check(refreshes == before, "FAU: hidden view does no render work")
T.Scope():Watch(selection, function() refreshes = refreshes + 1 end)
check(refreshes == before + 1, "FAU: hidden invalidation visible on reopen")
local oversized = {}; for i = 1, 21 do oversized[i] = i end
shortlist:Load({ schemaVersion = 1, ids = oversized })
check(not shortlist:Toggle(22) and shortlist:Remove(1), "FAU: capacity is an addition rule, not blanket validation")

-- ATCF: real navigation model is separate from search/comparison state.
local ATCF = loadAddon("AsTheCrowFlies", { "Model.lua", "Navigation.lua" })
local nav = ATCF.Navigation.New()
local origin, destination = { x = 0, y = 0, map = 1 }, { x = 100, y = 0, map = 1 }
check(ATCF.Navigation.Start(nav, { legs = {{ mode = "walk", start = origin, finish = destination }}, destination = destination }, origin, 0), "ATCF: start real route")
local planning = T.State({ generation = 0, query = "", searching = false, matches = {} })
local renders, planningView = 0, T.Scope()
planningView:Watch(planning:Select(function(s) return { searching = s.searching, matches = s.matches } end), function(s)
    renders = renders + 1
    check(not s.searching or #s.matches == 0, "ATCF: no partially updated search UI")
end)
local function begin(query)
    planning:Update(function(s) s.generation = s.generation + 1; s.query = query; s.searching = true; s.matches = {} end)
    local generation = planning:Read().generation
    return function(matches)
        if generation ~= planning:Read().generation then return false end
        return planning:Update(function(s) s.searching = false; s.matches = matches end)
    end
end
local old = begin("Stormwind")
local current = begin("Ironforge")
check(not old({ "Stormwind" }), "ATCF: obsolete callback rejected by consumer generation")
check(current({ "Ironforge" }), "ATCF: current result accepted")
check(planning:Read().matches[1] == "Ironforge" and nav.state == "walking", "ATCF: search preserves navigation")
local waitingGeneration = planning:Read().generation
begin("Darnassus")
check(waitingGeneration ~= planning:Read().generation, "ATCF: edited pending plan cannot auto-resume")

-- Cross-consumer contract edge cases.
local state = T.State({ n = 0 }, { validate = function(s) return s.n >= 0, "negative" end })
local captured
state:Update(function(s) captured = s; s.n = 1 end); captured.n = 90
check(state:Read().n == 1, "retained draft cannot mutate committed state")
local snapshot = state:Read(); snapshot.n = 80
check(state:Read().n == 1, "read cannot mutate committed state")
check(not state:Update(function(s) s.n = -1 end) and state:Read().n == 1, "validation failure is atomic")
check(not state:Update(function(s) s.n = 2; error("fail") end) and state:Read().n == 1, "exception is atomic")
local calls, owner = 0, T.Scope()
owner:Watch(state:Select(function(s) return s.n end), function()
    calls = calls + 1
    local success, err = state:Update(function(s) s.n = s.n + 1 end)
    check(not success and err == "reentrant", "watch writes fail synchronously")
end)
state:Update(function(s) s.n = 1 end)
check(calls == 1, "no-op emits nothing")
local errors = T.Scope()
errors:Watch(state:Select(function(s) return s.n end), function() error("view failed") end)
check(state:Update(function(s) s.n = 3 end) and #errors.errors == 2, "watch failure does not roll back commit")
local cancelScope, later, armed = T.Scope(), nil, false
cancelScope:Watch(state:Select(function(s) return s.n end), function() if armed then later:Cancel() end end)
local lateCalls = 0
later = cancelScope:Watch(state:Select(function(s) return s.n end), function() lateCalls = lateCalls + 1 end)
armed = true; state:Update(function(s) s.n = 4 end)
check(lateCalls == 1, "cancellation suppresses later dispatch")
check(not state:Update(function(s) s.loop = s end), "cycles rejected")
print("PASS: " .. count .. " assertions; three consumer exercises + state contract edges")
