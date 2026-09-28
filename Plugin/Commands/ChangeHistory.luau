--[[
	Undo integration. Uses ChangeHistoryService:TryBeginRecording /
	FinishRecording when available and falls back to SetWaypoint on older
	Studio builds. VisualFX's own preview journal handles Revert; this module
	only makes applied changes undoable with Ctrl+Z.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local ChangeHistory = {}

local function hasRecordingApi(): boolean
	local ok = pcall(function()
		return ChangeHistoryService.TryBeginRecording
	end)
	return ok
end

-- Begins an undoable operation. Returns a handle for Finish.
function ChangeHistory.Begin(name: string)
	if hasRecordingApi() then
		local ok, id = pcall(function()
			return ChangeHistoryService:TryBeginRecording(name, name)
		end)
		if ok and id then
			return { Id = id, Name = name }
		end
	end
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before " .. name)
	end)
	return { Name = name }
end

-- Completes an operation so it appears as one undo step.
function ChangeHistory.Finish(handle)
	if not handle then
		return
	end
	if handle.Id then
		pcall(function()
			ChangeHistoryService:FinishRecording(handle.Id, Enum.FinishRecordingOperation.Commit)
		end)
	else
		pcall(function()
			ChangeHistoryService:SetWaypoint(handle.Name)
		end)
	end
end

-- Runs fn as a single undoable operation.
function ChangeHistory.Record(name: string, fn: () -> any): any
	local handle = ChangeHistory.Begin(name)
	local ok, result = pcall(fn)
	ChangeHistory.Finish(handle)
	if not ok then
		error(result, 0)
	end
	return result
end

return ChangeHistory
