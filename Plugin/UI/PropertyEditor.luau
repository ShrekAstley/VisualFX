--[[
	Builds editors from VisualFX field schemas, so every section editor in
	the plugin is generated from the same schema that drives validation,
	serialization and the AI schema. Editing a value sends a configuration
	overlay through the controller (live, journaled preview).

	Field kinds -> controls:
	  number/integer  slider + numeric field (range from Min/Max/SoftMax)
	  boolean         toggle
	  string          dropdown when Values are listed, text field otherwise
	  Color3          color picker
	  EnumItem        dropdown of the engine's enum items
	  Vector3/2       numeric fields
	  NumberRange     min/max fields
	  NumberSequence  start/end fields (two keypoints)
	  ColorSequence   start/end color pickers
	  object          nested collapsible section
]]

local Theme = require(script.Parent.Theme)

local PropertyEditor = {}
PropertyEditor.__index = PropertyEditor

local FALLBACK_MAX = { number = 10, integer = 100 }

local function wrap(path: { string }, key: string, value: any)
	local root = {}
	local node = root
	for _, part in ipairs(path) do
		node[part] = {}
		node = node[part]
	end
	node[key] = value
	return root
end

local function readPath(root: any, path: { string }): any
	local node = root
	for _, part in ipairs(path) do
		if typeof(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

--[[
	options:
	  Live      function() -> table of live values for this path (optional)
	  Title     section title (optional; no section when nil)
	  Collapsed start collapsed
	  Exclude   { [key] = true } fields to skip
]]
function PropertyEditor.new(ui, controller, path: { string }, fields: { any }, options: { [string]: any }?)
	local self = setmetatable({}, PropertyEditor)
	local opts = options or {}
	self.UI = ui
	self.Controller = controller
	self.Path = path
	self.Fields = fields
	self.Options = opts
	self.Controls = {}
	self.Children = {}
	self._lastPreview = 0

	if opts.Title then
		self.Section = ui:Section(opts.Title, { Collapsed = opts.Collapsed, LayoutOrder = opts.LayoutOrder })
		self.Frame = self.Section.Frame
		self.Content = self.Section.Content
	else
		self.Frame = ui:Stack(Theme.Spacing.Small, opts.LayoutOrder)
		self.Content = self.Frame
	end
	self:Build()
	return self
end

function PropertyEditor:_Authored(key: string): any
	local config = readPath(self.Controller.Engine:GetConfiguration(), self.Path)
	return if typeof(config) == "table" then config[key] else nil
end

function PropertyEditor:_Current(field): any
	local authored = self:_Authored(field.Key)
	if authored ~= nil then
		return authored, true
	end
	if self.Options.Live then
		local ok, live = pcall(self.Options.Live)
		if ok and typeof(live) == "table" and live[field.Key] ~= nil then
			return live[field.Key], false
		end
	end
	return field.Default, false
end

function PropertyEditor:_Commit(key: string, value: any, final: boolean)
	local now = os.clock()
	if not final and now - self._lastPreview < 0.08 then
		return
	end
	self._lastPreview = now
	self.Controller:Edit(wrap(self.Path, key, value))
end

local function rangeFor(field)
	local min = field.Min or 0
	local max = field.Max or field.SoftMax or FALLBACK_MAX[field.Kind] or 10
	if field.Min and field.Min < 0 and not field.Max then
		max = math.abs(field.Min)
	end
	return min, max
end

function PropertyEditor:_BuildControl(field, value)
	local ui = self.UI
	local kind = field.Kind
	local function commit(newValue, final)
		self:_Commit(field.Key, newValue, final ~= false)
	end

	if kind == "number" or kind == "integer" then
		local min, max = rangeFor(field)
		local current = if typeof(value) == "number" then value else min
		return ui:Slider(current, min, math.max(max, current), commit, { Integer = kind == "integer" })
	elseif kind == "boolean" then
		return ui:Toggle(value == true, function(newValue)
			commit(newValue, true)
		end)
	elseif kind == "string" and field.Values then
		return ui:Dropdown(field.Values, value, function(choice)
			commit(choice, true)
		end)
	elseif kind == "string" then
		return ui:TextInput(value or "", function(text)
			commit(text, true)
		end, { Placeholder = field.Description })
	elseif kind == "Color3" then
		return ui:ColorPicker(if typeof(value) == "Color3" then value else Color3.new(1, 1, 1), commit)
	elseif kind == "EnumItem" then
		local names = {}
		local ok, items = pcall(function()
			return (Enum :: any)[field.Enum]:GetEnumItems()
		end)
		if ok then
			for _, item in ipairs(items) do
				table.insert(names, item.Name)
			end
		end
		return ui:Dropdown(names, if typeof(value) == "EnumItem" then value.Name else nil, function(choice)
			commit(choice, true)
		end)
	elseif kind == "Vector3" or kind == "Vector2" or kind == "NumberRange" or kind == "NumberSequence" then
		return self:_BuildComposite(field, value, commit)
	elseif kind == "ColorSequence" then
		local first = Color3.new(1, 1, 1)
		local last = first
		if typeof(value) == "ColorSequence" then
			first = value.Keypoints[1].Value
			last = value.Keypoints[#value.Keypoints].Value
		end
		local container = ui:Stack(2)
		local startPicker, endPicker
		local function send(final)
			commit(ColorSequence.new(startPicker:Get(), endPicker:Get()), final)
		end
		startPicker = ui:ColorPicker(first, function(_, final)
			send(final)
		end, { LayoutOrder = 1 })
		endPicker = ui:ColorPicker(last, function(_, final)
			send(final)
		end, { LayoutOrder = 2 })
		startPicker.Instance.Parent = container
		endPicker.Instance.Parent = container
		return {
			Instance = container,
			Set = function(_, newValue)
				if typeof(newValue) == "ColorSequence" then
					startPicker:Set(newValue.Keypoints[1].Value)
					endPicker:Set(newValue.Keypoints[#newValue.Keypoints].Value)
				end
			end,
		}
	end
	return nil
end

-- Vector3 / Vector2 / NumberRange / NumberSequence as a row of numeric fields.
function PropertyEditor:_BuildComposite(field, value, commit)
	local ui = self.UI
	local kind = field.Kind
	local parts
	if kind == "Vector3" then
		parts = if typeof(value) == "Vector3" then { value.X, value.Y, value.Z } else { 0, 0, 0 }
	elseif kind == "Vector2" then
		parts = if typeof(value) == "Vector2" then { value.X, value.Y } else { 0, 0 }
	elseif kind == "NumberRange" then
		parts = if typeof(value) == "NumberRange" then { value.Min, value.Max } else { 0, 0 }
	else
		if typeof(value) == "NumberSequence" then
			parts = { value.Keypoints[1].Value, value.Keypoints[#value.Keypoints].Value }
		else
			parts = { 0, 0 }
		end
	end
	local container = ui:Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight - 2),
	}, { ui:HorizontalList(4) })
	local inputs = {}
	local function build()
		if kind == "Vector3" then
			return Vector3.new(parts[1], parts[2], parts[3])
		elseif kind == "Vector2" then
			return Vector2.new(parts[1], parts[2])
		elseif kind == "NumberRange" then
			return NumberRange.new(math.min(parts[1], parts[2]), math.max(parts[1], parts[2]))
		end
		return NumberSequence.new(parts[1], parts[2])
	end
	local width = 1 / #parts
	for index = 1, #parts do
		local input = ui:NumberInput(parts[index], function(number)
			parts[index] = number
			commit(build(), true)
		end, { Size = UDim2.new(width, -4, 1, 0), LayoutOrder = index })
		input.Instance.Parent = container
		inputs[index] = input
	end
	return {
		Instance = container,
		Set = function(_, newValue)
			local values
			if typeof(newValue) == "Vector3" then
				values = { newValue.X, newValue.Y, newValue.Z }
			elseif typeof(newValue) == "Vector2" then
				values = { newValue.X, newValue.Y }
			elseif typeof(newValue) == "NumberRange" then
				values = { newValue.Min, newValue.Max }
			elseif typeof(newValue) == "NumberSequence" then
				values = { newValue.Keypoints[1].Value, newValue.Keypoints[#newValue.Keypoints].Value }
			end
			if values then
				for index, number in ipairs(values) do
					parts[index] = number
					if inputs[index] then
						inputs[index]:Set(number)
					end
				end
			end
		end,
	}
end

function PropertyEditor:Build()
	local ui = self.UI
	local exclude = self.Options.Exclude or {}
	for index, field in ipairs(self.Fields) do
		if exclude[field.Key] or field.Kind == "map" or field.Kind == "array" or field.Kind == "any" then
			continue
		end
		if field.Kind == "object" then
			local childPath = table.clone(self.Path)
			table.insert(childPath, field.Key)
			local child = PropertyEditor.new(ui, self.Controller, childPath, field.Fields, {
				Title = field.Key,
				Collapsed = true,
				LayoutOrder = index,
			})
			child.Frame.Parent = self.Content
			table.insert(self.Children, child)
			continue
		end
		local value, authored = self:_Current(field)
		local control = self:_BuildControl(field, value)
		if control then
			local row, _, label = ui:Row(field.Key, control.Instance, {
				LayoutOrder = index,
				Unset = not authored,
				SearchExtra = (field.Description or "") .. " " .. (field.Property or ""),
			})
			if field.Description then
				label:SetAttribute("Tooltip", field.Description)
			end
			-- Reset button: removes the key so the original value is restored.
			local reset = ui:Button("↺", function()
				self.Controller:Edit(wrap(self.Path, field.Key, "$remove"))
			end, { Style = "Ghost", Size = UDim2.new(0, 22, 0, Theme.RowHeight - 2) })
			reset.Position = UDim2.new(1, -22, 0, 1)
			reset.Visible = authored
			reset.Parent = row
			control.Instance.Size = UDim2.new(1, -26, control.Instance.Size.Y.Scale, control.Instance.Size.Y.Offset)
			row.Parent = self.Content
			self.Controls[field.Key] = { Control = control, Field = field, Label = label, Reset = reset }
		end
	end
end

-- Updates controls from the current configuration without rebuilding.
function PropertyEditor:Refresh()
	for _, entry in pairs(self.Controls) do
		local value, authored = self:_Current(entry.Field)
		if value ~= nil and entry.Control.Set then
			local kind = entry.Field.Kind
			if kind == "EnumItem" then
				entry.Control:Set(if typeof(value) == "EnumItem" then value.Name else value)
			else
				pcall(entry.Control.Set, entry.Control, value)
			end
		end
		entry.Label.TextColor3 = if authored then self.UI.Palette.Text else self.UI.Palette.SubText
		entry.Reset.Visible = authored
	end
	for _, child in ipairs(self.Children) do
		child:Refresh()
	end
end

return PropertyEditor
