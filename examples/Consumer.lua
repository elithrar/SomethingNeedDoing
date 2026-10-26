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
    },
})
local panel = app:Options({
    title = ADDON,
    pages = {{ id = 'appearance', label = 'Appearance', sections = {{
        title = 'Appearance', controls = {
            { type = 'slider', key = 'scale', label = 'Scale', step = .05 },
            { type = 'font', key = 'font', label = 'Font' },
        },
    }} }},
})
app:Slash('/sndexample', function() panel:Toggle() end)
-- Domain models remain local. Publish small UI projections after successful commands.
local status = app:State({ message = 'Ready' })
app:OnReady(function()
    local owner = app:Scope('status')
    owner:Watch(status:Select(function(value) return value.message end), function(message)
        app.log:Info(message)
    end)
end)
