-- Atmosphere page: Atmosphere, Sky and Clouds editors generated from the schema.
local Sections = require(script.Parent.Sections)

return Sections.Page(
	"Atmosphere",
	"Atmospheric scattering, sky and clouds. Existing Atmosphere/Sky/Clouds instances are adopted (their original values are restored on revert/reset).",
	function(context)
		local engine = context.Engine
		local registry = engine.Registry
		return {
			{
				Title = "Atmosphere",
				Path = { "Atmosphere" },
				Fields = registry:GetSection("Atmosphere").Fields,
				Live = function()
					return engine.Atmosphere:Get()
				end,
			},
			{
				Title = "Clouds",
				Path = { "Clouds" },
				Fields = registry:GetSection("Clouds").Fields,
				Live = function()
					return engine.Clouds:Get()
				end,
			},
			{
				Title = "Sky",
				Path = { "Sky" },
				Fields = registry:GetSection("Sky").Fields,
				Collapsed = true,
				Live = function()
					return engine.Sky:Get()
				end,
			},
		}
	end
)
