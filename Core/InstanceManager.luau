--[[
	VisualFX.Core.InstanceManager

	Owns every interaction between VisualFX and real Roblox instances:

	  * Managed identity. Every object VisualFX creates or adopts carries
	      Attribute VisualFX_Managed = true
	      Attribute VisualFX_ID      = "weather.rain.primary"
	      Attribute VisualFX_Type    = "Rain"
	      Attribute VisualFX_Section = "Weather"
	    plus the CollectionService tag "VisualFX". (Roblox attribute names
	    cannot contain ".", so "VisualFX.Managed" is spelled VisualFX_Managed.)

	  * Duplicate prevention. Instances are always looked up by identity
	    before anything is created; duplicate managed copies are collapsed.

	  * Original values. Before VisualFX writes a property on an instance it
	    did not create (Lighting, Terrain, an adopted Atmosphere), the original
	    value is stored in an attribute "VisualFX_Orig_<Property>" so it can
	    be restored later, even after the place is saved and reopened.

	  * Journal. While a journal is open (preview mode) every mutation is
	    recorded so it can be reverted exactly. Reverting never overwrites a
	    property a developer changed after VisualFX wrote it.

	Unknown or developer-owned instances are never destroyed.
]]

local Util = require(script.Parent.Util)
local Values = require(script.Parent.Values)

local InstanceManager = {}
InstanceManager.__index = InstanceManager

InstanceManager.TAG = "VisualFX"
InstanceManager.ATTR_MANAGED = "VisualFX_Managed"
InstanceManager.ATTR_ID = "VisualFX_ID"
InstanceManager.ATTR_TYPE = "VisualFX_Type"
InstanceManager.ATTR_SECTION = "VisualFX_Section"
InstanceManager.ATTR_OWNER = "VisualFX_Owner"
InstanceManager.ATTR_ADOPTED = "VisualFX_Adopted"
InstanceManager.ORIGINAL_PREFIX = "VisualFX_Orig_"

local ENUM_PREFIX = "VisualFXEnum:"
local NIL_MARKER = "VisualFXNil:"

local function getCollectionService()
	local ok, service = pcall(function()
		return game:GetService("CollectionService")
	end)
	return if ok then service else nil
end

function InstanceManager.new(compatibility)
	local self = setmetatable({}, InstanceManager)
	self.Compatibility = compatibility
	self.CollectionService = getCollectionService()
	self._index = {} -- id -> instance cache
	self._memoryOriginals = setmetatable({}, { __mode = "k" }) -- fallback when attributes fail
	self._journal = nil
	self._pool = {}
	self.PoolLimit = 16
	self.SearchRoots = nil -- optional override (tests / isolated scenes)
	return self
end

---------------------------------------------------------------------------
-- Attributes helpers
---------------------------------------------------------------------------

local function getAttribute(instance: Instance, name: string): any
	local ok, value = pcall(instance.GetAttribute, instance, name)
	return if ok then value else nil
end

function InstanceManager:_setAttribute(instance: Instance, name: string, value: any): boolean
	local before = getAttribute(instance, name)
	local ok = pcall(instance.SetAttribute, instance, name, value)
	if ok and self._journal and not self._journal.CreatedSet[instance] then
		table.insert(self._journal.Entries, { Kind = "Attribute", Instance = instance, Name = name, Before = before })
	end
	return ok
end

function InstanceManager:IsManaged(instance: Instance): boolean
	return getAttribute(instance, InstanceManager.ATTR_MANAGED) == true
end

function InstanceManager:IsAdopted(instance: Instance): boolean
	return getAttribute(instance, InstanceManager.ATTR_ADOPTED) == true
end

function InstanceManager:GetIdentity(instance: Instance)
	if not self:IsManaged(instance) then
		return nil
	end
	return {
		ID = getAttribute(instance, InstanceManager.ATTR_ID),
		Type = getAttribute(instance, InstanceManager.ATTR_TYPE),
		Section = getAttribute(instance, InstanceManager.ATTR_SECTION),
		Owner = getAttribute(instance, InstanceManager.ATTR_OWNER),
		Adopted = getAttribute(instance, InstanceManager.ATTR_ADOPTED) == true,
	}
end

-- Stamps the managed identity onto an instance.
function InstanceManager:Mark(instance: Instance, spec: { [string]: any }, adopted: boolean?)
	self:_setAttribute(instance, InstanceManager.ATTR_MANAGED, true)
	self:_setAttribute(instance, InstanceManager.ATTR_ID, spec.ID)
	self:_setAttribute(instance, InstanceManager.ATTR_TYPE, spec.Type or instance.ClassName)
	self:_setAttribute(instance, InstanceManager.ATTR_SECTION, spec.Section or "")
	self:_setAttribute(instance, InstanceManager.ATTR_OWNER, spec.Owner or "")
	if adopted then
		self:_setAttribute(instance, InstanceManager.ATTR_ADOPTED, true)
	end
	if self.CollectionService then
		pcall(self.CollectionService.AddTag, self.CollectionService, instance, InstanceManager.TAG)
	end
	self._index[spec.ID] = instance
end

-- Removes the managed identity (used when releasing an adopted instance).
function InstanceManager:Unmark(instance: Instance)
	local id = getAttribute(instance, InstanceManager.ATTR_ID)
	for _, name in ipairs({
		InstanceManager.ATTR_MANAGED,
		InstanceManager.ATTR_ID,
		InstanceManager.ATTR_TYPE,
		InstanceManager.ATTR_SECTION,
		InstanceManager.ATTR_OWNER,
		InstanceManager.ATTR_ADOPTED,
	}) do
		self:_setAttribute(instance, name, nil)
	end
	if self.CollectionService then
		pcall(self.CollectionService.RemoveTag, self.CollectionService, instance, InstanceManager.TAG)
	end
	if id and self._index[id] == instance then
		self._index[id] = nil
	end
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

--[[
	Places VisualFX creates or adopts instances in. Deep scans are limited to
	these containers (never the whole Workspace) so lookups stay cheap in
	large places.
]]
function InstanceManager:GetSearchRoots(): { Instance }
	if self.SearchRoots then
		return self.SearchRoots
	end
	local roots = {}
	local okLighting, lighting = pcall(function()
		return game:GetService("Lighting")
	end)
	if okLighting and lighting then
		table.insert(roots, lighting)
	end
	local okTerrain, terrain = pcall(function()
		return workspace.Terrain
	end)
	if okTerrain and terrain then
		table.insert(roots, terrain)
	end
	local folder = workspace:FindFirstChild("VisualFX")
	if folder then
		table.insert(roots, folder)
	end
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(roots, camera)
	end
	return roots
end

local function isAlive(instance: Instance?): boolean
	if not instance then
		return false
	end
	local ok, parent = pcall(function()
		return instance.Parent
	end)
	return ok and parent ~= nil
end

--[[
	All live managed instances, sorted deterministically by ID then full name.
	Tagged instances are always included; `deep` also scans the search roots
	(tags can be stripped by other tools, attributes survive).
]]
function InstanceManager:GetManaged(deep: boolean?): { Instance }
	local found, seen = {}, {}
	local function consider(instance: Instance)
		if not seen[instance] and isAlive(instance) and self:IsManaged(instance) then
			seen[instance] = true
			table.insert(found, instance)
		end
	end
	if self.CollectionService then
		local ok, tagged = pcall(self.CollectionService.GetTagged, self.CollectionService, InstanceManager.TAG)
		if ok then
			for _, instance in ipairs(tagged) do
				consider(instance)
			end
		end
	end
	if deep ~= false then
		for _, root in ipairs(self:GetSearchRoots()) do
			local ok, descendants = pcall(root.GetDescendants, root)
			if ok then
				for _, instance in ipairs(descendants) do
					consider(instance)
				end
			end
		end
	end
	table.sort(found, function(a, b)
		local ia, ib = tostring(getAttribute(a, InstanceManager.ATTR_ID)), tostring(getAttribute(b, InstanceManager.ATTR_ID))
		if ia ~= ib then
			return ia < ib
		end
		return a:GetFullName() < b:GetFullName()
	end)
	return found
end

--[[
	One deep scan, indexed by ID: { All = {...}, ByID = { [id] = { instances } } }.
	The reconciler uses a snapshot per plan instead of scanning per effect.
]]
function InstanceManager:Snapshot()
	local all = self:GetManaged(true)
	local byId = {}
	for _, instance in ipairs(all) do
		local id = getAttribute(instance, InstanceManager.ATTR_ID)
		if id then
			byId[id] = byId[id] or {}
			table.insert(byId[id], instance)
		end
	end
	return { All = all, ByID = byId }
end

function InstanceManager:FindAll(id: string): { Instance }
	return self:Snapshot().ByID[id] or {}
end

-- Finds a managed instance by identity: cache, then tags, then a deep scan.
function InstanceManager:Find(id: string): Instance?
	local cached = self._index[id]
	if cached and isAlive(cached) and getAttribute(cached, InstanceManager.ATTR_ID) == id then
		return cached
	end
	self._index[id] = nil
	for _, instance in ipairs(self:GetManaged(false)) do
		if getAttribute(instance, InstanceManager.ATTR_ID) == id then
			self._index[id] = instance
			return instance
		end
	end
	return nil
end

--[[
	Finds a developer-created (unmanaged) instance that can be adopted:
	same class, direct child of `parent`. Returns the first match in a
	stable order plus the total number of candidates.
]]
function InstanceManager:FindAdoptable(parent: Instance, className: string): (Instance?, number)
	local candidates = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child.ClassName == className and not self:IsManaged(child) then
			table.insert(candidates, child)
		end
	end
	table.sort(candidates, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return candidates[1], #candidates
end

-- Returns only IDs that have more than one managed instance.
function InstanceManager:FindDuplicates(): { [string]: { Instance } }
	local duplicates = {}
	for id, list in pairs(self:Snapshot().ByID) do
		if #list > 1 then
			duplicates[id] = list
		end
	end
	return duplicates
end

---------------------------------------------------------------------------
-- Original values
---------------------------------------------------------------------------

local function encodeOriginal(value: any): any
	if value == nil then
		return NIL_MARKER
	elseif typeof(value) == "EnumItem" then
		return ENUM_PREFIX .. tostring(value.EnumType) .. "." .. value.Name
	end
	return value
end

local function decodeOriginal(value: any): any
	if value == NIL_MARKER then
		return nil
	elseif typeof(value) == "string" and Util.startsWith(value, ENUM_PREFIX) then
		local enumName, itemName = string.match(string.sub(value, #ENUM_PREFIX + 1), "^([%w_]+)%.([%w_]+)$")
		if enumName then
			return Values.getEnumItem(enumName, itemName)
		end
		return nil
	end
	return value
end

function InstanceManager:HasOriginal(instance: Instance, property: string): boolean
	if getAttribute(instance, InstanceManager.ORIGINAL_PREFIX .. property) ~= nil then
		return true
	end
	local memory = self._memoryOriginals[instance]
	return memory ~= nil and memory[property] ~= nil
end

function InstanceManager:GetOriginal(instance: Instance, property: string): (boolean, any)
	local stored = getAttribute(instance, InstanceManager.ORIGINAL_PREFIX .. property)
	if stored ~= nil then
		return true, decodeOriginal(stored)
	end
	local memory = self._memoryOriginals[instance]
	if memory and memory[property] ~= nil then
		return true, memory[property].Value
	end
	return false, nil
end

-- Records the value a property had before VisualFX first touched it.
function InstanceManager:RecordOriginal(instance: Instance, property: string)
	if self:HasOriginal(instance, property) then
		return
	end
	local ok, value = pcall(function()
		return (instance :: any)[property]
	end)
	if not ok then
		return
	end
	if not self:_setAttribute(instance, InstanceManager.ORIGINAL_PREFIX .. property, encodeOriginal(value)) then
		self._memoryOriginals[instance] = self._memoryOriginals[instance] or {}
		self._memoryOriginals[instance][property] = { Value = value }
	end
end

function InstanceManager:ClearOriginal(instance: Instance, property: string)
	self:_setAttribute(instance, InstanceManager.ORIGINAL_PREFIX .. property, nil)
	local memory = self._memoryOriginals[instance]
	if memory then
		memory[property] = nil
	end
end

-- Properties with a recorded original value (i.e. currently managed by VisualFX).
function InstanceManager:GetManagedProperties(instance: Instance): { string }
	local properties = {}
	local ok, attributes = pcall(instance.GetAttributes, instance)
	if ok then
		for name in pairs(attributes) do
			if Util.startsWith(name, InstanceManager.ORIGINAL_PREFIX) then
				table.insert(properties, string.sub(name, #InstanceManager.ORIGINAL_PREFIX + 1))
			end
		end
	end
	local memory = self._memoryOriginals[instance]
	if memory then
		for property in pairs(memory) do
			Util.addUnique(properties, property)
		end
	end
	table.sort(properties)
	return properties
end

-- Restores a property to its recorded original value and forgets the record.
function InstanceManager:RestoreOriginal(instance: Instance, property: string): (boolean, string?)
	local has, value = self:GetOriginal(instance, property)
	if not has then
		return false, "no original value recorded"
	end
	local ok, problem = self:SetProperty(instance, property, value, { SkipOriginal = true })
	self:ClearOriginal(instance, property)
	return ok, problem
end

---------------------------------------------------------------------------
-- Mutation
---------------------------------------------------------------------------

--[[
	Writes a property through the compatibility layer.
	options.RecordOriginal: store the original value first (non-created instances).
	Returns ok, message.
]]
function InstanceManager:SetProperty(instance: Instance, property: string, value: any, options: { [string]: any }?): (boolean, string?)
	local opts = options or {}
	local okRead, before = pcall(function()
		return (instance :: any)[property]
	end)
	if opts.RecordOriginal and not opts.SkipOriginal then
		self:RecordOriginal(instance, property)
	end
	local ok, problem = self.Compatibility:SetProperty(instance, property, value)
	if ok and self._journal and not self._journal.CreatedSet[instance] then
		local _, after = pcall(function()
			return (instance :: any)[property]
		end)
		table.insert(self._journal.Entries, {
			Kind = "Property",
			Instance = instance,
			Property = property,
			Before = if okRead then before else nil,
			Written = after,
		})
	end
	return ok, problem
end

--[[
	Creates an instance, applies properties before parenting (cheaper for the
	engine), stamps the managed identity and parents it. Reuses pooled
	instances of the same class when available.
]]
function InstanceManager:Create(spec: { [string]: any }, parent: Instance): (Instance?, { string })
	local warnings = {}
	local instance = self:_takeFromPool(spec.ClassName)
	if not instance then
		local ok, result = pcall(Instance.new, spec.ClassName)
		if not ok then
			table.insert(warnings, string.format("%s: class %s is not available; effect skipped", spec.ID, spec.ClassName))
			return nil, warnings
		end
		instance = result
	end
	instance.Name = spec.Name or spec.Type or spec.ClassName
	if self._journal then
		self._journal.CreatedSet[instance] = true
		table.insert(self._journal.Entries, { Kind = "Created", Instance = instance })
	end
	self:Mark(instance, spec, false)
	for _, property in ipairs(Util.sortedKeys(spec.Properties or {})) do
		local ok, problem = self:SetProperty(instance, property, spec.Properties[property])
		if not ok and problem then
			table.insert(warnings, problem)
		end
	end
	instance.Parent = parent
	return instance, warnings
end

--[[
	Removes a managed instance. Adopted instances are restored and released
	instead of destroyed. Inside a journal, instances are only unparented so a
	revert can bring them back. Instances VisualFX does not manage are never
	touched.
]]
function InstanceManager:Remove(instance: Instance): (boolean, string?)
	if not self:IsManaged(instance) then
		return false, "refusing to remove unmanaged instance " .. instance:GetFullName()
	end
	local id = getAttribute(instance, InstanceManager.ATTR_ID)
	if self:IsAdopted(instance) then
		self:RestoreAll(instance)
		self:Unmark(instance)
		return true, nil
	end
	if id and self._index[id] == instance then
		self._index[id] = nil
	end
	if self._journal then
		if self._journal.CreatedSet[instance] then
			instance.Parent = nil
		else
			table.insert(self._journal.Entries, { Kind = "Removed", Instance = instance, Parent = instance.Parent })
			instance.Parent = nil
		end
		return true, nil
	end
	if not self:_returnToPool(instance) then
		instance:Destroy()
	end
	return true, nil
end

-- Restores every recorded original property on an instance.
function InstanceManager:RestoreAll(instance: Instance): { string }
	local restored = {}
	for _, property in ipairs(self:GetManagedProperties(instance)) do
		if self:RestoreOriginal(instance, property) then
			table.insert(restored, property)
		end
	end
	return restored
end

---------------------------------------------------------------------------
-- Pooling (reuse emitter hosts instead of churning instances)
---------------------------------------------------------------------------

local POOLABLE = { Part = true, ParticleEmitter = true, Attachment = true }

function InstanceManager:_returnToPool(instance: Instance): boolean
	if not POOLABLE[instance.ClassName] or #instance:GetChildren() > 0 then
		return false
	end
	local list = self._pool[instance.ClassName] or {}
	if #list >= self.PoolLimit then
		return false
	end
	self:Unmark(instance)
	instance.Parent = nil
	table.insert(list, instance)
	self._pool[instance.ClassName] = list
	return true
end

function InstanceManager:_takeFromPool(className: string): Instance?
	local list = self._pool[className]
	if list and #list > 0 then
		return table.remove(list)
	end
	return nil
end

function InstanceManager:GetPoolSize(): number
	local total = 0
	for _, list in pairs(self._pool) do
		total += #list
	end
	return total
end

function InstanceManager:ClearPool()
	for _, list in pairs(self._pool) do
		for _, instance in ipairs(list) do
			instance:Destroy()
		end
	end
	self._pool = {}
end

---------------------------------------------------------------------------
-- Journal (non-destructive preview)
---------------------------------------------------------------------------

function InstanceManager:BeginJournal(label: string?)
	if self._journal then
		return false
	end
	self._journal = { Label = label or "Preview", Entries = {}, CreatedSet = {} }
	return true
end

function InstanceManager:IsJournaling(): boolean
	return self._journal ~= nil
end

-- Keeps every change. Instances removed during the journal are destroyed now.
function InstanceManager:CommitJournal(): number
	local journal = self._journal
	if not journal then
		return 0
	end
	self._journal = nil
	local count = 0
	for _, entry in ipairs(journal.Entries) do
		count += 1
		if entry.Kind == "Removed" then
			entry.Instance:Destroy()
		elseif entry.Kind == "Created" and entry.Instance.Parent == nil then
			entry.Instance:Destroy()
		end
	end
	return count
end

--[[
	Undoes every recorded change in reverse order. A property is only restored
	when it still holds the value VisualFX wrote, so edits made by a developer
	during the preview are preserved. Returns { Restored, Skipped }.
]]
function InstanceManager:RevertJournal()
	local journal = self._journal
	local result = { Restored = 0, Skipped = {} }
	if not journal then
		return result
	end
	self._journal = nil
	for index = #journal.Entries, 1, -1 do
		local entry = journal.Entries[index]
		if entry.Kind == "Property" then
			local ok, current = pcall(function()
				return (entry.Instance :: any)[entry.Property]
			end)
			if ok and Values.equal(current, entry.Written) then
				if self.Compatibility:SetProperty(entry.Instance, entry.Property, entry.Before) then
					result.Restored += 1
				end
			else
				table.insert(
					result.Skipped,
					string.format("%s.%s was changed outside VisualFX; kept", entry.Instance:GetFullName(), entry.Property)
				)
			end
		elseif entry.Kind == "Attribute" then
			pcall(entry.Instance.SetAttribute, entry.Instance, entry.Name, entry.Before)
		elseif entry.Kind == "Created" then
			local id = getAttribute(entry.Instance, InstanceManager.ATTR_ID)
			if id and self._index[id] == entry.Instance then
				self._index[id] = nil
			end
			entry.Instance:Destroy()
			result.Restored += 1
		elseif entry.Kind == "Removed" then
			entry.Instance.Parent = entry.Parent
			result.Restored += 1
		end
	end
	self._index = {}
	return result
end

return InstanceManager
