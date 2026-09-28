--[[
	VisualFX.Runtime.Particles

	A reusable particle abstraction on top of ParticleEmitter.

	Every particle system is an anchored, invisible, non-colliding host Part
	(the emission volume) with a ParticleEmitter child, stored in
	Workspace.VisualFX. Systems are declared in the configuration:

	  Particles = {
	      Rain = { Template = "Rain", Rate = 600 },
	      Campfire = { Template = "Embers", Attach = "World", Position = Vector3.new(0, 2, 0) },
	  }

	Templates (Rain, Snow, Dust, Fog, Mist, Smoke, Embers, Sparks, Fireflies,
	Leaves, Magic, Custom) provide defaults; any ParticleEmitter property in the
	configuration overrides them.

	Attach = "Camera" keeps the emission volume above the local camera (use
	from a LocalScript; on the server there is no camera, so the volume stays
	at Position). Attach = "World" keeps it at Position.

	Textures: templates use textures that ship with the Roblox client
	(rbxasset://textures/particles/...). They are generic sprites, so rain,
	leaves etc. are approximations; set `Texture` to your own asset for
	production-quality visuals.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)
local PropertyMap = require(Core.PropertyMap)
local Values = require(Core.Values)

local Particles = {}

Particles.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Spark = "rbxasset://textures/particles/fire_sparks_main.dds",
}

local T = Particles.Textures

-- Emitter properties (ParticleEmitter).
Particles.EmitterFields = {
	{ Key = "Enabled", Property = "Enabled", Kind = "boolean", Default = true },
	{ Key = "Rate", Property = "Rate", Kind = "number", Min = 0, SoftMax = 2000, Aliases = { "EmissionRate" }, Neutral = 0, Description = "Particles emitted per second (before quality scaling)." },
	{ Key = "Lifetime", Property = "Lifetime", Kind = "NumberRange", Min = 0, SoftMax = 30 },
	{ Key = "Speed", Property = "Speed", Kind = "NumberRange" },
	{ Key = "Size", Property = "Size", Kind = "NumberSequence", Min = 0 },
	{ Key = "Color", Property = "Color", Kind = "ColorSequence" },
	{ Key = "Transparency", Property = "Transparency", Kind = "NumberSequence", Min = 0, Max = 1 },
	{ Key = "Rotation", Property = "Rotation", Kind = "NumberRange" },
	{ Key = "RotSpeed", Property = "RotSpeed", Kind = "NumberRange" },
	{ Key = "Drag", Property = "Drag", Kind = "number" },
	{ Key = "Acceleration", Property = "Acceleration", Kind = "Vector3" },
	{ Key = "SpreadAngle", Property = "SpreadAngle", Kind = "Vector2" },
	{ Key = "Texture", Property = "Texture", Kind = "string", Interpolate = false },
	{ Key = "LightEmission", Property = "LightEmission", Kind = "number", Min = 0, Max = 1 },
	{ Key = "LightInfluence", Property = "LightInfluence", Kind = "number", Min = 0, Max = 1 },
	{ Key = "Brightness", Property = "Brightness", Kind = "number", Min = 0, SoftMax = 10 },
	{ Key = "Shape", Property = "Shape", Kind = "EnumItem", Enum = "ParticleEmitterShape" },
	{ Key = "ShapeStyle", Property = "ShapeStyle", Kind = "EnumItem", Enum = "ParticleEmitterShapeStyle" },
	{ Key = "ShapeInOut", Property = "ShapeInOut", Kind = "EnumItem", Enum = "ParticleEmitterShapeInOut" },
	{ Key = "ShapePartial", Property = "ShapePartial", Kind = "number", Min = 0, Max = 1 },
	{ Key = "Orientation", Property = "Orientation", Kind = "EnumItem", Enum = "ParticleOrientation" },
	{ Key = "EmissionDirection", Property = "EmissionDirection", Kind = "EnumItem", Enum = "NormalId" },
	{ Key = "ZOffset", Property = "ZOffset", Kind = "number" },
	{ Key = "LockedToPart", Property = "LockedToPart", Kind = "boolean" },
	{ Key = "VelocityInheritance", Property = "VelocityInheritance", Kind = "number" },
	{ Key = "WindAffectsDrag", Property = "WindAffectsDrag", Kind = "boolean" },
	{ Key = "Squash", Property = "Squash", Kind = "NumberSequence", Min = -3, Max = 3 },
	{ Key = "TimeScale", Property = "TimeScale", Kind = "number", Min = 0, Max = 1 },
}

-- Placement fields (not ParticleEmitter properties).
Particles.PlacementFields = {
	{ Key = "Template", Kind = "string", Description = "Particle template providing defaults (Rain, Snow, ...)." },
	{ Key = "Attach", Kind = "string", Values = { "Camera", "World" }, Description = "Follow the local camera or stay at Position." },
	{ Key = "Position", Kind = "Vector3", Description = "World position of the emission volume (World attach, or server fallback)." },
	{ Key = "Area", Kind = "Vector3", Min = 0, Description = "Size of the emission volume in studs." },
	{ Key = "Offset", Kind = "Vector3", Description = "Offset from the camera when Attach = Camera." },
	{ Key = "Priority", Kind = "number", Description = "Higher priority systems keep their budget first when quality limits apply." },
	{ Key = "CullDistance", Kind = "number", Min = 0, Description = "Disable when the camera is farther than this (World attach). Defaults to the quality profile." },
}

Particles.ItemFields = {}
Util.append(Particles.ItemFields, Particles.PlacementFields)
Util.append(Particles.ItemFields, Particles.EmitterFields)

local function ns(...)
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local keypoints = {}
	for index, value in ipairs(values) do
		table.insert(keypoints, NumberSequenceKeypoint.new((index - 1) / (#values - 1), value))
	end
	return NumberSequence.new(keypoints)
end

local function cs(...)
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for index, color in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

local rgb = Color3.fromRGB

-- Enum items are looked up safely so a template never fails to load on an
-- engine that lacks a newer enum item; missing items are simply omitted.
local function E(enumName: string, itemName: string)
	return Values.getEnumItem(enumName, itemName)
end

Particles.Templates = {
	Rain = {
		Description = "Falling rain streaks (stretched with Squash, aligned to velocity).",
		Defaults = {
			Attach = "Camera", Area = Vector3.new(160, 4, 160), Offset = Vector3.new(0, 55, 0), Priority = 10,
			Rate = 600, Lifetime = NumberRange.new(1, 1.4), Speed = NumberRange.new(90, 120),
			Size = ns(0.1), Squash = ns(2.5), Color = cs(rgb(185, 205, 230)), Transparency = ns(0.35),
			LightEmission = 0.1, LightInfluence = 0.9, Acceleration = Vector3.new(0, -40, 0),
			SpreadAngle = Vector2.new(3, 3), Texture = T.Sparkle,
			EmissionDirection = E("NormalId", "Bottom"), Orientation = E("ParticleOrientation", "VelocityParallel"),
			Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Snow = {
		Description = "Slowly drifting snowflakes that respond to wind.",
		Defaults = {
			Attach = "Camera", Area = Vector3.new(180, 4, 180), Offset = Vector3.new(0, 45, 0), Priority = 10,
			Rate = 250, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(4, 8),
			Size = ns(0.3), Color = cs(rgb(255, 255, 255)), Transparency = ns(0.1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
			LightEmission = 0.2, LightInfluence = 1, Acceleration = Vector3.new(0, -2, 0), Drag = 0.5,
			WindAffectsDrag = true, SpreadAngle = Vector2.new(25, 25), Texture = T.Sparkle,
			EmissionDirection = E("NormalId", "Bottom"),
			Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Dust = {
		Description = "Floating dust motes around the camera.",
		Defaults = {
			Attach = "Camera", Area = Vector3.new(80, 30, 80), Offset = Vector3.new(0, 5, 0), Priority = 3,
			Rate = 40, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.5, 2),
			Size = ns(0.15), Color = cs(rgb(200, 180, 140)), Transparency = ns(1, 0.6, 1),
			LightEmission = 0, LightInfluence = 1, Drag = 1, WindAffectsDrag = true,
			SpreadAngle = Vector2.new(180, 180), Texture = T.Sparkle,
			Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Fog = {
		Description = "Large, soft, slow smoke sprites that read as low-lying volumetric fog.",
		Defaults = {
			Attach = "Camera", Area = Vector3.new(200, 12, 200), Offset = Vector3.new(0, 2, 0), Priority = 5,
			Rate = 8, Lifetime = NumberRange.new(12, 18), Speed = NumberRange.new(0.2, 1),
			Size = ns(18, 28), Color = cs(rgb(210, 215, 220)), Transparency = ns(1, 0.82, 1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-3, 3),
			LightEmission = 0, LightInfluence = 1, SpreadAngle = Vector2.new(180, 180), Texture = T.Smoke,
			Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Mist = {
		Description = "Thin, low mist; subtler than Fog.",
		Defaults = {
			Attach = "Camera", Area = Vector3.new(150, 6, 150), Offset = Vector3.new(0, 1, 0), Priority = 4,
			Rate = 12, Lifetime = NumberRange.new(8, 12), Speed = NumberRange.new(0.2, 0.8),
			Size = ns(8, 12), Color = cs(rgb(220, 225, 230)), Transparency = ns(1, 0.88, 1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-4, 4),
			LightEmission = 0, LightInfluence = 1, SpreadAngle = Vector2.new(180, 180), Texture = T.Smoke,
			Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Smoke = {
		Description = "Rising smoke column.",
		Defaults = {
			Attach = "World", Area = Vector3.new(4, 1, 4), Priority = 5,
			Rate = 20, Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(3, 6),
			Size = ns(2, 6), Color = cs(rgb(90, 90, 95)), Transparency = ns(0.4, 1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20),
			LightEmission = 0, LightInfluence = 1, Acceleration = Vector3.new(0, 1, 0),
			SpreadAngle = Vector2.new(10, 10), Texture = T.Smoke, EmissionDirection = E("NormalId", "Top"),
		},
	},
	Embers = {
		Description = "Glowing embers drifting upward.",
		Defaults = {
			Attach = "World", Area = Vector3.new(6, 1, 6), Priority = 5,
			Rate = 30, Lifetime = NumberRange.new(2, 4), Speed = NumberRange.new(3, 8),
			Size = ns(0.15, 0), Color = cs(rgb(255, 170, 60), rgb(255, 80, 20)), Transparency = ns(0, 1),
			LightEmission = 1, LightInfluence = 0, Acceleration = Vector3.new(0, 4, 0),
			RotSpeed = NumberRange.new(-90, 90), SpreadAngle = Vector2.new(30, 30), Texture = T.Sparkle,
			EmissionDirection = E("NormalId", "Top"),
		},
	},
	Sparks = {
		Description = "Fast, short-lived sparks with gravity.",
		Defaults = {
			Attach = "World", Area = Vector3.new(1, 1, 1), Priority = 5,
			Rate = 60, Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(20, 35),
			Size = ns(0.12), Squash = ns(1), Color = cs(rgb(255, 220, 120)), Transparency = ns(0, 1),
			LightEmission = 1, LightInfluence = 0, Acceleration = Vector3.new(0, -30, 0),
			SpreadAngle = Vector2.new(60, 60), Texture = T.Spark,
			Orientation = E("ParticleOrientation", "VelocityParallel"), EmissionDirection = E("NormalId", "Top"),
		},
	},
	Fireflies = {
		Description = "Slow glowing points that fade in and out.",
		Defaults = {
			Attach = "Camera", Area = Vector3.new(60, 8, 60), Offset = Vector3.new(0, 3, 0), Priority = 3,
			Rate = 6, Lifetime = NumberRange.new(5, 9), Speed = NumberRange.new(0.5, 1.5),
			Size = ns(0, 0.25, 0), Color = cs(rgb(220, 255, 120)), Transparency = ns(1, 0, 1),
			LightEmission = 1, LightInfluence = 0, Drag = 1, SpreadAngle = Vector2.new(180, 180),
			Texture = T.Sparkle,
			Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Leaves = {
		Description = "Tumbling falling leaves (use a leaf texture for best results).",
		Defaults = {
			Attach = "Camera", Area = Vector3.new(120, 20, 120), Offset = Vector3.new(0, 25, 0), Priority = 4,
			Rate = 10, Lifetime = NumberRange.new(6, 10), Speed = NumberRange.new(2, 5),
			Size = ns(0.6), Color = cs(rgb(214, 128, 44), rgb(160, 70, 30)), Transparency = ns(0, 0, 1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
			LightEmission = 0, LightInfluence = 1, Acceleration = Vector3.new(2, -3, 0), Drag = 0.6,
			WindAffectsDrag = true, SpreadAngle = Vector2.new(40, 40), Texture = T.Sparkle,
			EmissionDirection = E("NormalId", "Bottom"),
			Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Magic = {
		Description = "Swirling colored sparkles.",
		Defaults = {
			Attach = "World", Area = Vector3.new(6, 6, 6), Priority = 5,
			Rate = 40, Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(1, 3),
			Size = ns(0.3, 0), Color = cs(rgb(170, 90, 255), rgb(80, 220, 255)), Transparency = ns(0, 1),
			LightEmission = 1, LightInfluence = 0, RotSpeed = NumberRange.new(-180, 180),
			SpreadAngle = Vector2.new(180, 180), Texture = T.Sparkle,
			Shape = E("ParticleEmitterShape", "Sphere"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
		},
	},
	Custom = {
		Description = "Plain emitter; configure every property yourself.",
		Defaults = {
			Attach = "World", Area = Vector3.new(4, 4, 4), Priority = 5,
			Rate = 20, Texture = T.Sparkle,
		},
	},
}

function Particles.RegisterTemplates(registry)
	for _, name in ipairs(Util.sortedKeys(Particles.Templates)) do
		registry:RegisterParticleTemplate(name, Particles.Templates[name])
	end
end

-- Resolves the template for a system (explicit Template, else the system's name).
function Particles.ResolveTemplate(registry, name: string, config: { [string]: any })
	if config.Template then
		local template, registered = registry:FindParticleTemplate(config.Template)
		return template, registered
	end
	local template, registered = registry:FindParticleTemplate(name)
	if template then
		return template, registered
	end
	return registry:GetParticleTemplate("Custom"), "Custom"
end

-- Template defaults merged with the system configuration.
function Particles.Merge(registry, name: string, config: { [string]: any })
	local template, templateName = Particles.ResolveTemplate(registry, name, config)
	local merged = Util.deepCopy(template and template.Defaults or {})
	for key, value in pairs(config) do
		merged[key] = value
	end
	merged.Template = templateName
	return merged
end

local EMITTER_BY_KEY = {}
for _, field in ipairs(Particles.EmitterFields) do
	EMITTER_BY_KEY[field.Key] = field
end

--[[
	Builds the two specs (host Part + ParticleEmitter) for one system.
	options: { ID, Type, Owner, Priority }
]]
function Particles.BuildSpecs(merged: { [string]: any }, context, options: { [string]: any })
	local emitterProperties, byProperty = PropertyMap.toProperties(Particles.EmitterFields, merged)
	if emitterProperties.Enabled == nil then
		emitterProperties.Enabled = true
	end
	local attach = merged.Attach or "World"
	local area = merged.Area or Vector3.new(4, 4, 4)
	local offset = merged.Offset or Vector3.new(0, 0, 0)
	local position = merged.Position
	if not position then
		position = if attach == "Camera" then offset else Vector3.new(0, area.Y / 2, 0)
	end
	local hostId = options.ID .. ".host"
	local hostName = "VisualFX_" .. (options.Type or "Particles")
	local host = {
		ID = hostId,
		Type = (options.Type or "Particles") .. "Volume",
		ClassName = "Part",
		Name = hostName,
		ParentID = "root",
		Owner = options.Owner,
		Properties = {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Locked = true,
			Transparency = 1,
			Size = area,
			Position = position,
		},
		RuntimeProperties = if attach == "Camera" then { Position = true } else nil,
		Depth = 1,
	}
	local emitter = {
		ID = options.ID,
		Type = options.Type or "Particles",
		ClassName = "ParticleEmitter",
		Name = options.Type or "Particles",
		ParentID = hostId,
		Owner = options.Owner,
		Properties = emitterProperties,
		FieldsByProperty = byProperty,
		Depth = 2,
		Particle = {
			BaseRate = emitterProperties.Rate or 0,
			Lifetime = merged.Lifetime,
			Priority = merged.Priority or options.Priority or 5,
			Attach = attach,
			Offset = offset,
			CullDistance = merged.CullDistance,
			HostID = hostId,
		},
		RuntimeProperties = if attach == "World" then { Enabled = true } else nil,
	}
	return host, emitter
end

function Particles.Register(registry)
	Particles.RegisterTemplates(registry)
	registry:RegisterSection({
		Name = "Particles",
		Order = 60,
		Kind = "map",
		ClassName = "ParticleEmitter",
		Description = "Named particle systems. Keys are system names; values are template overrides.",
		ItemFields = Particles.ItemFields,
		Validate = function(section, report)
			for _, name in ipairs(Util.sortedKeys(section)) do
				local item = section[name]
				if typeof(item) == "table" and item.Template and not registry:FindParticleTemplate(item.Template) then
					local suggestion = Util.suggest(item.Template, registry:ListParticleTemplates())
					report:Error(
						"Particles." .. name .. ".Template",
						"UnknownTemplate",
						string.format(
							"Particles.%s.Template: unknown particle template '%s'%s",
							name,
							item.Template,
							if suggestion then " (did you mean '" .. suggestion .. "'?)" else ""
						)
					)
				end
			end
		end,
		Desired = function(section, context)
			local specs = {}
			for _, name in ipairs(Util.sortedKeys(section)) do
				local merged = Particles.Merge(registry, name, section[name])
				local host, emitter = Particles.BuildSpecs(merged, context, {
					ID = "particles." .. name,
					Type = name,
					Owner = "Particles",
				})
				table.insert(specs, host)
				table.insert(specs, emitter)
			end
			return specs
		end,
		Inspect = function(context)
			local list = {}
			local ok, descendants = pcall(context.Workspace.GetDescendants, context.Workspace)
			if ok then
				local scanned = 0
				for _, instance in ipairs(descendants) do
					if instance.ClassName == "ParticleEmitter" then
						scanned += 1
						if scanned > 500 then
							break
						end
						local ownerPart = instance.Parent
						table.insert(list, {
							Name = instance.Name,
							Path = instance:GetFullName(),
							Enabled = instance.Enabled,
							Rate = instance.Rate,
							Parent = if ownerPart then ownerPart.Name else nil,
							Instance = instance,
						})
					end
				end
			end
			return list
		end,
	})
end

--[[
	Client controller: keeps camera-attached emission volumes above the camera
	and disables world systems that are farther than their cull distance.
]]
function Particles.CreateController(engine)
	local controller = { Name = "Particles", _accumulated = 0, Culled = 0 }

	function controller:Step(dt: number)
		local profile = engine.Quality:GetProfile()
		self._accumulated += dt
		if self._accumulated < 1 / math.max(1, profile.UpdateFrequency) then
			return
		end
		self._accumulated = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local cameraPosition = camera.CFrame.Position
		local culled = 0
		for _, spec in ipairs(engine:GetActiveSpecs()) do
			local particle = spec.Particle
			if particle then
				local host = engine.InstanceManager:Find(particle.HostID)
				local emitter = engine.InstanceManager:Find(spec.ID)
				if host and emitter then
					if particle.Attach == "Camera" then
						local target = cameraPosition + particle.Offset
						if (host.Position - target).Magnitude > 1 then
							host.Position = target
						end
					elseif profile.SpatialCulling then
						local limit = particle.CullDistance or profile.ActivationDistance
						local desired = spec.Properties.Enabled ~= false
						local inRange = (host.Position - cameraPosition).Magnitude <= limit
						local shouldEnable = desired and inRange
						if not inRange and desired then
							culled += 1
						end
						if emitter.Enabled ~= shouldEnable then
							emitter.Enabled = shouldEnable
						end
					end
				end
			end
		end
		self.Culled = culled
	end

	return controller
end

-- Estimated particles alive for a spec: rate * average lifetime.
function Particles.EstimateCount(spec): number
	local particle = spec.Particle
	if not particle then
		return 0
	end
	local rate = spec.Properties.Rate or 0
	local lifetime = if particle.Lifetime then Values.average(particle.Lifetime) else 1
	return rate * lifetime
end

return Particles
