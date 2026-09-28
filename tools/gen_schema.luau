--[[
	Regenerates the machine-readable schemas in Documentation/schema/ from the
	live registries, so they never drift from the code.

	  python3 tools/bundle.py test.project.json build/test_bundle.luau
	  luau tools/gen_schema.luau -a config    > Documentation/schema/config.schema.json
	  luau tools/gen_schema.luau -a full      > Documentation/schema/visualfx.schema.json
	  luau tools/gen_schema.luau -a commands  > Documentation/schema/commands.json
	  luau tools/gen_schema.luau -a presets   > Documentation/schema/presets.json

	(tools/gen_docs.sh runs all four.)
]]

local Mock = require("./mock/Roblox")
local bundle = require("../build/test_bundle")

local which = ({ ... })[1] or "config"

local function findNode(node, path)
	for _, name in ipairs(path) do
		for _, child in ipairs(node.Children) do
			if child.Name == name then
				node = child
				break
			end
		end
	end
	return node
end

local world = Mock.createWorld()
local package = Mock.mount(findNode(bundle, { "ReplicatedStorage", "VisualFX" }), world.game:GetService("ReplicatedStorage"))
local requireFn = Mock.makeRequire(world)
local VisualFX = requireFn(package)
local Serialization = requireFn(package.Core.Serialization)
local Schema = requireFn(package.AI.Schema)
local engine = VisualFX.new({ AutoStart = false })

local output
if which == "config" then
	output = Schema.ToJSONSchema(engine)
elseif which == "full" then
	output = Schema.Build(engine, { IncludePresets = false })
elseif which == "commands" then
	output = engine.Commands:Catalog()
elseif which == "presets" then
	local presets = {}
	for _, preset in ipairs(engine:ListPresets()) do
		presets[preset.Name] = {
			Summary = preset,
			Resolved = Serialization:EncodeValue((engine:GetPreset(preset.Name))),
		}
	end
	output = presets
else
	error("unknown schema kind: " .. tostring(which))
end

print(Serialization:ToJSON(output, true))
