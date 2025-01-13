-- Implementation of iterative search along rails.
local lib = {}

local defines_front = defines.rail_direction.front
local defines_back = defines.rail_direction.back

---@class Cybersyn.Internal.IterativeRailSearchState
---@field public next_connected_rail any The argument to `get_connected_rail` used to iterate along the rails.
---@field public direction defines.direction? Absolute direction of the search in world space; established after 1 iteration.
---@field public rail LuaEntity? The current rail being examined
---@field public segment_rail LuaEntity? The rail defining the current segment being searched.
---@field public front_stop LuaEntity? The stop in the rail segment of the current rail corresponding to `defines.front`.
---@field public front_rail LuaEntity? The rail connected to `front_stop`.
---@field public back_stop LuaEntity? The stop in the rail segment of the current rail corresponding to `defines.back`.
---@field public back_rail LuaEntity? The rail connected to `back_stop`.
---@field public no_connected_rail true? `true` if the search ended because no next connected rail could be found in the given direction. In this case, `state.rail` will be the last rail checked.
---@field public check fun(state: Cybersyn.Internal.IterativeRailSearchState): boolean, any Perform the logic of this search. If the check returns `true` the search continues, if it returns `false` the search is done with the given result.

---@param rail LuaEntity
local function draw_rail_search_debug_overlay(rail)
	local l, t, r, b = bbox_get(rail.bounding_box)
	rendering.draw_rectangle({
		color = { r = 0, g = 1, b = 0, a = 0.5 },
		left_top = { l, t },
		right_bottom = { r, b },
		surface = rail.surface,
		time_to_live = 300,
	})
end

---Perform one step of a unidirectional iterative rail search.
---@param state Cybersyn.Internal.IterativeRailSearchState Iteration state. This is mutated by the ongoing iterative search.
---@return boolean continue Should the iteration continue?
---@return any result? The result of the search as defined by the check function.
local function rail_search_iteration(state)
	local current_rail = state.rail
	if not current_rail then return false, nil end

	if mod_settings.enable_debug_overlay then
		draw_rail_search_debug_overlay(current_rail)
	end

	-- Check if rail begins a new search segment.
	if (not state.segment_rail) or (not current_rail.is_rail_in_same_rail_segment_as(state.segment_rail)) then
		state.segment_rail = current_rail
		state.front_stop = current_rail.get_rail_segment_stop(defines_front)
		state.front_rail = state.front_stop and state.front_stop.connected_rail
		state.back_stop = current_rail.get_rail_segment_stop(defines_back)
		state.back_rail = state.back_stop and state.back_stop.connected_rail
	end

	-- Run the user-defined check.
	local cont, result = state.check(state)
	if not cont then return false, result end

	-- Iterate to the next rail.
	local next_rail = current_rail.get_connected_rail(state.next_connected_rail)
	if not next_rail then
		state.no_connected_rail = true
		return false, nil
	end
	if not state.direction then
		state.direction = dir_ortho(current_rail.position, next_rail.position)
	end
	state.rail = next_rail
	return true, nil
end

---Perform an iterative search along rails.
---@param state Cybersyn.Internal.IterativeRailSearchState Initial state of the search.
---@param max_iterations integer Maximum number of iterations to perform.
---@return any? #The result of the search as defined by the check function.
function lib.search(state, max_iterations)
	local n = 1
	while n <= max_iterations do
		local cont, result = rail_search_iteration(state)
		if not cont then return result end
		n = n + 1
	end
end

return lib
