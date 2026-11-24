-- Standalone example. Declare ExampleCharacterProfiles in the TOC's SavedVariables.
local addonName, ns = ...
local SND = ns.SomethingNeedDoing
local app = SND:NewAddon(addonName)
ns.app = app
app:Settings({
    savedVariables = { "ExampleCharacterProfiles" },
    characterProfiles = true,
    fields = { showTotals = { type = "boolean", default = true } },
})

local function bindPlayer()
    if not app.profiles:Capabilities().needsCharacter then return end
    local name, realm = UnitName("player"), GetRealmName()
    if not SND.Values.Readable(name) or not SND.Values.Readable(realm) then return end
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT
        or type(realm) ~= "string" or realm == "" then return end
    local ok, err = app.profiles:BindCharacter(name .. "-" .. realm)
    if not ok then app.log:Warn(err.message) end
end
app:OnReady(bindPlayer)
app:Scope("player"):Event("PLAYER_ENTERING_WORLD", bindPlayer)
