-- Water page: terrain water properties and the underwater approximation.
local Sections = require(script.Parent.Sections)

return Sections.Page(
	"Water",
	"Terrain water (Workspace.Terrain.Water*). The underwater look is a client-side ColorCorrection/Blur approximation enabled while the camera is inside water.",
	function(context)
		local engine = context.Engine
		return {
			{
				Title = "Terrain water",
				Path = { "Water" },
				Fields = engine.Registry:GetSection("Water").Fields,
				Live = function()
					return engine.Water:Get()
				end,
			},
		}
	end
)
