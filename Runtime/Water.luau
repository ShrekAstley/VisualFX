--[[
	VisualFX.Runtime.Water

	Configures Roblox terrain water through the properties the engine really
	exposes on Workspace.Terrain:

	  Color        -> Terrain.WaterColor
	  Transparency -> Terrain.WaterTransparency
	  Reflectance  -> Terrain.WaterReflectance
	  WaveSize     -> Terrain.WaterWaveSize      (alias: WaveStrength)
	  WaveSpeed    -> Terrain.WaterWaveSpeed

	Roblox has no dedicated underwater fog property. `Underwater` is an
	approximation: on clients, when the camera is inside terrain water,
	VisualFX enables a managed ColorCorrection (tint) and optional Blur.
	Environmental reflections on water come from Lighting.EnvironmentSpecularScale.
]]

local Core = script.Parent.Parent.Core
local PropertyMap = require(Core.PropertyMap)

local Water = {}

Water.Fields = {
	{ Key = "Color", Property = "WaterColor", Kind = "Color3", Default = Color3.fromRGB(12, 84, 92), Aliases = { "WaterColor" }, Description = "Water tint." },
	{ Key = "Transparency", Property = "WaterTransparency", Kind = "number", Min = 0, Max = 1, Default = 0.3, Aliases = { "WaterTransparency" }, Description = "0 = opaque, 1 = fully clear." },
	{ Key = "Reflectance", Property = "WaterReflectance", Kind = "number", Min = 0, Max = 1, Default = 1, Aliases = { "WaterReflectance" }, Description = "Strength of sky reflections." },
	{ Key = "WaveSize", Property = "WaterWaveSize", Kind = "number", Min = 0, Max = 1, Default = 0.15, Aliases = { "WaveStrength", "WaterWaveSize" }, Description = "Wave height." },
	{ Key = "WaveSpeed", Property = "WaterWaveSpeed", Kind = "number", Min = 0, Max = 100, Default = 10, Aliases = { "WaterWaveSpeed" }, Description = "Wave animation speed." },
	{
		Key = "Underwater",
		Kind = "object",
		Description = "Client-side underwater look (approximation using ColorCorrectionEffect/BlurEffect).",
		Fields = {
			{ Key = "Enabled", Kind = "boolean", Default = true },
			{ Key = "TintColor", Kind = "Color3", Default = Color3.fromRGB(120, 190, 210) },
			{ Key = "Brightness", Kind = "number", Min = -1, Max = 1, Default = -0.05 },
			{ Key = "Contrast", Kind = "number", Min = -1, Max = 1, Default = 0.05 },
			{ Key = "Saturation", Kind = "number", Min = -1, Max = 1, Default = -0.1 },
			{ Key = "BlurSize", Kind = "number", Min = 0, Max = 56, Default = 4 },
		},
	},
}

function Water.Register(registry)
	registry:RegisterSection({
		Name = "Water",
		Order = 50,
		ClassName = "Terrain",
		Description = "Terrain water appearance and the underwater look.",
		Fields = Water.Fields,
		Targets = function(context)
			return { { ID = "water", Instance = context.Terrain } }
		end,
		Desired = function(section, context)
			local properties, byProperty = PropertyMap.toProperties(Water.Fields, section)
			local specs = {
				{
					ID = "water",
					Type = "Water",
					Target = context.Terrain,
					Properties = properties,
					FieldsByProperty = byProperty,
				},
			}
			local underwater = section.Underwater
			if underwater and underwater.Enabled ~= false then
				table.insert(specs, {
					ID = "water.underwater.colorcorrection",
					Type = "UnderwaterTint",
					ClassName = "ColorCorrectionEffect",
					Name = "VisualFX_UnderwaterTint",
					Parent = context.Lighting,
					Properties = {
						Enabled = false,
						TintColor = underwater.TintColor or Color3.fromRGB(120, 190, 210),
						Brightness = underwater.Brightness or -0.05,
						Contrast = underwater.Contrast or 0.05,
						Saturation = underwater.Saturation or -0.1,
					},
					RuntimeProperties = { Enabled = true },
				})
				local blurSize = underwater.BlurSize or 4
				if blurSize > 0 then
					table.insert(specs, {
						ID = "water.underwater.blur",
						Type = "UnderwaterBlur",
						ClassName = "BlurEffect",
						Name = "VisualFX_UnderwaterBlur",
						Parent = context.Lighting,
						Properties = { Enabled = false, Size = blurSize },
						RuntimeProperties = { Enabled = true },
					})
				end
			end
			return specs
		end,
		Inspect = function(context)
			return PropertyMap.read(context.Terrain, Water.Fields, context.Compatibility)
		end,
	})
end

--[[
	Client controller: toggles the underwater effects when the camera is
	inside terrain water. Uses Terrain:ReadVoxels, a supported API.
]]
function Water.CreateController(engine)
	local controller = { Name = "Underwater", Interval = 0.2, _accumulated = 0, _inside = false }

	local function cameraInWater(): boolean
		local camera = workspace.CurrentCamera
		if not camera then
			return false
		end
		local position = camera.CFrame.Position
		local ok, inside = pcall(function()
			local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2)):ExpandToGrid(4)
			local materials, occupancies = workspace.Terrain:ReadVoxels(region, 4)
			local material = materials[1][1][1]
			local occupancy = occupancies[1][1][1]
			return material == Enum.Material.Water and occupancy > 0.5
		end)
		return ok and inside == true
	end

	function controller:Step(dt: number)
		local resolved = engine:GetResolvedConfiguration()
		local water = resolved.Water
		if not water or not water.Underwater or water.Underwater.Enabled == false then
			return
		end
		self._accumulated += dt
		if self._accumulated < self.Interval then
			return
		end
		self._accumulated = 0
		local inside = cameraInWater()
		if inside ~= self._inside then
			self._inside = inside
			for _, id in ipairs({ "water.underwater.colorcorrection", "water.underwater.blur" }) do
				local instance = engine.InstanceManager:Find(id)
				if instance then
					engine.Compatibility:SetProperty(instance, "Enabled", inside)
				end
			end
		end
	end

	return controller
end

return Water
