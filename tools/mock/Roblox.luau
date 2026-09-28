--[[
	Minimal but strict Roblox engine mock for running VisualFX tests with the
	standalone Luau CLI (https://github.com/luau-lang/luau).

	Fidelity goals (the things VisualFX depends on):
	  * typeof() returns Roblox type names for datatypes and instances
	  * reading or writing a property a class does not have raises an error
	  * number properties are stored as float32, ClockTime with 1s precision
	  * Parent is locked after Destroy()
	  * attributes validate names and value types
	  * CollectionService tags, GetTagged only returns instances in the DataModel
	  * children are reachable as instance.ChildName (used by require paths)

	It is not a renderer: nothing is drawn, particles are not simulated.
]]

local Mock = {}

---------------------------------------------------------------------------
-- typeof
---------------------------------------------------------------------------

local function mockTypeof(value)
	if type(value) == "table" then
		local mt = getmetatable(value)
		if type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
	end
	return type(value)
end
Mock.typeof = mockTypeof

local function f32(x)
	return (string.unpack("f", string.pack("f", x)))
end

local function immutable(name)
	return function(_, key)
		error(string.format("%s cannot be assigned to (%s is read-only)", tostring(key), name), 2)
	end
end

---------------------------------------------------------------------------
-- Datatypes
---------------------------------------------------------------------------

local Color3 = {}
local Color3Methods = {}
local Color3Meta = { __type = "Color3", __index = Color3Methods, __newindex = immutable("Color3") }
Color3Meta.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
Color3Meta.__tostring = function(c)
	return string.format("%g, %g, %g", c.R, c.G, c.B)
end
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then
		return Color3.new(v, t, p)
	elseif m == 1 then
		return Color3.new(q, v, p)
	elseif m == 2 then
		return Color3.new(p, v, t)
	elseif m == 3 then
		return Color3.new(p, q, v)
	elseif m == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
end
function Color3Methods.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function Color3Methods.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, max
	local d = max - min
	s = if max == 0 then 0 else d / max
	if d ~= 0 then
		if max == r then
			h = (g - b) / d % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, s, v
end
function Color3Methods.ToHex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local Vector3 = {}
local Vector3Methods = {}
local Vector3Meta = { __type = "Vector3", __newindex = immutable("Vector3") }
local function v3(x, y, z)
	local magnitude = math.sqrt(x * x + y * y + z * z)
	return setmetatable({ X = x, Y = y, Z = z, Magnitude = magnitude }, Vector3Meta)
end
Vector3Meta.__index = function(self, key)
	if key == "Unit" then
		local m = rawget(self, "Magnitude")
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	local method = Vector3Methods[key]
	if method then
		return method
	end
	error(tostring(key) .. " is not a valid member of Vector3", 2)
end
Vector3Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3Meta.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Meta.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Meta.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Meta.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3Meta.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
Vector3Meta.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end
function Vector3.new(x, y, z)
	return v3(x or 0, y or 0, z or 0)
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
function Vector3Methods.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function Vector3Methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3Methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3Methods.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end

local Vector2 = {}
local Vector2Methods = {}
local Vector2Meta = { __type = "Vector2", __newindex = immutable("Vector2") }
local function v2(x, y)
	return setmetatable({ X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }, Vector2Meta)
end
Vector2Meta.__index = function(self, key)
	if key == "Unit" then
		local m = rawget(self, "Magnitude")
		return v2(self.X / m, self.Y / m)
	end
	local method = Vector2Methods[key]
	if method then
		return method
	end
	error(tostring(key) .. " is not a valid member of Vector2", 2)
end
Vector2Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2Meta.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
Vector2Meta.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
Vector2Meta.__mul = function(a, b)
	if type(a) == "number" then
		return v2(b.X * a, b.Y * a)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
Vector2Meta.__tostring = function(v)
	return string.format("%g, %g", v.X, v.Y)
end
function Vector2.new(x, y)
	return v2(x or 0, y or 0)
end
Vector2.zero = v2(0, 0)
function Vector2Methods.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end

local NumberRange = {}
local NumberRangeMeta = { __type = "NumberRange", __newindex = immutable("NumberRange") }
NumberRangeMeta.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
NumberRangeMeta.__tostring = function(r)
	return string.format("%g %g", r.Min, r.Max)
end
function NumberRange.new(min, max)
	max = max or min
	if min > max then
		error("NumberRange: invalid range", 2)
	end
	return setmetatable({ Min = min, Max = max }, NumberRangeMeta)
end

local NumberSequenceKeypoint = {}
local NSKMeta = { __type = "NumberSequenceKeypoint", __newindex = immutable("NumberSequenceKeypoint") }
NSKMeta.__eq = function(a, b)
	return a.Time == b.Time and a.Value == b.Value and a.Envelope == b.Envelope
end
function NumberSequenceKeypoint.new(time, value, envelope)
	return setmetatable({ Time = time, Value = value, Envelope = envelope or 0 }, NSKMeta)
end

local function validateKeypoints(keypoints, label)
	if #keypoints < 2 then
		error(label .. ": requires at least 2 keypoints", 3)
	end
	if #keypoints > 20 then
		error(label .. ": maximum of 20 keypoints", 3)
	end
	if keypoints[1].Time ~= 0 then
		error(label .. ": must start at time=0", 3)
	end
	if keypoints[#keypoints].Time ~= 1 then
		error(label .. ": must end at time=1", 3)
	end
	for i = 2, #keypoints do
		if keypoints[i].Time < keypoints[i - 1].Time then
			error(label .. ": keypoints must be ordered by time", 3)
		end
	end
end

local NumberSequence = {}
local NSMeta = { __type = "NumberSequence", __newindex = immutable("NumberSequence") }
NSMeta.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i = 1, #a.Keypoints do
		if a.Keypoints[i] ~= b.Keypoints[i] then
			return false
		end
	end
	return true
end
function NumberSequence.new(a, b)
	local keypoints
	if type(a) == "number" then
		keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
	elseif type(a) == "table" and mockTypeof(a) == "table" then
		keypoints = table.clone(a)
		validateKeypoints(keypoints, "NumberSequence")
	else
		error("NumberSequence.new: invalid argument", 2)
	end
	return setmetatable({ Keypoints = keypoints }, NSMeta)
end

local ColorSequenceKeypoint = {}
local CSKMeta = { __type = "ColorSequenceKeypoint", __newindex = immutable("ColorSequenceKeypoint") }
CSKMeta.__eq = function(a, b)
	return a.Time == b.Time and a.Value == b.Value
end
function ColorSequenceKeypoint.new(time, color)
	return setmetatable({ Time = time, Value = color }, CSKMeta)
end

local ColorSequence = {}
local CSMeta = { __type = "ColorSequence", __newindex = immutable("ColorSequence") }
CSMeta.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i = 1, #a.Keypoints do
		if a.Keypoints[i] ~= b.Keypoints[i] then
			return false
		end
	end
	return true
end
function ColorSequence.new(a, b)
	local keypoints
	if mockTypeof(a) == "Color3" then
		keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	elseif mockTypeof(a) == "table" then
		keypoints = table.clone(a)
		validateKeypoints(keypoints, "ColorSequence")
	else
		error("ColorSequence.new: invalid argument", 2)
	end
	return setmetatable({ Keypoints = keypoints }, CSMeta)
end

local CFrame = {}
local CFrameMeta = { __type = "CFrame", __newindex = immutable("CFrame") }
function CFrame.new(x, y, z)
	local position
	if mockTypeof(x) == "Vector3" then
		position = x
	else
		position = Vector3.new(x or 0, y or 0, z or 0)
	end
	return setmetatable({ Position = position, X = position.X, Y = position.Y, Z = position.Z }, CFrameMeta)
end

local Region3 = {}
local Region3Methods = {}
local Region3Meta = { __type = "Region3", __index = Region3Methods }
function Region3.new(min, max)
	return setmetatable({ Min = min, Max = max, Size = max - min, CFrame = CFrame.new((min + max) / 2) }, Region3Meta)
end
function Region3Methods.ExpandToGrid(self, _resolution)
	return self
end

local UDim = {}
local UDimMeta = { __type = "UDim" }
function UDim.new(scale, offset)
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDimMeta)
end
local UDim2 = {}
local UDim2Meta = { __type = "UDim2" }
UDim2Meta.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
function UDim2.new(xs, xo, ys, yo)
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo), Width = UDim.new(xs, xo), Height = UDim.new(ys, yo) }, UDim2Meta)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end

local Random = {}
local RandomMethods = {}
local RandomMeta = { __type = "Random", __index = RandomMethods }
function Random.new(seed)
	return setmetatable({ _state = (math.floor(seed or 0) % 2147483647) + 1 }, RandomMeta)
end
function RandomMethods.NextNumber(self, min, max)
	self._state = (self._state * 48271) % 2147483647
	local unit = self._state / 2147483647
	if min then
		return min + (max - min) * unit
	end
	return unit
end
function RandomMethods.NextInteger(self, min, max)
	return math.floor(self:NextNumber(min, max + 1))
end

local DockWidgetPluginGuiInfo = {}
function DockWidgetPluginGuiInfo.new(...)
	return setmetatable({ Args = { ... } }, { __type = "DockWidgetPluginGuiInfo" })
end

local TweenInfo = {}
function TweenInfo.new(time, style, direction)
	return setmetatable({ Time = time, EasingStyle = style, EasingDirection = direction }, { __type = "TweenInfo" })
end

local Font = {}
function Font.new(family, weight, style)
	return setmetatable({ Family = family, Weight = weight, Style = style }, { __type = "Font" })
end
function Font.fromEnum(item)
	return Font.new("rbxasset://fonts/families/" .. tostring(item.Name) .. ".json")
end

---------------------------------------------------------------------------
-- Enums
---------------------------------------------------------------------------

local EnumItemMeta = { __type = "EnumItem" }
EnumItemMeta.__tostring = function(item)
	return "Enum." .. tostring(item.EnumType) .. "." .. item.Name
end
EnumItemMeta.__newindex = immutable("EnumItem")

local EnumMeta = { __type = "Enum" }
EnumMeta.__tostring = function(enum)
	return rawget(enum, "_name")
end
EnumMeta.__index = function(enum, key)
	if key == "GetEnumItems" then
		return function(self)
			local list = {}
			for _, item in ipairs(rawget(self, "_items")) do
				table.insert(list, item)
			end
			return list
		end
	end
	local item = rawget(enum, "_byName")[key]
	if item then
		return item
	end
	error(tostring(key) .. " is not a valid member of \"Enum." .. rawget(enum, "_name") .. "\"", 2)
end

local EnumsMeta = { __type = "Enums" }
local Enum = setmetatable({}, EnumsMeta)
local enumStore = {}
EnumsMeta.__index = function(_, key)
	local enum = enumStore[key]
	if enum then
		return enum
	end
	error(tostring(key) .. " is not a valid member of \"Enums\"", 2)
end

function Mock.defineEnum(name, items)
	local enum = setmetatable({ _name = name, _items = {}, _byName = {} }, EnumMeta)
	for index, itemName in ipairs(items) do
		local item = setmetatable({ Name = itemName, Value = index - 1, EnumType = enum }, EnumItemMeta)
		table.insert(rawget(enum, "_items"), item)
		rawget(enum, "_byName")[itemName] = item
	end
	enumStore[name] = enum
	return enum
end

function Mock.removeEnum(name)
	enumStore[name] = nil
end

Mock.defineEnum("NormalId", { "Right", "Top", "Back", "Left", "Bottom", "Front" })
Mock.defineEnum("ParticleEmitterShape", { "Box", "Sphere", "Cylinder", "Disc" })
Mock.defineEnum("ParticleEmitterShapeStyle", { "Volume", "Surface" })
Mock.defineEnum("ParticleEmitterShapeInOut", { "Outward", "Inward", "InAndOut" })
Mock.defineEnum("ParticleOrientation", { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" })
Mock.defineEnum("Technology", { "Legacy", "Voxel", "Compatibility", "ShadowMap", "Future", "Unified" })
Mock.defineEnum("Material", { "Plastic", "Wood", "Slate", "Concrete", "Grass", "Sand", "Water", "Air", "Rock", "Snow", "Ice" })
Mock.defineEnum("EasingStyle", { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" })
Mock.defineEnum("EasingDirection", { "In", "Out", "InOut" })
Mock.defineEnum("Font", { "Legacy", "Arial", "SourceSans", "SourceSansBold", "SourceSansSemibold", "Gotham", "GothamMedium", "GothamBold", "BuilderSans", "RobotoMono", "Code" })
Mock.defineEnum("FontWeight", { "Regular", "Medium", "SemiBold", "Bold" })
Mock.defineEnum("TextXAlignment", { "Left", "Center", "Right" })
Mock.defineEnum("TextYAlignment", { "Top", "Center", "Bottom" })
Mock.defineEnum("FillDirection", { "Horizontal", "Vertical" })
Mock.defineEnum("SortOrder", { "Name", "Custom", "LayoutOrder" })
Mock.defineEnum("HorizontalAlignment", { "Center", "Left", "Right" })
Mock.defineEnum("VerticalAlignment", { "Center", "Top", "Bottom" })
Mock.defineEnum("AutomaticSize", { "None", "X", "Y", "XY" })
Mock.defineEnum("ScrollingDirection", { "X", "Y", "XY" })
Mock.defineEnum("InitialDockState", { "Top", "Bottom", "Left", "Right", "Float" })
Mock.defineEnum("StudioStyleGuideColor", {
	"MainBackground", "Titlebar", "Dropdown", "Tooltip", "Notification", "ScrollBar", "ScrollBarBackground", "TabBar", "Tab",
	"RibbonTab", "RibbonTabTopBar", "Button", "MainButton", "RibbonButton", "ViewPortBackground", "InputFieldBackground",
	"Item", "TableItem", "CategoryItem", "GameSettingsTableItem", "GameSettingsTooltip", "EmulatorBar", "EmulatorDropDown",
	"ColorPickerFrame", "CurrentMarker", "Border", "Shadow", "Light", "Dark", "Mid", "MainText", "SubText", "TitlebarText",
	"BrightText", "DimmedText", "LinkText", "WarningText", "ErrorText", "InfoText", "SensitiveText", "ScriptBackground",
	"ScriptText", "SelectedText", "InputFieldBorder", "CheckedFieldBackground", "CheckedFieldBorder", "CheckedFieldIndicator",
	"HeaderSection", "Midlight", "StatusBar", "DialogButton", "DialogButtonText", "DialogButtonBorder", "DialogMainButton",
	"DialogMainButtonText", "InfoBarWarningBackground", "InfoBarWarningText", "ScriptEditorScrollBar", "DiffTextAddition",
	"DiffTextDeletion", "DiffTextAdditionBackground", "DiffTextDeletionBackground", "FilterButtonDefault", "FilterButtonHover",
	"FilterButtonChecked", "FilterButtonAccent", "FilterButtonBorder", "FilterButtonBorderAlt", "SubText2", "ButtonText",
})
Mock.defineEnum("StudioStyleGuideModifier", { "Default", "Selected", "Pressed", "Disabled", "Hover" })
Mock.defineEnum("UserInputType", { "MouseButton1", "MouseButton2", "MouseMovement", "Touch", "Keyboard" })
Mock.defineEnum("UserInputState", { "Begin", "Change", "End", "Cancel" })
Mock.defineEnum("KeyCode", { "Unknown", "Return", "Escape", "Tab" })
Mock.defineEnum("ZIndexBehavior", { "Global", "Sibling" })
Mock.defineEnum("ApplyStrokeMode", { "Contextual", "Border" })
Mock.defineEnum("TextTruncate", { "None", "AtEnd" })
Mock.defineEnum("FinishRecordingOperation", { "Cancel", "Commit", "Append" })

Mock.Enum = Enum

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------

local ConnectionMeta = { __type = "RBXScriptConnection" }
ConnectionMeta.__index = ConnectionMeta
function ConnectionMeta:Disconnect()
	self.Connected = false
	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

local SignalMeta = { __type = "RBXScriptSignal" }
SignalMeta.__index = SignalMeta
local function newSignal()
	return setmetatable({ _connections = {} }, SignalMeta)
end
function SignalMeta:Connect(fn)
	local connection = setmetatable({ Connected = true, _signal = self, _fn = fn }, ConnectionMeta)
	table.insert(self._connections, connection)
	return connection
end
function SignalMeta:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end
function SignalMeta:Fire(...)
	for _, connection in ipairs(table.clone(self._connections)) do
		if connection.Connected then
			connection._fn(...)
		end
	end
end
function SignalMeta:Wait()
	return nil
end
Mock.newSignal = newSignal

---------------------------------------------------------------------------
-- Classes
---------------------------------------------------------------------------

local rgb = Color3.fromRGB
local E = function(enumName, itemName)
	return enumStore[enumName][itemName]
end

--[[
	Props: default values (type of the default is the property type).
	Strict classes reject unknown properties; permissive (GUI) classes accept anything.
]]
local Classes = {}
Mock.Classes = Classes

local function class(name, super, props, extra)
	local definition = extra or {}
	definition.Name = name
	definition.Super = super
	definition.Props = props or {}
	Classes[name] = definition
	return definition
end

class("Instance", nil, { Archivable = true })
class("DataModel", "Instance", {}, { Service = true })
class("Folder", "Instance", {})
class("Configuration", "Instance", {})
class("Model", "Instance", {})
class("LuaSourceContainer", "Instance", {}, { Abstract = true })
class("BaseScript", "LuaSourceContainer", { Disabled = false, Enabled = true }, { Abstract = true })
class("Script", "BaseScript", { Source = "" })
class("LocalScript", "Script", { Source = "" })
class("ModuleScript", "LuaSourceContainer", { Source = "" })
class("StringValue", "Instance", { Value = "" })

class("Lighting", "Instance", {
	ClockTime = 14,
	TimeOfDay = "14:00:00",
	Brightness = 2,
	ExposureCompensation = 0,
	Ambient = rgb(0, 0, 0),
	OutdoorAmbient = rgb(128, 128, 128),
	ColorShift_Top = rgb(0, 0, 0),
	ColorShift_Bottom = rgb(0, 0, 0),
	GlobalShadows = true,
	ShadowSoftness = 0.2,
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	GeographicLatitude = 41.733,
	FogColor = rgb(192, 192, 192),
	FogStart = 0,
	FogEnd = 100000,
	Technology = E("Technology", "ShadowMap"),
}, {
	Service = true,
	Setters = {
		Technology = function()
			error("The current thread cannot write 'Technology' (lacking capability Plugin)", 0)
		end,
		ClockTime = function(state, value)
			local seconds = math.floor(((value % 24) * 3600) + 0.5)
			state.props.ClockTime = seconds / 3600
			state.props.TimeOfDay = string.format("%02d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
			return true
		end,
	},
})
class("Atmosphere", "Instance", { Density = 0.395, Offset = 0, Color = rgb(199, 199, 199), Decay = rgb(106, 112, 125), Glare = 0, Haze = 0 })
class("Sky", "Instance", {
	SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex", SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex",
	SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex", SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex",
	SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex", SkyboxUp = "rbxasset://textures/sky/sky512_up.tex",
	SunTextureId = "rbxasset://sky/sun.jpg", MoonTextureId = "rbxasset://sky/moon.jpg",
	SunAngularSize = 21, MoonAngularSize = 11, StarCount = 3000, CelestialBodiesShown = true,
	SkyboxOrientation = Vector3.new(0, 0, 0),
})
class("Clouds", "Instance", { Enabled = true, Cover = 0.5, Density = 0.7, Color = rgb(255, 255, 255) })
class("PostEffect", "Instance", { Enabled = true }, { Abstract = true })
class("BloomEffect", "PostEffect", { Intensity = 1, Size = 24, Threshold = 2 })
class("ColorCorrectionEffect", "PostEffect", { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = rgb(255, 255, 255) })
class("DepthOfFieldEffect", "PostEffect", { FarIntensity = 0.75, FocusDistance = 0.05, InFocusRadius = 10, NearIntensity = 0.75 })
class("SunRaysEffect", "PostEffect", { Intensity = 0.25, Spread = 1 })
class("BlurEffect", "PostEffect", { Size = 24 })

class("Workspace", "Model", { GlobalWind = Vector3.new(0, 0, 0), Gravity = 196.2 }, { Service = true, Refs = { CurrentCamera = true, Terrain = true } })
class("BasePart", "Instance", {
	Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true, Locked = false,
	Transparency = 0, Size = Vector3.new(4, 1, 2), Position = Vector3.new(0, 0, 0), Color = rgb(163, 162, 165),
}, { Abstract = true, Refs = { CFrame = true } })
class("Part", "BasePart", {})
class("Terrain", "BasePart", {
	WaterColor = rgb(12, 84, 92), WaterTransparency = 0.3, WaterReflectance = 1, WaterWaveSize = 0.15, WaterWaveSpeed = 10,
}, { NotCreatable = true })
class("Camera", "Instance", { FieldOfView = 70 }, { Refs = { CFrame = true } })
class("ParticleEmitter", "Instance", {
	Enabled = true, Rate = 20, Lifetime = NumberRange.new(5, 10), Speed = NumberRange.new(5), Size = NumberSequence.new(1),
	Color = ColorSequence.new(rgb(255, 255, 255)), Transparency = NumberSequence.new(0), Rotation = NumberRange.new(0),
	RotSpeed = NumberRange.new(0), Drag = 0, Acceleration = Vector3.new(0, 0, 0), SpreadAngle = Vector2.new(0, 0),
	Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 0, LightInfluence = 0, Brightness = 1,
	Shape = E("ParticleEmitterShape", "Box"), ShapeStyle = E("ParticleEmitterShapeStyle", "Volume"),
	ShapeInOut = E("ParticleEmitterShapeInOut", "Outward"), ShapePartial = 1,
	Orientation = E("ParticleOrientation", "FacingCamera"), EmissionDirection = E("NormalId", "Top"),
	ZOffset = 0, LockedToPart = false, VelocityInheritance = 0, WindAffectsDrag = false,
	Squash = NumberSequence.new(0), TimeScale = 1,
})
class("Attachment", "Instance", { Position = Vector3.new(0, 0, 0) })
class("PointLight", "Instance", { Brightness = 1, Range = 8, Color = rgb(255, 255, 255), Enabled = true })

-- Services
class("RunService", "Instance", {}, { Service = true })
class("CollectionService", "Instance", {}, { Service = true })
class("HttpService", "Instance", {}, { Service = true })
class("ReplicatedStorage", "Instance", {}, { Service = true })
class("ServerStorage", "Instance", {}, { Service = true })
class("ServerScriptService", "Instance", {}, { Service = true })
class("StarterPlayer", "Instance", {}, { Service = true })
class("StarterPlayerScripts", "Instance", {})
class("ChangeHistoryService", "Instance", {}, { Service = true })
class("Selection", "Instance", {}, { Service = true })
class("TweenService", "Instance", {}, { Service = true })
class("ScriptEditorService", "Instance", {}, { Service = true })
class("StudioService", "Instance", {}, { Service = true })
class("Players", "Instance", {}, { Service = true })
class("TextService", "Instance", {}, { Service = true })

-- Permissive GUI / plugin classes: any property can be set; common
-- properties have defaults so layout code can read them.
class("GuiBase2d", "Instance", {
	AbsoluteSize = Vector2.new(320, 24),
	AbsolutePosition = Vector2.new(0, 0),
}, { Abstract = true, Permissive = true })
class("GuiObject", "GuiBase2d", {
	Visible = true,
	Size = UDim2.new(0, 0, 0, 0),
	Position = UDim2.new(0, 0, 0, 0),
	LayoutOrder = 0,
}, { Abstract = true, Permissive = true })
class("GuiButton", "GuiObject", {}, { Abstract = true, Permissive = true })
for _, name in ipairs({ "Frame", "TextLabel", "ScrollingFrame", "ImageLabel", "CanvasGroup", "ViewportFrame" }) do
	class(name, "GuiObject", {}, { Permissive = true })
end
for _, name in ipairs({ "TextButton", "ImageButton" }) do
	class(name, "GuiButton", { Text = "" }, { Permissive = true })
end
class("TextBox", "GuiObject", { Text = "" }, {
	Permissive = true,
	Methods = {
		IsFocused = function()
			return false
		end,
		CaptureFocus = function() end,
		ReleaseFocus = function() end,
	},
})
class("LayerCollector", "GuiBase2d", { Enabled = true }, { Abstract = true, Permissive = true })
class("ScreenGui", "LayerCollector", {}, { Permissive = true })
class("PluginGui", "LayerCollector", { Title = "" }, { Abstract = true, Permissive = true })
class("DockWidgetPluginGui", "PluginGui", {}, {
	Permissive = true,
	Methods = {
		GetRelativeMousePosition = function()
			return Vector2.new(0, 0)
		end,
		BindToClose = function() end,
	},
})
for _, name in ipairs({
	"UIListLayout", "UIGridLayout", "UIPadding", "UICorner", "UIStroke", "UIGradient", "UISizeConstraint",
	"UITextSizeConstraint", "UIFlexItem", "UIAspectRatioConstraint", "PluginToolbar", "PluginToolbarButton",
	"PluginAction", "PluginMenu", "Plugin",
}) do
	class(name, "Instance", {}, { Permissive = true })
end

local function classChain(name)
	local chain = {}
	local current = Classes[name]
	while current do
		table.insert(chain, current)
		current = current.Super and Classes[current.Super]
	end
	return chain
end

local function findPropDefault(className, property)
	for _, definition in ipairs(classChain(className)) do
		if definition.Props[property] ~= nil then
			return true, definition.Props[property]
		end
	end
	return false, nil
end

local function findSetter(className, property)
	for _, definition in ipairs(classChain(className)) do
		if definition.Setters and definition.Setters[property] then
			return definition.Setters[property]
		end
	end
	return nil
end

local function hasRef(className, property)
	for _, definition in ipairs(classChain(className)) do
		if definition.Refs and definition.Refs[property] then
			return true
		end
	end
	return false
end

local function isPermissive(className)
	for _, definition in ipairs(classChain(className)) do
		if definition.Permissive then
			return true
		end
	end
	return false
end

-- Test hooks: simulate engine differences.
function Mock.removeProperty(className, property)
	local definition = Classes[className]
	definition.Removed = definition.Removed or {}
	definition.Removed[property] = true
end

function Mock.restoreProperty(className, property)
	local definition = Classes[className]
	if definition.Removed then
		definition.Removed[property] = nil
	end
end

local function isRemoved(className, property)
	for _, definition in ipairs(classChain(className)) do
		if definition.Removed and definition.Removed[property] then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------

local states = setmetatable({}, { __mode = "k" })
local allInstances = setmetatable({}, { __mode = "k" })
Mock.States = states

local InstanceMeta = { __type = "Instance" }
local Methods = {}

local EVENT_NAMES = {
	Changed = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
	AncestryChanged = true, Destroying = true, AttributeChanged = true,
	MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseEnter = true, MouseLeave = true,
	MouseMoved = true, InputBegan = true, InputChanged = true, InputEnded = true, FocusLost = true, Focused = true,
	Activated = true, Click = true, Triggered = true, Enabling = true, Closing = true, BindToClose = true,
	Heartbeat = true, RenderStepped = true, Stepped = true, PostSimulation = true, PreRender = true,
	ThemeChanged = true, Unloading = true, Deactivation = true, SelectionChanged = true,
}

local function newInstance(className, isService)
	local definition = Classes[className]
	if not definition then
		error(string.format("Unable to create an Instance of type \"%s\"", tostring(className)), 3)
	end
	local instance = setmetatable({}, InstanceMeta)
	states[instance] = {
		className = className,
		name = className,
		parent = nil,
		children = {},
		props = {},
		attributes = {},
		tags = {},
		signals = {},
		destroyed = false,
		parentLocked = false,
		service = isService,
	}
	allInstances[instance] = true
	return instance
end

local function state(instance)
	return states[instance]
end

local function getSignal(instance, name)
	local s = state(instance)
	if not s.signals[name] then
		s.signals[name] = newSignal()
	end
	return s.signals[name]
end

InstanceMeta.__tostring = function(instance)
	return state(instance).name
end

InstanceMeta.__index = function(instance, key)
	local s = state(instance)
	if key == "Name" then
		return s.name
	elseif key == "Parent" then
		return s.parent
	elseif key == "ClassName" then
		return s.className
	end
	for _, definition in ipairs(classChain(s.className)) do
		if definition.Methods and definition.Methods[key] then
			return definition.Methods[key]
		end
	end
	local method = Methods[key]
	if method then
		return method
	end
	if isRemoved(s.className, key) then
		error(string.format("%s is not a valid member of %s \"%s\"", tostring(key), s.className, s.name), 2)
	end
	if s.props[key] ~= nil then
		return s.props[key]
	end
	do
		local found, default = findPropDefault(s.className, key)
		if found then
			return default
		end
	end
	if hasRef(s.className, key) then
		return s.refs and s.refs[key]
	end
	if EVENT_NAMES[key] then
		return getSignal(instance, key)
	end
	for _, child in ipairs(s.children) do
		if state(child).name == key then
			return child
		end
	end
	if isPermissive(s.className) then
		return nil
	end
	error(string.format("%s is not a valid member of %s \"%s\"", tostring(key), s.className, s.name), 2)
end

local function isDescendantOf(instance, ancestor)
	local node = state(instance).parent
	while node do
		if node == ancestor then
			return true
		end
		node = state(node).parent
	end
	return false
end

local function setParent(instance, parent)
	local s = state(instance)
	if s.parentLocked then
		error(string.format("The Parent property of %s is locked, current parent: NULL, new parent %s", s.name, if parent then state(parent).name else "NULL"), 3)
	end
	if parent ~= nil and mockTypeof(parent) ~= "Instance" then
		error("Parent must be an Instance", 3)
	end
	if parent == instance or (parent and isDescendantOf(parent, instance)) then
		error("Attempt to set parent of " .. s.name .. " to itself or a descendant", 3)
	end
	if s.parent == parent then
		return
	end
	if s.parent then
		local siblings = state(s.parent).children
		local index = table.find(siblings, instance)
		if index then
			table.remove(siblings, index)
		end
	end
	s.parent = parent
	if parent then
		table.insert(state(parent).children, instance)
	end
end

local ATTRIBUTE_TYPES = {
	string = true, boolean = true, number = true, Color3 = true, Vector3 = true, Vector2 = true,
	NumberRange = true, NumberSequence = true, ColorSequence = true, UDim = true, UDim2 = true, CFrame = true,
}

InstanceMeta.__newindex = function(instance, key, value)
	local s = state(instance)
	if key == "Parent" then
		setParent(instance, value)
		return
	elseif key == "Name" then
		if type(value) ~= "string" then
			error("Name must be a string", 2)
		end
		s.name = value
		return
	elseif key == "ClassName" then
		error("ClassName is read-only", 2)
	end
	local setter = findSetter(s.className, key)
	if setter then
		if setter(s, value) then
			getSignal(instance, "Changed"):Fire(key)
			return
		end
	end
	if hasRef(s.className, key) then
		s.refs = s.refs or {}
		s.refs[key] = value
		if key == "CFrame" and value and s.props.Position ~= nil or (key == "CFrame" and findPropDefault(s.className, "Position")) then
			s.props.Position = value.Position
		end
		return
	end
	local found, default = findPropDefault(s.className, key)
	if found and not isRemoved(s.className, key) then
		local expected = mockTypeof(default)
		local actual = mockTypeof(value)
		if expected ~= actual then
			error(string.format("Unable to assign property %s. %s expected, got %s", key, expected, actual), 2)
		end
		if expected == "EnumItem" and value.EnumType ~= default.EnumType then
			error(string.format("Unable to assign property %s. Enum.%s expected", key, tostring(default.EnumType)), 2)
		end
		if expected == "number" then
			value = f32(value)
		end
		if key == "Position" and s.refs then
			s.refs.CFrame = CFrame.new(value)
		end
		s.props[key] = value
		getSignal(instance, "Changed"):Fire(key)
		if s.signals["Changed:" .. key] then
			s.signals["Changed:" .. key]:Fire()
		end
		return
	end
	if isPermissive(s.className) then
		s.props[key] = value
		if s.signals["Changed:" .. key] then
			s.signals["Changed:" .. key]:Fire()
		end
		return
	end
	error(string.format("%s is not a valid member of %s \"%s\"", tostring(key), s.className, s.name), 2)
end

function Methods.GetChildren(instance)
	return table.clone(state(instance).children)
end

function Methods.GetDescendants(instance)
	local result = {}
	local function visit(node)
		for _, child in ipairs(state(node).children) do
			table.insert(result, child)
			visit(child)
		end
	end
	visit(instance)
	return result
end

function Methods.FindFirstChild(instance, name, recursive)
	for _, child in ipairs(state(instance).children) do
		if state(child).name == name then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(state(instance).children) do
			local found = Methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Methods.WaitForChild(instance, name)
	return Methods.FindFirstChild(instance, name)
end

function Methods.IsA(instance, className)
	for _, definition in ipairs(classChain(state(instance).className)) do
		if definition.Name == className then
			return true
		end
	end
	return false
end

function Methods.FindFirstChildOfClass(instance, className)
	for _, child in ipairs(state(instance).children) do
		if state(child).className == className then
			return child
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(instance, className)
	for _, child in ipairs(state(instance).children) do
		if Methods.IsA(child, className) then
			return child
		end
	end
	return nil
end

function Methods.FindFirstAncestorOfClass(instance, className)
	local node = state(instance).parent
	while node do
		if state(node).className == className then
			return node
		end
		node = state(node).parent
	end
	return nil
end

function Methods.IsDescendantOf(instance, ancestor)
	return isDescendantOf(instance, ancestor)
end

function Methods.IsAncestorOf(instance, descendant)
	return isDescendantOf(descendant, instance)
end

function Methods.GetFullName(instance)
	local parts = {}
	local node = instance
	while node do
		local s = state(node)
		if s.className == "DataModel" then
			break
		end
		table.insert(parts, 1, s.name)
		node = s.parent
	end
	return table.concat(parts, ".")
end

function Methods.ClearAllChildren(instance)
	for _, child in ipairs(table.clone(state(instance).children)) do
		Methods.Destroy(child)
	end
end

function Methods.Destroy(instance)
	local s = state(instance)
	if s.service then
		error("Cannot destroy service " .. s.name, 2)
	end
	getSignal(instance, "Destroying"):Fire()
	for _, child in ipairs(table.clone(s.children)) do
		Methods.Destroy(child)
	end
	if s.parent then
		setParent(instance, nil)
	end
	s.destroyed = true
	s.parentLocked = true
	for _, signal in pairs(s.signals) do
		table.clear(signal._connections)
	end
end
Methods.Remove = Methods.Destroy

function Methods.Clone(instance)
	local s = state(instance)
	local copy = newInstance(s.className, false)
	local cs = state(copy)
	cs.name = s.name
	for key, value in pairs(s.props) do
		cs.props[key] = value
	end
	for key, value in pairs(s.attributes) do
		cs.attributes[key] = value
	end
	for tag in pairs(s.tags) do
		cs.tags[tag] = true
	end
	if s.refs then
		cs.refs = table.clone(s.refs)
	end
	Mock.CloneSource(instance, copy)
	for _, child in ipairs(s.children) do
		local childCopy = Methods.Clone(child)
		setParent(childCopy, copy)
	end
	return copy
end

function Methods.GetAttribute(instance, name)
	return state(instance).attributes[name]
end

function Methods.SetAttribute(instance, name, value)
	if type(name) ~= "string" or not string.match(name, "^[%w_]+$") or #name > 100 or string.sub(name, 1, 3) == "RBX" then
		error("Attribute name '" .. tostring(name) .. "' is invalid", 2)
	end
	if value ~= nil and not ATTRIBUTE_TYPES[mockTypeof(value)] then
		error(mockTypeof(value) .. " is not a supported attribute type", 2)
	end
	state(instance).attributes[name] = value
	getSignal(instance, "AttributeChanged"):Fire(name)
end

function Methods.GetAttributes(instance)
	return table.clone(state(instance).attributes)
end

function Methods.GetAttributeChangedSignal(instance, name)
	return getSignal(instance, "AttributeChanged:" .. name)
end

function Methods.GetPropertyChangedSignal(instance, name)
	return getSignal(instance, "Changed:" .. name)
end

function Methods.AddTag(instance, tag)
	state(instance).tags[tag] = true
end

function Methods.RemoveTag(instance, tag)
	state(instance).tags[tag] = nil
end

function Methods.HasTag(instance, tag)
	return state(instance).tags[tag] == true
end

function Methods.GetTags(instance)
	local list = {}
	for tag in pairs(state(instance).tags) do
		table.insert(list, tag)
	end
	table.sort(list)
	return list
end

-- Terrain voxels: everything is air unless a test marks water regions.
Classes.Terrain.Methods = {
	ReadVoxels = function(_terrain, region, _resolution)
		local inWater = false
		for _, box in ipairs(Mock.WaterRegions) do
			local center = region.CFrame.Position
			if center.X >= box.Min.X and center.X <= box.Max.X and center.Y >= box.Min.Y and center.Y <= box.Max.Y and center.Z >= box.Min.Z and center.Z <= box.Max.Z then
				inWater = true
			end
		end
		local material = if inWater then enumStore.Material.Water else enumStore.Material.Air
		return { { { material } } }, { { { if inWater then 1 else 0 } } }
	end,
}
Mock.WaterRegions = {}

---------------------------------------------------------------------------
-- Instance global
---------------------------------------------------------------------------

local InstanceGlobal = {}
function InstanceGlobal.new(className, parent)
	local definition = Classes[className]
	if not definition or definition.Abstract or definition.Service or definition.NotCreatable then
		error(string.format("Unable to create an Instance of type \"%s\"", tostring(className)), 2)
	end
	local instance = newInstance(className, false)
	if parent then
		setParent(instance, parent)
	end
	return instance
end

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------

local sources = setmetatable({}, { __mode = "k" })
Mock.Sources = sources
function Mock.CloneSource(from, to)
	if sources[from] then
		sources[to] = sources[from]
	end
end

--[[
	Creates a fresh DataModel. Returns the world table:
	{ game, workspace, env = globals to inject, RunService, ... }
]]
function Mock.createWorld(options)
	options = options or {}
	local game = newInstance("DataModel", true)
	state(game).name = "Game"
	local services = {}

	local function getService(_, name)
		if services[name] then
			return services[name]
		end
		local definition = Classes[name]
		if not definition or not definition.Service then
			error(string.format("'%s' is not a valid Service name", tostring(name)), 2)
		end
		local service = newInstance(name, true)
		state(service).name = name
		setParent(service, game)
		services[name] = service
		return service
	end
	Classes.DataModel.Methods = {
		GetService = getService,
		FindService = function(_, name)
			return services[name]
		end,
	}

	local workspaceService = getService(nil, "Workspace")
	local terrain = newInstance("Terrain", false)
	state(terrain).name = "Terrain"
	state(terrain).service = true
	setParent(terrain, workspaceService)
	local camera = newInstance("Camera", false)
	state(camera).name = "Camera"
	camera.CFrame = CFrame.new(0, 20, 20)
	setParent(camera, workspaceService)
	state(workspaceService).refs = { Terrain = terrain, CurrentCamera = camera }

	getService(nil, "Lighting")

	local runService = getService(nil, "RunService")
	local running = options.Running == true
	local client = options.Client == true
	Classes.RunService.Methods = {
		IsRunning = function()
			return running
		end,
		IsClient = function()
			return client
		end,
		IsServer = function()
			return not client
		end,
		IsStudio = function()
			return true
		end,
		IsEdit = function()
			return not running
		end,
	}

	local collection = getService(nil, "CollectionService")
	Classes.CollectionService.Methods = {
		AddTag = function(_, instance, tag)
			Methods.AddTag(instance, tag)
		end,
		RemoveTag = function(_, instance, tag)
			Methods.RemoveTag(instance, tag)
		end,
		HasTag = function(_, instance, tag)
			return Methods.HasTag(instance, tag)
		end,
		GetTagged = function(_, tag)
			local list = {}
			for instance in pairs(allInstances) do
				local s = state(instance)
				if s and not s.destroyed and s.tags[tag] and isDescendantOf(instance, game) then
					table.insert(list, instance)
				end
			end
			return list
		end,
		GetInstanceAddedSignal = function()
			return newSignal()
		end,
		GetInstanceRemovedSignal = function()
			return newSignal()
		end,
	}

	local history = getService(nil, "ChangeHistoryService")
	local waypoints = {}
	local recordingId = 0
	Classes.ChangeHistoryService.Methods = {
		SetWaypoint = function(_, name)
			table.insert(waypoints, name)
		end,
		TryBeginRecording = function(_, name)
			recordingId += 1
			return "recording-" .. recordingId
		end,
		FinishRecording = function(_, id, operation)
			table.insert(waypoints, tostring(id) .. ":" .. tostring(operation))
		end,
		Undo = function() end,
		Redo = function() end,
	}

	local selectionItems = {}
	getService(nil, "Selection")
	Classes.Selection.Methods = {
		Get = function()
			return table.clone(selectionItems)
		end,
		Set = function(_, items)
			selectionItems = table.clone(items)
		end,
	}

	getService(nil, "HttpService")
	Classes.HttpService.Methods = {
		GenerateGUID = function()
			return "00000000-0000-0000-0000-000000000000"
		end,
	}

	local world = {
		game = game,
		workspace = workspaceService,
		Terrain = terrain,
		Camera = camera,
		RunService = runService,
		CollectionService = collection,
		Waypoints = waypoints,
		setRunning = function(value)
			running = value
		end,
		setClient = function(value)
			client = value
		end,
	}

	local warnings = {}
	world.Warnings = warnings

	local taskQueue = {}
	local taskLibrary = {
		spawn = function(fn, ...)
			if type(fn) == "function" then
				fn(...)
			end
		end,
		defer = function(fn, ...)
			table.insert(taskQueue, { fn = fn, args = { ... } })
		end,
		delay = function(_, fn, ...)
			table.insert(taskQueue, { fn = fn, args = { ... } })
		end,
		wait = function(t)
			return t or 0
		end,
		cancel = function() end,
	}
	world.flushTasks = function()
		local queue = taskQueue
		taskQueue = {}
		for _, item in ipairs(queue) do
			item.fn(table.unpack(item.args))
		end
	end

	world.env = {
		game = game,
		workspace = workspaceService,
		Workspace = workspaceService,
		Instance = InstanceGlobal,
		Color3 = Color3,
		Vector3 = Vector3,
		Vector2 = Vector2,
		NumberRange = NumberRange,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		CFrame = CFrame,
		Region3 = Region3,
		UDim = UDim,
		UDim2 = UDim2,
		Random = Random,
		Font = Font,
		TweenInfo = TweenInfo,
		DockWidgetPluginGuiInfo = DockWidgetPluginGuiInfo,
		Enum = Enum,
		typeof = mockTypeof,
		task = taskLibrary,
		tick = os.clock,
		time = os.clock,
		wait = function(t)
			return t or 0
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring(select(i, ...)))
			end
			table.insert(warnings, table.concat(parts, " "))
		end,
		settings = function()
			return { Studio = { Theme = Mock.StudioTheme, ThemeChanged = Mock.ThemeChanged } }
		end,
		-- Scripts in one DataModel share _G (the CLI's own _G is read-only).
		_G = {},
	}
	return world
end

Mock.ThemeChanged = newSignal()

-- A stand-in for settings().Studio.Theme used by plugin UI smoke tests.
Mock.StudioTheme = {
	Name = "Dark",
	GetColor = function(_, _guideColor, _modifier)
		return Color3.fromRGB(46, 46, 46)
	end,
}

---------------------------------------------------------------------------
-- Plugin object
---------------------------------------------------------------------------

-- Creates a stand-in for the `plugin` global.
function Mock.createPlugin()
	local store = {}
	local pluginInstance = InstanceGlobal.new("Plugin")
	pluginInstance.Name = "VisualFXStudio"
	local opened = {}
	Classes.Plugin.Methods = {
		CreateToolbar = function(_, name)
			local toolbar = InstanceGlobal.new("PluginToolbar")
			toolbar.Name = name
			return toolbar
		end,
		CreateDockWidgetPluginGui = function(_, id, _info)
			local widget = InstanceGlobal.new("DockWidgetPluginGui")
			widget.Name = id
			widget.Enabled = false
			return widget
		end,
		GetSetting = function(_, key)
			return store[key]
		end,
		SetSetting = function(_, key, value)
			store[key] = value
		end,
		OpenScript = function(_, scriptInstance)
			table.insert(opened, scriptInstance)
		end,
	}
	Classes.PluginToolbar.Methods = {
		CreateButton = function(_, id, _tooltip, _icon, text)
			local button = InstanceGlobal.new("PluginToolbarButton")
			button.Name = id
			button.Text = text
			return button
		end,
	}
	Classes.PluginToolbarButton.Methods = {
		SetActive = function(button, active)
			button.Active = active
		end,
	}
	return pluginInstance, store, opened
end

---------------------------------------------------------------------------
-- Module loading
---------------------------------------------------------------------------

--[[
	Mounts a bundle tree ({ Name, ClassName, Source?, Children }) under parent
	and returns the root instance.
]]
function Mock.mount(node, parent)
	local instance = InstanceGlobal.new(node.ClassName)
	instance.Name = node.Name
	if node.Source then
		sources[instance] = { Source = node.Source, Path = node.Path }
	end
	for _, child in ipairs(node.Children or {}) do
		Mock.mount(child, instance)
	end
	instance.Parent = parent
	return instance
end

-- Creates a require() that loads ModuleScript instances from their sources.
function Mock.makeRequire(world, extraGlobals)
	local cache = {}
	local loading = {}
	local base = setmetatable({}, { __index = function(_, key)
		local value = world.env[key]
		if value ~= nil then
			return value
		end
		if extraGlobals and extraGlobals[key] ~= nil then
			return extraGlobals[key]
		end
		return _G[key] or getfenv(0)[key]
	end })

	local requireFn
	requireFn = function(target)
		if mockTypeof(target) ~= "Instance" then
			error("require expects a ModuleScript instance, got " .. mockTypeof(target), 2)
		end
		if cache[target] ~= nil then
			return cache[target]
		end
		if loading[target] then
			error("Requested module was required recursively: " .. target:GetFullName(), 2)
		end
		local source = sources[target]
		if not source or target.ClassName ~= "ModuleScript" then
			error("Attempted to call require with invalid argument(s): " .. target:GetFullName(), 2)
		end
		loading[target] = true
		local chunk, problem = loadstring(source.Source, "=" .. (source.Path or target:GetFullName()))
		if not chunk then
			loading[target] = nil
			error("Syntax error in " .. target:GetFullName() .. ": " .. tostring(problem), 2)
		end
		local env = setmetatable({ script = target, require = requireFn }, { __index = base })
		setfenv(chunk, env)
		local ok, result = pcall(chunk)
		loading[target] = nil
		if not ok then
			error(result, 0)
		end
		if result == nil then
			error("Module code did not return exactly one value: " .. target:GetFullName(), 2)
		end
		cache[target] = result
		return result
	end
	return requireFn
end

-- Runs a Script instance's source with the world's globals (for plugin smoke tests).
function Mock.runScript(world, scriptInstance, requireFn, extraGlobals)
	local source = sources[scriptInstance]
	local chunk, problem = loadstring(source.Source, "=" .. (source.Path or scriptInstance:GetFullName()))
	if not chunk then
		error(problem, 0)
	end
	local env = setmetatable({ script = scriptInstance, require = requireFn }, { __index = function(_, key)
		if extraGlobals and extraGlobals[key] ~= nil then
			return extraGlobals[key]
		end
		local value = world.env[key]
		if value ~= nil then
			return value
		end
		return _G[key] or getfenv(0)[key]
	end })
	setfenv(chunk, env)
	return chunk()
end

return Mock
