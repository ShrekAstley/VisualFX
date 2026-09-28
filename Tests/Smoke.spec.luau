return function(t)
	local expect = t.expect

	t.describe("Smoke", function()
		t.it("creates an engine and applies a preset", function()
			local engine = t.newEngine()
			local result = engine:ApplyPreset("MistyForest")
			if not result.Success then
				error(table.concat(result.Errors, "\n"))
			end
			expect(result.Success).toBe(true)
			expect(#result.Created).toBeGreaterThan(0)
		end)
	end)
end
