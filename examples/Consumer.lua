-- Load after SND/Embed.xml and examples/SettingsAdapter.lua in a consumer TOC.
-- The consumer TOC declares: ## SavedVariables: ExampleDB
local ADDON, ns = ...
local app = ns.SomethingNeedDoing:NewAddon(ADDON, { version = '1.0.0' })
ns.app = app
app:Settings({
    savedVariables = { 'ExampleDB' },
    adapter = ns.CreateSettingsAdapter('ExampleDB'),
    fields = {
        scale = { type = 'number', default = 1, min = .5, max = 2 },
        font = { type = 'font', default = 'Game tooltip' },
        tint = { type = 'color', default = {.2,.4,.6} },
    },
})
-- One settings owner drives both the standard controls and a bespoke view.
local preview
local function paint(color)
    if preview then preview:SetBackdropColor(unpack(color)) end
end
local panel = app:Options({
    title = ADDON,
    pages = {{ id = 'appearance', label = 'Appearance', sections = {{
        title = 'Appearance', controls = {
            { type = 'slider', key = 'scale', label = 'Scale', step = .05 },
            { type = 'font', key = 'font', label = 'Font' },
            { type = 'color', key = 'tint', label = 'Tint', preview = paint },
        },
    }} }},
})
local registered, err = app:Slash('/sndexample', function()
    local ok, failure = panel:Toggle()
    if not ok then app.log:Warn(failure.message) end
end)
if not registered then app.log:Warn(err.message) end
-- Domain models remain local. Publish small UI projections after successful commands.
local status = app:State({ message = 'Ready' })
app:OnReady(function()
    preview = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
    preview:SetSize(120, 40);preview:SetPoint('CENTER')
    preview:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'})
    ns.Preview = preview
    local appearance = app:SelectSettings(function(values)
        return {scale=values.scale, tint=values.tint}
    end)
    local owner = app:Scope('example-view')
    owner:Watch(appearance, function(value)
        preview:SetScale(value.scale);paint(value.tint)
    end)
    -- The color control's preview only repaints; acceptance commits through app:Set.
    -- Reset/profile changes reach the same watcher. No cached mutable settings table.
    owner:Watch(status:Select(function(value) return value.message end), function(message)
        app.log:Info(message)
    end)
end)
