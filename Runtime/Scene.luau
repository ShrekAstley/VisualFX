--[[
	VisualFX.Runtime.Scene

	The reconciler. Every mutation in VisualFX goes through the same steps:

	  authored configuration
	      │  Resolve   (preset inheritance, day/night seed, weather composition)
	      ▼
	  resolved configuration
	      │  BuildSpecs (each section declares the instances/properties it wants)
	      ▼
	  desired specs  { ID, Type, ClassName | Target, Parent, Properties, ... }
	      │  Plan      (locate by identity, adopt, diff properties, find removals)
	      ▼
	  plan           { Steps, Added, Modified, Removed, Unchanged, Warnings }
	      │  Execute   (only the differences are written)
	      ▼
	  result

	Because Plan is side-effect free, DiffScene and dry runs use exactly the
	same logic as Apply. Instances are always located by managed identity
	first, so re-applying a configuration never creates duplicates.
]]

local Core = script.Parent.Parent.Core
local Util = require(Core.Util)
local Values = require(Core.Values)
local Config = require(Core.Config)
local Weather = require(script.Parent.Weather)
local Environment = require(script.Parent.Environment)
local CustomEffects = require(script.Parent.CustomEffects)

local Scene = {}
Scene.__index = Scene

Scene.ROOT_ID = "root"

function Scene.new(engine)
	local self = setmetatable({}, Scene)
	self.Engine = engine
	self._runtimeApplied = {} -- ID -> { [property] = last desired value } for runtime-owned properties
	return self
end

---------------------------------------------------------------------------
-- Resolve
---------------------------------------------------------------------------

function Scene:Resolve(authored: { [string]: any }): { [string]: any }
	local engine = self.Engine
	local expanded = authored
	if authored.Inherits and engine.Presets then
		expanded = engine.Presets:Expand(authored)
	end
	local resolved = Config.stripRemovals(Util.deepCopy(expanded))
	resolved.Inherits = nil
	Environment.Resolve(resolved)
	Weather.Resolve(engine.Registry, resolved, expanded)
	return resolved
end

---------------------------------------------------------------------------
-- Desired specs
---------------------------------------------------------------------------

function Scene:MakeContext(resolved: { [string]: any })
	local engine = self.Engine
	return setmetatable({
		Quality = engine.Quality:GetProfile(),
		Resolved = resolved,
	}, { __index = engine.Context })
end

--[[
	Marks properties that runtime controllers own (day/night ClockTime, zone
	atmosphere blending, camera-following volumes). They are written when the
	desired value changes, but live drift is not treated as a difference.
]]
local function applyRuntimeOwnership(specs, resolved)
	local environment = resolved.Environment
	local dayNight = environment and environment.DayNight
	local zoneAtmosphere = {}
	for _, zone in pairs(environment and environment.Zones or {}) do
		for key in pairs(zone.Atmosphere or {}) do
			zoneAtmosphere[key] = true
		end
	end
	for _, spec in ipairs(specs) do
		if spec.ID == "lighting" and dayNight and dayNight.Enabled then
			spec.RuntimeProperties = spec.RuntimeProperties or {}
			spec.RuntimeProperties.ClockTime = true
			if dayNight.DriveLighting then
				for _, property in ipairs({ "Brightness", "OutdoorAmbient", "Ambient", "ColorShift_Top" }) do
					spec.RuntimeProperties[property] = true
				end
			end
		elseif spec.ID == "atmosphere.primary" then
			if dayNight and dayNight.Enabled and dayNight.DriveLighting then
				spec.RuntimeProperties = spec.RuntimeProperties or {}
				spec.RuntimeProperties.Color = true
				spec.RuntimeProperties.Decay = true
			end
			for key in pairs(zoneAtmosphere) do
				spec.RuntimeProperties = spec.RuntimeProperties or {}
				spec.RuntimeProperties[key] = true
			end
		end
	end
end

--[[
	Builds the ordered list of desired specs for a resolved configuration.
	options.SkipBudget: do not apply quality budgets (used for estimates).
	Returns specs, warnings.
]]
function Scene:BuildSpecs(resolved: { [string]: any }, options: { [string]: any }?): ({ any }, { string })
	local opts = options or {}
	local engine = self.Engine
	local registry = engine.Registry
	local context = self:MakeContext(resolved)
	local specs, warnings = {}, {}
	local usesRoot = false
	for _, sectionName in ipairs(registry.SectionOrder) do
		local section = registry.Sections[sectionName]
		local value = resolved[sectionName]
		if section.Desired and (value ~= nil or sectionName == "Weather") then
			local ok, result = pcall(section.Desired, value or {}, context, resolved)
			if not ok then
				table.insert(warnings, string.format("%s: failed to build effects: %s", sectionName, tostring(result)))
			else
				for _, spec in ipairs(result) do
					spec.Section = spec.Section or sectionName
					spec.Properties = spec.Properties or {}
					spec.Depth = spec.Depth or (if spec.ParentID then 1 else 0)
					if spec.ParentID == Scene.ROOT_ID then
						usesRoot = true
					end
					table.insert(specs, spec)
				end
			end
		end
	end
	if usesRoot then
		table.insert(specs, {
			ID = Scene.ROOT_ID,
			Type = "Folder",
			ClassName = "Folder",
			Name = "VisualFX",
			Parent = context.Workspace,
			Section = "_Root",
			Properties = {},
			Depth = 0,
			Hidden = true,
		})
	end
	for _, spec in ipairs(specs) do
		if spec.ClassName == "Part" then
			spec.Hidden = true
		end
	end
	applyRuntimeOwnership(specs, resolved)
	if not opts.SkipBudget then
		Util.append(warnings, engine.Quality:ApplyBudget(specs))
	end
	table.sort(specs, function(a, b)
		if a.Depth ~= b.Depth then
			return a.Depth < b.Depth
		end
		return a.ID < b.ID
	end)
	return specs, warnings
end

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------

local function epsilonFor(spec, property: string): number?
	local field = spec.FieldsByProperty and spec.FieldsByProperty[property]
	return field and field.Epsilon
end

local function depthOf(instance: Instance): number
	local depth = 0
	local node = instance.Parent
	while node do
		depth += 1
		node = node.Parent
	end
	return depth
end

function Scene:_Locate(spec, plan)
	local manager = self.Engine.InstanceManager
	if spec.Target then
		return spec.Target, "Target"
	end
	local matches = plan.Snapshot.ByID[spec.ID] or {}
	if #matches > 1 then
		local extras = {}
		for index = 2, #matches do
			table.insert(extras, matches[index])
		end
		table.insert(plan.Steps, { Kind = "RemoveDuplicates", ID = spec.ID, Instances = extras })
		table.insert(
			plan.Warnings,
			string.format("%d duplicate managed instances found for %s; keeping one and removing %d", #matches, spec.ID, #extras)
		)
	end
	if matches[1] then
		return matches[1], if manager:IsAdopted(matches[1]) then "Adopted" else "Found"
	end
	if spec.Adopt and spec.Parent then
		local candidate, count = manager:FindAdoptable(spec.Parent, spec.ClassName)
		if candidate then
			if count > 1 then
				table.insert(
					plan.Warnings,
					string.format(
						"%d unmanaged %s instances exist in %s; adopted '%s' and left the others untouched (Roblox only renders one)",
						count,
						spec.ClassName,
						spec.Parent:GetFullName(),
						candidate.Name
					)
				)
			end
			return candidate, "Adopt"
		end
	end
	return nil, nil
end

--[[
	Computes what must change for the scene to match `resolved`.
	options:
	  Scope            { [sectionName] = true } sections that may lose effects (nil = all)
	  RemoveRoot       also remove the Workspace.VisualFX folder when unused
	Returns a plan (no side effects).
]]
function Scene:Plan(resolved: { [string]: any }, options: { [string]: any }?)
	local opts = options or {}
	local engine = self.Engine
	local compatibility = engine.Compatibility
	local manager = engine.InstanceManager
	local specs, buildWarnings = self:BuildSpecs(resolved)
	local plan = {
		Resolved = resolved,
		Specs = specs,
		Steps = {},
		Added = {},
		Modified = {},
		Removed = {},
		Unchanged = {},
		Warnings = Util.append({}, buildWarnings),
		Changes = {},
		Snapshot = manager:Snapshot(),
	}
	local desiredIds = {}
	for _, spec in ipairs(specs) do
		desiredIds[spec.ID] = spec
	end
	local function inScope(section: string?): boolean
		if opts.Scope == nil then
			return true
		end
		return section ~= nil and opts.Scope[section] == true
	end

	-- Removals first (their pooled instances can be reused by creations).
	local removals = {}
	for _, instance in ipairs(plan.Snapshot.All) do
		local identity = manager:GetIdentity(instance)
		if identity and identity.ID and not desiredIds[identity.ID] then
			local removable = inScope(identity.Section)
			if identity.ID == Scene.ROOT_ID then
				removable = opts.RemoveRoot == true
			end
			if removable then
				table.insert(removals, { Instance = instance, Identity = identity })
			end
		end
	end
	table.sort(removals, function(a, b)
		local da, db = depthOf(a.Instance), depthOf(b.Instance)
		if da ~= db then
			return da > db
		end
		return a.Identity.ID < b.Identity.ID
	end)
	for _, removal in ipairs(removals) do
		table.insert(plan.Steps, { Kind = "Remove", Instance = removal.Instance, Identity = removal.Identity })
		if not (removal.Instance.ClassName == "Part" or removal.Identity.ID == Scene.ROOT_ID) then
			table.insert(plan.Removed, { ID = removal.Identity.ID, Type = removal.Identity.Type, Adopted = removal.Identity.Adopted })
		end
	end

	-- Service targets whose section no longer declares them: restore originals.
	local context = self:MakeContext(resolved)
	for _, sectionName in ipairs(engine.Registry.SectionOrder) do
		local section = engine.Registry.Sections[sectionName]
		if section.Targets and inScope(sectionName) then
			for _, target in ipairs(section.Targets(context)) do
				if not desiredIds[target.ID] and target.Instance then
					for _, property in ipairs(manager:GetManagedProperties(target.Instance)) do
						local _, original = manager:GetOriginal(target.Instance, property)
						local okRead, current = compatibility:GetProperty(target.Instance, property)
						table.insert(plan.Steps, { Kind = "Restore", Instance = target.Instance, Property = property, ID = target.ID })
						table.insert(plan.Changes, {
							ID = target.ID,
							Type = sectionName,
							Property = property,
							From = if okRead then current else nil,
							To = original,
							Restore = true,
						})
						Util.addUnique(plan.Modified, sectionName)
					end
				end
			end
		end
	end

	-- Creations and updates.
	for _, spec in ipairs(specs) do
		local instance, how = self:_Locate(spec, plan)
		if instance and not spec.Target and not spec.Custom and instance.ClassName ~= spec.ClassName then
			table.insert(plan.Steps, { Kind = "Remove", Instance = instance, Identity = manager:GetIdentity(instance) })
			table.insert(
				plan.Warnings,
				string.format("%s was a %s but must be a %s; it will be replaced", spec.ID, instance.ClassName, tostring(spec.ClassName))
			)
			instance, how = nil, nil
		end

		if not instance then
			table.insert(plan.Steps, { Kind = "Create", Spec = spec })
			if not spec.Hidden then
				table.insert(plan.Added, { ID = spec.ID, Type = spec.Type, ClassName = spec.ClassName, Properties = spec.Properties })
			end
			for _, property in ipairs(Util.sortedKeys(spec.Properties)) do
				table.insert(plan.Changes, { ID = spec.ID, Type = spec.Type, Property = property, To = spec.Properties[property], Create = true })
			end
			continue
		end

		local changed = false
		if how == "Adopt" then
			table.insert(plan.Steps, { Kind = "Adopt", Spec = spec, Instance = instance })
			table.insert(plan.Changes, { ID = spec.ID, Type = spec.Type, Adopt = true, Instance = instance:GetFullName() })
			changed = true
		end

		if spec.Custom then
			local ok, fingerprint = pcall(instance.GetAttribute, instance, CustomEffects.HASH_ATTRIBUTE)
			if not ok or fingerprint ~= spec.Fingerprint then
				table.insert(plan.Steps, { Kind = "UpdateCustom", Spec = spec, Instance = instance })
				table.insert(plan.Changes, { ID = spec.ID, Type = spec.Type, Property = "<configuration>" })
				changed = true
			end
		end

		local recordOriginal = how == "Target" or how == "Adopt" or how == "Adopted"
		local runtimeApplied = self._runtimeApplied[spec.ID]
		for _, property in ipairs(Util.sortedKeys(spec.Properties)) do
			local desired = spec.Properties[property]
			if not compatibility:HasProperty(instance, property) then
				table.insert(
					plan.Warnings,
					string.format("%s.%s is not supported by this engine version; skipped", instance.ClassName, property)
				)
				continue
			end
			local isRuntime = spec.RuntimeProperties and spec.RuntimeProperties[property]
			if isRuntime and runtimeApplied and runtimeApplied[property] ~= nil and Values.equal(runtimeApplied[property], desired) then
				continue
			end
			local okRead, current = compatibility:GetProperty(instance, property)
			if not okRead or not Values.equal(current, desired, epsilonFor(spec, property)) then
				table.insert(plan.Steps, {
					Kind = "Set",
					Spec = spec,
					Instance = instance,
					Property = property,
					Value = desired,
					RecordOriginal = recordOriginal,
				})
				table.insert(plan.Changes, {
					ID = spec.ID,
					Type = spec.Type,
					Property = property,
					From = if okRead then current else nil,
					To = desired,
				})
				changed = true
			end
			if isRuntime then
				table.insert(plan.Steps, { Kind = "RuntimeApplied", ID = spec.ID, Property = property, Value = desired })
			end
		end

		-- Properties VisualFX managed before but the configuration no longer sets.
		if recordOriginal then
			for _, property in ipairs(manager:GetManagedProperties(instance)) do
				if spec.Properties[property] == nil then
					local _, original = manager:GetOriginal(instance, property)
					local okRead, current = compatibility:GetProperty(instance, property)
					table.insert(plan.Steps, { Kind = "Restore", Instance = instance, Property = property, ID = spec.ID })
					table.insert(plan.Changes, {
						ID = spec.ID,
						Type = spec.Type,
						Property = property,
						From = if okRead then current else nil,
						To = original,
						Restore = true,
					})
					changed = true
				end
			end
		end

		-- Re-parent if the managed instance was moved.
		if not spec.Target and how ~= "Adopt" then
			local expectedParent = spec.Parent
			if not expectedParent and spec.ParentID then
				local parents = plan.Snapshot.ByID[spec.ParentID]
				expectedParent = parents and parents[1]
			end
			if expectedParent and instance.Parent ~= expectedParent then
				table.insert(plan.Steps, { Kind = "Parent", Spec = spec, Instance = instance })
				changed = true
			end
		end

		if changed then
			if not spec.Hidden then
				Util.addUnique(plan.Modified, spec.Type)
			end
		elseif not spec.Hidden then
			table.insert(plan.Unchanged, spec.ID)
		end
	end
	return plan
end

---------------------------------------------------------------------------
-- Execute
---------------------------------------------------------------------------

function Scene:_ResolveParent(spec, created)
	if spec.Parent then
		return spec.Parent
	end
	if spec.ParentID then
		return created[spec.ParentID] or self.Engine.InstanceManager:Find(spec.ParentID)
	end
	return nil
end

function Scene:_RemoveInstance(instance: Instance, identity, warnings)
	local engine = self.Engine
	local definition = identity and identity.Type and engine.Registry:GetEffect(identity.Type)
	if definition and definition.Remove and string.sub(identity.ID or "", 1, 7) == "effect." then
		local ok, problem = pcall(definition.Remove, instance, engine.Context)
		if not ok then
			table.insert(warnings, string.format("%s: Remove failed: %s", identity.ID, tostring(problem)))
		end
		local alive = pcall(function()
			return instance.Parent
		end)
		if not alive or instance.Parent == nil then
			return
		end
	end
	local ok, problem = engine.InstanceManager:Remove(instance)
	if not ok and problem then
		table.insert(warnings, problem)
	end
	self._runtimeApplied[identity and identity.ID or ""] = nil
	engine.Events.EffectRemoved:Fire({ ID = identity and identity.ID, Type = identity and identity.Type })
end

--[[
	Executes a plan. Returns { Created, Modified, Removed, Changes, Warnings }
	with effect type names suitable for summaries.
]]
function Scene:Execute(plan)
	local engine = self.Engine
	local manager = engine.InstanceManager
	local warnings = Util.append({}, plan.Warnings)
	local created = {}
	local createdTypes = {}
	for _, step in ipairs(plan.Steps) do
		local kind = step.Kind
		if kind == "RemoveDuplicates" then
			for _, instance in ipairs(step.Instances) do
				self:_RemoveInstance(instance, manager:GetIdentity(instance), warnings)
			end
		elseif kind == "Remove" then
			self:_RemoveInstance(step.Instance, step.Identity, warnings)
		elseif kind == "Restore" then
			local ok, problem = manager:RestoreOriginal(step.Instance, step.Property)
			if not ok and problem and problem ~= "no original value recorded" then
				table.insert(warnings, string.format("%s.%s: %s", step.Instance.Name, step.Property, problem))
			end
		elseif kind == "Create" then
			local spec = step.Spec
			local parent = self:_ResolveParent(spec, created)
			if not parent then
				table.insert(warnings, string.format("%s: parent %s is not available; skipped", spec.ID, tostring(spec.ParentID)))
				continue
			end
			local instance
			if spec.Custom then
				local ok, result = pcall(spec.Custom.Create, Util.deepCopy(spec.Config), engine.Context)
				if not ok or typeof(result) ~= "Instance" then
					table.insert(
						warnings,
						string.format("%s: Create did not return an Instance (%s)", spec.ID, if ok then typeof(result) else tostring(result))
					)
					continue
				end
				instance = result
				manager:Mark(instance, spec, false)
				pcall(instance.SetAttribute, instance, CustomEffects.HASH_ATTRIBUTE, spec.Fingerprint)
				if instance.Parent == nil then
					instance.Parent = parent
				end
			else
				local createWarnings
				instance, createWarnings = manager:Create(spec, parent)
				Util.append(warnings, createWarnings)
			end
			if instance then
				created[spec.ID] = instance
				if spec.RuntimeProperties then
					self._runtimeApplied[spec.ID] = {}
					for property in pairs(spec.RuntimeProperties) do
						self._runtimeApplied[spec.ID][property] = spec.Properties[property]
					end
				end
				if not spec.Hidden then
					Util.addUnique(createdTypes, spec.Type)
				end
				engine.Events.EffectCreated:Fire({ ID = spec.ID, Type = spec.Type, Instance = instance })
			end
		elseif kind == "Adopt" then
			manager:Mark(step.Instance, step.Spec, true)
			table.insert(warnings, string.format("Adopted existing %s for %s (original values are recorded and restored on reset)", step.Instance:GetFullName(), step.Spec.ID))
		elseif kind == "UpdateCustom" then
			local spec = step.Spec
			if spec.Custom.Update then
				local ok, problem = pcall(spec.Custom.Update, step.Instance, Util.deepCopy(spec.Config), engine.Context)
				if not ok then
					table.insert(warnings, string.format("%s: Update failed: %s", spec.ID, tostring(problem)))
				end
			end
			pcall(step.Instance.SetAttribute, step.Instance, CustomEffects.HASH_ATTRIBUTE, spec.Fingerprint)
		elseif kind == "Set" then
			local ok, problem = manager:SetProperty(step.Instance, step.Property, step.Value, { RecordOriginal = step.RecordOriginal })
			if not ok and problem then
				table.insert(warnings, problem)
			end
		elseif kind == "RuntimeApplied" then
			self._runtimeApplied[step.ID] = self._runtimeApplied[step.ID] or {}
			self._runtimeApplied[step.ID][step.Property] = step.Value
		elseif kind == "Parent" then
			local parent = self:_ResolveParent(step.Spec, created)
			if parent then
				step.Instance.Parent = parent
			end
		end
	end

	local modified = {}
	for _, typeName in ipairs(plan.Modified) do
		if not table.find(createdTypes, typeName) then
			table.insert(modified, typeName)
		end
	end
	local removed = {}
	for _, entry in ipairs(plan.Removed) do
		Util.addUnique(removed, entry.Type)
	end
	return {
		Created = createdTypes,
		Modified = modified,
		Removed = removed,
		Changes = plan.Changes,
		Warnings = warnings,
	}
end

-- Human-readable diff lines for UIs and logs.
function Scene.FormatDiff(plan): { string }
	local lines = {}
	for _, entry in ipairs(plan.Added) do
		table.insert(lines, string.format("+ %s (%s)", entry.Type, entry.ID))
	end
	for _, entry in ipairs(plan.Removed) do
		table.insert(lines, string.format("- %s (%s)%s", entry.Type, entry.ID, if entry.Adopted then " [released]" else ""))
	end
	for _, change in ipairs(plan.Changes) do
		if not change.Create and change.Property then
			table.insert(
				lines,
				string.format(
					"~ %s.%s: %s -> %s%s",
					change.Type,
					change.Property,
					Values.describe(change.From),
					Values.describe(change.To),
					if change.Restore then " (restore original)" else ""
				)
			)
		elseif change.Adopt then
			table.insert(lines, string.format("* adopt %s as %s", change.Instance, change.ID))
		end
	end
	for _, warning in ipairs(plan.Warnings) do
		table.insert(lines, "! " .. warning)
	end
	return lines
end

return Scene
