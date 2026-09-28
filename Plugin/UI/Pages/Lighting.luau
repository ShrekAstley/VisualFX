-- Lighting page: Lighting service properties and post-processing effects.
local Sections = require(script.Parent.Sections)

return Sections.Page(
	"Lighting",
	"Lighting service properties and post-processing. Unsupported properties are detected and skipped with a warning.",
	function(context)
		local engine = context.Engine
		local registry = engine.Registry
		local specs = {
			{
				Title = "Lighting",
				Path = { "Lighting" },
				Fields = registry:GetSection("Lighting").Fields,
				Live = function()
					return engine.Lighting:Get()
				end,
			},
		}
		for _, effect in ipairs(registry:GetSection("PostProcessing").Fields) do
			table.insert(specs, {
				Title = "Post-processing: " .. effect.Key,
				Path = { "PostProcessing", effect.Key },
				Fields = effect.Fields,
				Collapsed = true,
				Live = function()
					return engine.PostProcessing[effect.Key]:Get()
				end,
			})
		end
		return specs
	end
)
