--[[
	VisualFX.Runtime.Transitions

	Smooth transitions between configurations.

	  VisualFX:TransitionTo({
	      Duration = 8,
	      Easing = "Smooth",            -- Linear | Smooth | Sine | Quad | Cubic | Quart | Expo | Back
	      EasingDirection = "InOut",    -- In | Out | InOut
	      Configuration = { Lighting = {...}, Atmosphere = {...}, Weather = {...} },
	  })

	How it works:
	  1. The target configuration is resolved and planned by the Scene reconciler.
	  2. New effects are created in a neutral state (particle Rate 0, bloom
	     Intensity 0, ...) and faded in. Effects that will be removed fade to
	     neutral first and are removed at the end.
	  3. Interpolable values (number, Color3, Vector3/2, NumberRange,
	     NumberSequence, ColorSequence) are tweened. Booleans that turn on switch
	     at the start; booleans that turn off, and non-interpolable values that
	     only matter at the end, switch at the end.
	  4. Updates run at the quality profile's TransitionFrequency and a property
	     is only written when its value actually changes.
	  5. When the transition completes, the exact target plan is executed, so
	     the final state is identical to an instant apply.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)
local Values = require(Core.Values)

local Transitions = {}
Transitions.__index = Transitions

---------------------------------------------------------------------------
-- Easing
---------------------------------------------------------------------------

local EasingIn = {
	Linear = function(t)
		return t
	end,
	Sine = function(t)
		return 1 - math.cos(t * math.pi / 2)
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t * t * t * t
	end,
	Quint = function(t)
		return t * t * t * t * t
	end,
	Expo = function(t)
		return if t == 0 then 0 else 2 ^ (10 * t - 10)
	end,
	Circular = function(t)
		return 1 - math.sqrt(1 - t * t)
	end,
	Back = function(t)
		local c = 1.70158
		return (c + 1) * t * t * t - c * t * t
	end,
}

Transitions.EasingStyles = { "Linear", "Smooth", "Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Circular", "Back" }

--[[
	Returns an easing function f(t) for a style/direction. Accepts names or
	Roblox Enum.EasingStyle / Enum.EasingDirection items.
]]
function Transitions.GetEasing(style: any, direction: any): (number) -> number
	local styleName = if typeof(style) == "EnumItem" then style.Name else (style or "Smooth")
	local directionName = if typeof(direction) == "EnumItem" then direction.Name else (direction or "InOut")
	-- Allow combined names such as "SineInOut" or "QuadOut".
	if typeof(styleName) == "string" then
		for _, suffix in ipairs({ "InOut", "Out", "In" }) do
			if #styleName > #suffix and string.sub(styleName, -#suffix) == suffix and EasingIn[string.sub(styleName, 1, -#suffix - 1)] then
				directionName = suffix
				styleName = string.sub(styleName, 1, -#suffix - 1)
				break
			end
		end
	end
	if styleName == "Smooth" then
		return function(t)
			return t * t * (3 - 2 * t)
		end
	end
	local easeIn = EasingIn[styleName] or EasingIn.Linear
	if directionName == "In" then
		return easeIn
	elseif directionName == "Out" then
		return function(t)
			return 1 - easeIn(1 - t)
		end
	end
	return function(t)
		if t < 0.5 then
			return easeIn(t * 2) / 2
		end
		return 1 - easeIn((1 - t) * 2) / 2
	end
end

---------------------------------------------------------------------------
-- Transition manager
---------------------------------------------------------------------------

local NEUTRAL_BY_CLASS = {
	ParticleEmitter = { Rate = 0 },
	BloomEffect = { Intensity = 0 },
	SunRaysEffect = { Intensity = 0 },
	BlurEffect = { Size = 0 },
	DepthOfFieldEffect = { FarIntensity = 0, NearIntensity = 0 },
	ColorCorrectionEffect = {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	},
	Atmosphere = { Density = 0, Haze = 0, Glare = 0 },
	Clouds = { Cover = 0 },
}

function Transitions.new(engine)
	local self = setmetatable({}, Transitions)
	self.Engine = engine
	self._active = nil
	self._nextId = 0
	return self
end

function Transitions:IsActive(): boolean
	return self._active ~= nil
end

function Transitions:GetActive()
	local active = self._active
	if not active then
		return nil
	end
	return {
		Id = active.Id,
		Duration = active.Duration,
		Elapsed = active.Elapsed,
		Progress = if active.Duration > 0 then math.min(1, active.Elapsed / active.Duration) else 1,
		Tracks = #active.Tracks,
	}
end

local function neutralFor(spec, className: string, property: string): any
	local field = spec and spec.FieldsByProperty and spec.FieldsByProperty[property]
	if field and field.Neutral ~= nil then
		return field.Neutral
	end
	local byClass = NEUTRAL_BY_CLASS[className]
	return byClass and byClass[property]
end

--[[
	Starts a transition to `resolved` (a resolved configuration).
	options: { Duration, Easing, EasingDirection, Scope, OnComplete }
	Returns a summary table.
]]
function Transitions:Start(resolved: { [string]: any }, options: { [string]: any })
	local engine = self.Engine
	local scene = engine.Scene
	local manager = engine.InstanceManager
	local compatibility = engine.Compatibility

	if self._active then
		self:Cancel(false)
	end

	local plan = scene:Plan(resolved, { Scope = options.Scope })
	local tracks = {}
	local startSteps = {}

	local function addTrack(instance: Instance?, spec, property: string, from: any, to: any, recordOriginal: boolean?, specId: string?)
		local field = spec and spec.FieldsByProperty and spec.FieldsByProperty[property]
		local wrap = field and field.Wrap
		if wrap and typeof(from) == "number" and typeof(to) == "number" then
			-- Cyclic values (ClockTime) take the shortest way around.
			local delta = (to - from) % wrap
			if delta > wrap / 2 then
				delta -= wrap
			end
			to = from + delta
		end
		table.insert(tracks, {
			Wrap = wrap,
			Instance = instance,
			SpecID = specId,
			Property = property,
			From = from,
			To = to,
			Epsilon = spec and spec.FieldsByProperty and spec.FieldsByProperty[property] and spec.FieldsByProperty[property].Epsilon,
			RecordOriginal = recordOriginal,
			Last = from,
		})
	end

	for _, step in ipairs(plan.Steps) do
		if step.Kind == "Create" and not step.Spec.Custom then
			-- Start new effects neutral, then fade them in.
			local spec = step.Spec
			local startSpec = Util.shallowCopy(spec)
			startSpec.Properties = Util.shallowCopy(spec.Properties)
			for property, target in pairs(spec.Properties) do
				local neutral = neutralFor(spec, spec.ClassName, property)
				if neutral ~= nil and Values.InterpolableKinds[typeof(target)] and typeof(neutral) == typeof(target) then
					startSpec.Properties[property] = neutral
					addTrack(nil, spec, property, neutral, target, false, spec.ID)
				end
			end
			table.insert(startSteps, { Kind = "Create", Spec = startSpec })
		elseif step.Kind == "Set" then
			local from = step.Instance and select(2, compatibility:GetProperty(step.Instance, step.Property))
			if Values.InterpolableKinds[typeof(step.Value)] and typeof(from) == typeof(step.Value) then
				if step.RecordOriginal then
					manager:RecordOriginal(step.Instance, step.Property)
				end
				addTrack(step.Instance, step.Spec, step.Property, from, step.Value, false)
			elseif step.Value == false then
				-- Switching off happens at the end, via the final exact plan.
				continue
			else
				table.insert(startSteps, step)
			end
		elseif step.Kind == "Remove" then
			-- Fade out before removal (removal itself happens in the final plan).
			local instance = step.Instance
			local neutral = NEUTRAL_BY_CLASS[instance.ClassName]
			if neutral then
				for property, value in pairs(neutral) do
					local ok, current = compatibility:GetProperty(instance, property)
					if ok and typeof(current) == typeof(value) then
						addTrack(instance, nil, property, current, value, false)
					end
				end
			end
		elseif step.Kind == "Restore" then
			local has, original = manager:GetOriginal(step.Instance, step.Property)
			local ok, current = compatibility:GetProperty(step.Instance, step.Property)
			if has and ok and Values.InterpolableKinds[typeof(original)] and typeof(current) == typeof(original) then
				addTrack(step.Instance, nil, step.Property, current, original, false)
			end
		elseif step.Kind ~= "RuntimeApplied" and step.Kind ~= "UpdateCustom" and not (step.Kind == "Create" and step.Spec.Custom) then
			table.insert(startSteps, step)
		end
	end

	-- Execute the start steps (creations in neutral state, adoption, switches).
	local startResult = scene:Execute({
		Steps = startSteps,
		Added = {},
		Modified = {},
		Removed = {},
		Warnings = {},
		Changes = {},
	})
	for _, track in ipairs(tracks) do
		if not track.Instance and track.SpecID then
			track.Instance = manager:Find(track.SpecID)
		end
	end

	self._nextId += 1
	local id = "transition-" .. self._nextId
	local duration = math.max(0, options.Duration or 0)
	self._active = {
		Id = id,
		Duration = duration,
		Elapsed = 0,
		Accumulated = 0,
		Ease = Transitions.GetEasing(options.Easing, options.EasingDirection),
		Tracks = tracks,
		Resolved = resolved,
		Scope = options.Scope,
		OnComplete = options.OnComplete,
		Plan = plan,
	}
	engine.Events.TransitionStarted:Fire({ Id = id, Duration = duration })
	if duration <= 0 then
		self:Step(0)
	end
	return {
		Id = id,
		Duration = duration,
		Tracks = #tracks,
		Plan = plan,
		Warnings = startResult.Warnings,
	}
end

function Transitions:_WriteTracks(alpha: number)
	local compatibility = self.Engine.Compatibility
	for _, track in ipairs(self._active.Tracks) do
		local instance = track.Instance
		if instance and instance.Parent then
			local value = Values.lerp(track.From, track.To, alpha)
			if track.Wrap then
				value = value % track.Wrap
			end
			if not Values.equal(value, track.Last, track.Epsilon) then
				compatibility:SetProperty(instance, track.Property, value)
				track.Last = value
			end
		end
	end
end

--[[
	Advances the active transition. Called by the VisualFX scheduler; can be
	called manually (e.g. from tests or edit-mode previews).
]]
function Transitions:Step(dt: number)
	local active = self._active
	if not active then
		return
	end
	active.Elapsed += dt
	active.Accumulated += dt
	local profile = self.Engine.Quality:GetProfile()
	local interval = 1 / math.max(1, profile.TransitionFrequency)
	local finished = active.Elapsed >= active.Duration
	if not finished and active.Accumulated < interval then
		return
	end
	active.Accumulated = 0
	local t = if active.Duration > 0 then Util.clamp(active.Elapsed / active.Duration, 0, 1) else 1
	self:_WriteTracks(active.Ease(t))
	if finished then
		self:_Finish(false)
	end
end

function Transitions:_Finish(cancelled: boolean)
	local active = self._active
	if not active then
		return
	end
	self._active = nil
	local result = nil
	if not cancelled then
		-- Execute the exact target so the end state equals an instant apply.
		local engine = self.Engine
		local plan = engine.Scene:Plan(active.Resolved, { Scope = active.Scope })
		result = engine.Scene:Execute(plan)
	end
	if active.OnComplete then
		pcall(active.OnComplete, result, cancelled)
	end
	self.Engine.Events.TransitionCompleted:Fire({ Id = active.Id, Cancelled = cancelled, Result = result })
end

--[[
	Cancels the active transition. complete = true jumps to the final state;
	otherwise the scene stays at its current intermediate values.
]]
function Transitions:Cancel(complete: boolean?)
	if not self._active then
		return false
	end
	if complete then
		self:_WriteTracks(1)
		self:_Finish(false)
	else
		self:_Finish(true)
	end
	return true
end

return Transitions
