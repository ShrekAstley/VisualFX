--[[
	VisualFX.Runtime.Quality

	Quality profiles and performance budgets.

	  VisualFX:SetQuality("High")
	  VisualFX:SetQuality("Custom", { MaxParticleRate = 2500 })
	  VisualFX:GetPerformanceStats()

	Budgets are applied deterministically when the desired scene is built:
	  1. every particle system's Rate is multiplied by ParticleRateScale;
	  2. systems beyond MaxParticleSystems (lowest Priority first) are disabled;
	  3. if the total rate still exceeds MaxParticleRate, all rates are scaled
	     down proportionally.
	Nothing here predicts frame rate; stats are estimates of workload only.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)

local Quality = {}
Quality.__index = Quality

Quality.Levels = { "Low", "Medium", "High", "Ultra", "Custom" }

Quality.Profiles = {
	Low = {
		ParticleRateScale = 0.3,
		MaxParticleRate = 800,
		MaxParticleSystems = 4,
		UpdateFrequency = 10,
		TransitionFrequency = 15,
		WeatherFrequency = 5,
		ActivationDistance = 250,
		SpatialCulling = true,
		Pooling = true,
		PostProcessing = { Bloom = false, DepthOfField = false, SunRays = false, Blur = false, ColorCorrection = true },
	},
	Medium = {
		ParticleRateScale = 0.6,
		MaxParticleRate = 2000,
		MaxParticleSystems = 8,
		UpdateFrequency = 15,
		TransitionFrequency = 20,
		WeatherFrequency = 10,
		ActivationDistance = 400,
		SpatialCulling = true,
		Pooling = true,
		PostProcessing = { Bloom = true, DepthOfField = false, SunRays = false, Blur = true, ColorCorrection = true },
	},
	High = {
		ParticleRateScale = 1,
		MaxParticleRate = 4000,
		MaxParticleSystems = 16,
		UpdateFrequency = 30,
		TransitionFrequency = 30,
		WeatherFrequency = 15,
		ActivationDistance = 700,
		SpatialCulling = true,
		Pooling = true,
		PostProcessing = { Bloom = true, DepthOfField = true, SunRays = true, Blur = true, ColorCorrection = true },
	},
	Ultra = {
		ParticleRateScale = 1,
		MaxParticleRate = 8000,
		MaxParticleSystems = 32,
		UpdateFrequency = 60,
		TransitionFrequency = 60,
		WeatherFrequency = 30,
		ActivationDistance = 1200,
		SpatialCulling = true,
		Pooling = true,
		PostProcessing = { Bloom = true, DepthOfField = true, SunRays = true, Blur = true, ColorCorrection = true },
	},
}

Quality.Fields = {
	{ Key = "Level", Kind = "string", Values = Quality.Levels, Default = "High" },
	{ Key = "ParticleRateScale", Kind = "number", Min = 0, Max = 4 },
	{ Key = "MaxParticleRate", Kind = "number", Min = 0, SoftMax = 20000 },
	{ Key = "MaxParticleSystems", Kind = "integer", Min = 0, Max = 128 },
	{ Key = "UpdateFrequency", Kind = "number", Min = 1, Max = 60 },
	{ Key = "TransitionFrequency", Kind = "number", Min = 1, Max = 60 },
	{ Key = "WeatherFrequency", Kind = "number", Min = 1, Max = 60 },
	{ Key = "ActivationDistance", Kind = "number", Min = 0 },
	{ Key = "SpatialCulling", Kind = "boolean" },
	{ Key = "Pooling", Kind = "boolean" },
	{
		Key = "PostProcessing",
		Kind = "object",
		Fields = {
			{ Key = "Bloom", Kind = "boolean" },
			{ Key = "ColorCorrection", Kind = "boolean" },
			{ Key = "DepthOfField", Kind = "boolean" },
			{ Key = "SunRays", Kind = "boolean" },
			{ Key = "Blur", Kind = "boolean" },
		},
	},
}

function Quality.new()
	local self = setmetatable({}, Quality)
	self.Level = "High"
	self.Overrides = {}
	self._profile = nil
	self.LastBudget = { RateScale = 1, BudgetScale = 1, Disabled = {} }
	return self
end

-- Builds a profile from a level name and optional overrides (pure function).
function Quality.BuildProfile(level: string?, overrides: { [string]: any }?)
	local baseLevel = if level and Quality.Profiles[level] then level else "High"
	local profile = Util.deepCopy(Quality.Profiles[baseLevel])
	if overrides then
		for key, value in pairs(overrides) do
			if key == "PostProcessing" and typeof(value) == "table" then
				for effect, allowed in pairs(value) do
					profile.PostProcessing[effect] = allowed
				end
			elseif key ~= "Level" then
				profile[key] = value
			end
		end
	end
	profile.Level = level or "High"
	return profile
end

function Quality:Set(level: string, overrides: { [string]: any }?)
	self.Level = level
	self.Overrides = Util.deepCopy(overrides or {})
	self._profile = nil
end

-- Applies the Quality section of a configuration (if present).
function Quality:ApplySection(section: { [string]: any }?)
	if not section then
		return
	end
	local overrides = Util.shallowCopy(section)
	overrides.Level = nil
	self:Set(section.Level or self.Level, overrides)
end

function Quality:GetProfile()
	if not self._profile then
		self._profile = Quality.BuildProfile(self.Level, self.Overrides)
	end
	return self._profile
end

--[[
	Applies particle budgets to a list of specs in place. Only specs with a
	`Particle` block are affected. Returns warnings.
]]
function Quality:ApplyBudget(specs: { any }): { string }
	local profile = self:GetProfile()
	local warnings = {}
	local particles = {}
	for _, spec in ipairs(specs) do
		if spec.Particle then
			spec.Properties.Rate = (spec.Particle.BaseRate or 0) * profile.ParticleRateScale
			table.insert(particles, spec)
		end
	end
	-- Deterministic priority order: highest priority first, then by ID.
	table.sort(particles, function(a, b)
		if a.Particle.Priority ~= b.Particle.Priority then
			return a.Particle.Priority > b.Particle.Priority
		end
		return a.ID < b.ID
	end)
	local disabled = {}
	local active = 0
	for _, spec in ipairs(particles) do
		if spec.Properties.Enabled ~= false then
			active += 1
			if active > profile.MaxParticleSystems then
				spec.Properties.Enabled = false
				spec.QualityDisabled = true
				table.insert(disabled, spec.ID)
			end
		end
	end
	if #disabled > 0 then
		table.sort(disabled)
		table.insert(
			warnings,
			string.format(
				"Quality %s allows %d particle systems; disabled lowest-priority systems: %s",
				profile.Level,
				profile.MaxParticleSystems,
				table.concat(disabled, ", ")
			)
		)
	end
	local total = 0
	for _, spec in ipairs(particles) do
		if spec.Properties.Enabled ~= false then
			total += spec.Properties.Rate
		end
	end
	local budgetScale = 1
	if total > profile.MaxParticleRate and total > 0 then
		budgetScale = profile.MaxParticleRate / total
		for _, spec in ipairs(particles) do
			spec.Properties.Rate *= budgetScale
		end
		table.insert(
			warnings,
			string.format(
				"Total particle rate %d/s exceeds the %s budget of %d/s; all rates scaled by %.2f",
				math.floor(total + 0.5),
				profile.Level,
				profile.MaxParticleRate,
				budgetScale
			)
		)
	end
	for _, spec in ipairs(particles) do
		spec.Properties.Rate = Util.round(spec.Properties.Rate, 3)
	end
	self.LastBudget = { RateScale = profile.ParticleRateScale, BudgetScale = budgetScale, Disabled = disabled }
	return warnings
end

--[[
	Validation check: warns about configurations that will be throttled
	by the current profile (performance validation step of the pipeline).
]]
function Quality:CheckConfiguration(engine, normalized, report)
	local ok, specs = pcall(function()
		return engine.Scene:BuildSpecs(engine.Scene:Resolve(normalized), { SkipBudget = true })
	end)
	if not ok then
		return
	end
	local profile = self:GetProfile()
	local count, total = 0, 0
	for _, spec in ipairs(specs) do
		if spec.Particle and spec.Properties.Enabled ~= false then
			count += 1
			total += (spec.Particle.BaseRate or 0) * profile.ParticleRateScale
		end
	end
	if count > profile.MaxParticleSystems then
		report:Warn(
			"Particles",
			"PerformanceBudget",
			string.format("%d particle systems exceed the %s limit of %d; lowest priority systems will be disabled", count, profile.Level, profile.MaxParticleSystems)
		)
	end
	if total > profile.MaxParticleRate then
		report:Warn(
			"Particles",
			"PerformanceBudget",
			string.format("estimated %d particles/s exceeds the %s budget of %d/s; rates will be scaled down", math.floor(total), profile.Level, profile.MaxParticleRate)
		)
	end
end

return Quality
