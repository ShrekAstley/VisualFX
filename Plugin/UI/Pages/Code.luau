--[[
	Code page: deterministic Luau generated from the current configuration.
	Studio plugins cannot write to the system clipboard, so "Copy" focuses
	the code and selects it (press Ctrl+C / Cmd+C); "Export" writes a script
	into the place and opens it.
]]
local Theme = require(script.Parent.Parent.Theme)

return function(context)
	local ui, controller = context.UI, context.Controller
	local frame = ui:Stack(Theme.Spacing.Medium)
	local page = { Name = "Code", Frame = frame }

	local templates = require(context.Library.Codegen.Templates)
	local template = controller.Settings.CodeTemplate
	local info = ui:Label("", { Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 2 })
	local templateDropdown = ui:Dropdown(templates.Names, template, function(choice)
		template = choice
		controller:SetSetting("CodeTemplate", choice)
		page:Refresh(true)
	end)
	ui:Row("Template", templateDropdown.Instance, { LayoutOrder = 1 }).Parent = frame
	info.Parent = frame

	local code = ui:CodeBox("", { Height = 360, Editable = false, LayoutOrder = 3 })
	code.Instance.Parent = frame
	local message = ui:Label("", { Dim = true, TextSize = Theme.TextSize.Small, LayoutOrder = 5 })

	ui:ButtonBar({
		ui:Button("Regenerate", function()
			page:Refresh(true)
		end),
		ui:Button("Copy", function()
			code:SelectAll()
			message.Text = "Code selected — press Ctrl+C (Cmd+C on macOS) to copy."
		end),
		ui:Button("Export to place", function()
			local result = controller:ExportCode(template)
			message.Text = if result.Success then result.Message else table.concat(result.Errors, "\n")
		end, { Style = "Primary" }),
	}, 4).Parent = frame
	message.Parent = frame

	function page:Refresh()
		info.Text = templates.Descriptions[template] or ""
		local result = controller:GenerateCode(template)
		code:Set(if result.Success then result.Code else "-- " .. table.concat(result.Errors, "\n-- "))
	end

	return page
end
