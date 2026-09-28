--[[
	VisualFX.Codegen.Templates

	Script templates used by the Luau generator. Placeholders:
	  {{HEADER}}         comment header
	  {{REQUIRE}}        expression that requires the runtime library
	  {{CONFIG_NAME}}    variable holding the configuration table
	  {{CONFIG}}         the configuration table literal
	  {{QUALITY}}        optional quality line
	Templates never embed timestamps, so output is deterministic.
]]

local Templates = {}

Templates.Names = { "Script", "LocalScript", "Module", "Transition" }

Templates.Descriptions = {
	Script = "Server Script: applies the scene for everyone when the server starts.",
	LocalScript = "LocalScript: applies the scene on the client (camera-following weather, underwater effects).",
	Module = "ModuleScript returning the configuration table (reuse it anywhere, or save as a preset).",
	Transition = "LocalScript that transitions smoothly from the current scene to this configuration.",
}

Templates.Script = [[
{{HEADER}}
local VisualFX = require({{REQUIRE}})

-- Reusable configuration table (plain data; safe to store, diff and share).
local {{CONFIG_NAME}} = {{CONFIG}}
{{QUALITY}}
local result = VisualFX:CreateScene({{CONFIG_NAME}})
if not result.Success then
	warn("[VisualFX] scene failed to apply:", table.concat(result.Errors, "\n"))
end

return {{CONFIG_NAME}}
]]

Templates.LocalScript = [[
{{HEADER}}
-- Place in StarterPlayer.StarterPlayerScripts. Client-side application enables
-- camera-attached weather particles and the underwater effect.
local VisualFX = require({{REQUIRE}})

local {{CONFIG_NAME}} = {{CONFIG}}
{{QUALITY}}
local result = VisualFX:CreateScene({{CONFIG_NAME}})
if not result.Success then
	warn("[VisualFX] scene failed to apply:", table.concat(result.Errors, "\n"))
end
]]

Templates.Module = [[
{{HEADER}}
-- Configuration module. Use with:
--   VisualFX:CreateScene(require(path.To.ThisModule))
-- or save it in VisualFX.Presets.User to make it an ApplyPreset-able preset.
return {{CONFIG}}
]]

Templates.Transition = [[
{{HEADER}}
local VisualFX = require({{REQUIRE}})

local {{CONFIG_NAME}} = {{CONFIG}}

-- Smoothly move from whatever is currently shown to this configuration.
VisualFX:TransitionTo({
	Duration = {{DURATION}},
	Easing = "{{EASING}}",
	Configuration = {{CONFIG_NAME}},
	Replace = true,
})
]]

function Templates.Render(template: string, values: { [string]: string }): string
	local output = string.gsub(template, "{{([%u_]+)}}", function(key)
		return values[key] or ""
	end)
	-- Collapse the blank line left by an empty optional placeholder.
	output = string.gsub(output, "\n\n\n+", "\n\n")
	return output
end

return Templates
