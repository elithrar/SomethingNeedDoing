-- Load after SND/Embed.xml in a consumer TOC.
-- The consumer TOC declares: ## SavedVariables: ExampleProfiles
-- Use a distinct global for the default profile schema; existing databases need an adapter.
local ADDON, ns = ...
local app = ns.SomethingNeedDoing:NewAddon(ADDON, { version = '1.0.0' })
ns.app = app
app:Settings({
    savedVariables = { 'ExampleProfiles' },
    fields = {
        scale = { type = 'number', default = 1, min = .5, max = 2 },
        font = { type = 'font', default = 'Game tooltip' },
        fontSize = { type = 'integer', default = 14, min = 10, max = 20 },
        theme = { type = 'enum', default = 'modern', values = {'modern','forever','dusk'} },
        tint = { type = 'color', default = {.2,.4,.6} },
    },
})
local SND = ns.SomethingNeedDoing
-- A theme can add plain tokens for a consumer renderer without teaching SND its geometry.
local dusk = {
    label = 'Dusk', border = 'thin',
    colors = {surface={.05,.04,.09,.97}, border={.25,.2,.35,1}, accent={.7,.6,1,1},
        text={.94,.93,.98,1}, muted={.65,.6,.75,1}},
    tokens = {track={.12,.09,.2,1}},
}
app:Appearance({defaultTheme='modern', themes={modern=SND.Themes.modern, forever=SND.Themes.forever, dusk=dusk}})
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
            { type = 'select', key = 'theme', label = 'Theme', choices = app.ui:Themes() },
            { type = 'slider', key = 'fontSize', label = 'Font size' },
        },
    }} }, SND.Pages.Profiles()},
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
    local styled, styleError = app.ui:Style(preview,'section')
    if not styled then app.log:Warn(styleError.message) end
    local label=preview:CreateFontString(nil,'OVERLAY','GameTooltipText')
    label:SetPoint('CENTER');label:SetText('Ready')
    local applied, fontError = app.fonts:Apply(label,'body')
    if not applied then app.log:Warn(fontError.message) end
    local colored, colorError = app.ui:Color(label,'text')
    if not colored then app.log:Warn(colorError.message) end
    ns.Preview = preview
    local appearance = app:SelectSettings(function(values)
        return {scale=values.scale, tint=values.tint}
    end)
    local owner = app:Scope('example-view')
    owner:Watch(app:SelectAppearance(function(value)return value end),function()
        local width,height=app.fonts:Measure(label)
        preview:SetSize(math.max(120,width+24),math.max(40,height+16))
        paint(app:Get('tint')) -- An explicit user tint takes precedence over the theme surface.
    end)
    owner:Watch(appearance, function(value)
        preview:SetScale(value.scale);paint(value.tint)
    end)
    -- The color control's preview only repaints; acceptance commits through app:Set.
    -- Reset/profile changes reach the same watcher. No cached mutable settings table.
    owner:Watch(status:Select(function(value) return value.message end), function(message)
        app.log:Info(message)
    end)
end)
