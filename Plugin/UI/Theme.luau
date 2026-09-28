--[[
	VisualFX Studio theme. Colors come from the active Studio theme
	(settings().Studio.Theme:GetColor) so the plugin matches Light and Dark
	themes; a dark fallback palette is used if the API is unavailable.
]]

local Theme = {}

local FALLBACK = {
	Background = Color3.fromRGB(37, 37, 37),
	Panel = Color3.fromRGB(46, 46, 46),
	PanelAlt = Color3.fromRGB(53, 53, 53),
	Border = Color3.fromRGB(34, 34, 34),
	Text = Color3.fromRGB(220, 220, 220),
	SubText = Color3.fromRGB(150, 150, 150),
	Input = Color3.fromRGB(30, 30, 30),
	InputBorder = Color3.fromRGB(70, 70, 70),
	Button = Color3.fromRGB(60, 60, 60),
	ButtonText = Color3.fromRGB(220, 220, 220),
	Hover = Color3.fromRGB(66, 66, 66),
	Selected = Color3.fromRGB(11, 90, 175),
	Accent = Color3.fromRGB(0, 162, 255),
	AccentText = Color3.fromRGB(255, 255, 255),
	Error = Color3.fromRGB(235, 87, 87),
	Warning = Color3.fromRGB(242, 179, 61),
	Success = Color3.fromRGB(76, 175, 80),
	Info = Color3.fromRGB(100, 160, 230),
}

local STUDIO_COLORS = {
	Background = "MainBackground",
	Panel = "Titlebar",
	PanelAlt = "CategoryItem",
	Border = "Border",
	Text = "MainText",
	SubText = "SubText",
	Input = "InputFieldBackground",
	InputBorder = "InputFieldBorder",
	Button = "Button",
	ButtonText = "ButtonText",
	Hover = "Item",
	Selected = "CurrentMarker",
	Accent = "LinkText",
	Error = "ErrorText",
	Warning = "WarningText",
	Info = "InfoText",
}

Theme.Fonts = {
	Body = Enum.Font.SourceSans,
	Strong = Enum.Font.SourceSansSemibold,
	Heading = Enum.Font.SourceSansBold,
	Code = Enum.Font.RobotoMono,
}

Theme.TextSize = { Small = 12, Body = 14, Heading = 16, Title = 18 }
Theme.Spacing = { Tight = 2, Small = 4, Medium = 8, Large = 12 }
Theme.RowHeight = 26

local function studioTheme()
	local ok, theme = pcall(function()
		return settings().Studio.Theme
	end)
	return if ok then theme else nil
end

-- Returns the current palette as a table of Color3 values.
function Theme.Palette(): { [string]: Color3 }
	local palette = table.clone(FALLBACK)
	local theme = studioTheme()
	if theme then
		for key, guideName in pairs(STUDIO_COLORS) do
			local ok, color = pcall(function()
				return theme:GetColor((Enum.StudioStyleGuideColor :: any)[guideName])
			end)
			if ok and typeof(color) == "Color3" then
				palette[key] = color
			end
		end
	end
	palette.AccentText = FALLBACK.AccentText
	palette.Success = FALLBACK.Success
	return palette
end

-- Calls `callback` whenever the Studio theme changes. Returns the connection or nil.
function Theme.OnChanged(callback: () -> ())
	local ok, connection = pcall(function()
		return settings().Studio.ThemeChanged:Connect(callback)
	end)
	return if ok then connection else nil
end

return Theme
