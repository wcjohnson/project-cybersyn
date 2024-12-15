-- Stop layout and equipment detection.

-- Don't allow this file to be included twice. We are using transient local
-- state during stop layout scans to allow external event-driven equipment
-- detection.
if _G._require_guard_stop_layout then
	return
else
	_G._require_guard_stop_layout = true
end

local flib_bbox = require("__flib__.bounding-box")
local flib_table = require("__flib__.table")
local flib_direction = require("__flib__.direction")
local bbox_contain = bbox_contain
local bbox_extend = bbox_extend

local defines_front = defines.rail_direction.front
local defines_back = defines.rail_direction.back
local defines_straight = defines.rail_connection_direction.straight
local connected_rail_fwd = {
	rail_direction = defines_front,
	rail_connection_direction = defines_straight,
}
local connected_rail_rev = {
	rail_direction = defines_back,
	rail_connection_direction = defines_straight,
}

-- Maximum number of rail entities to search in iterative rail searches.
local MAX_RAILS_TO_SEARCH = 112 -- TODO: why 112?

-- List of prototypes that are considered equipment when scanning stops.
local equipment_type_list = { "inserter", "pump", "arithmetic-combinator", "loader-1x1", "loader" }

---@class Cybersyn.Internal.IterativeRailSearchState
---@field public next_connected_rail any One of `connected_rail_fwd` or `connected_rail_rev`.
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

---Perform one step of an iterative rail search.
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

---Check function to find nearest associated train stop in an iterative rail search.
---@param state Cybersyn.Internal.IterativeRailSearchState
local function search_for_stop(state)
	local current_rail = state.rail --[[@as LuaEntity]]
	-- Non-straight rail = done
	if current_rail.type ~= "straight-rail" then return false, nil end
	-- If rail reaches a stop, we're done. If the stop is in a good direction
	-- the search is successful, otherwise don't go further.
	if current_rail == state.front_rail then
		if (not state.direction) or state.direction == state.front_stop.direction then
			return false, state.front_stop
		else
			return false, nil
		end
	elseif current_rail == state.back_rail then
		if (not state.direction) or state.direction == state.back_stop.direction then
			return false, state.back_stop
		else
			return false, nil
		end
	end
	return true
end

---Find the stop associated to the given rail entity. Attempts to move in both directions, looking for the
---first stop it finds, stopping under the same conditions as the layout scanner.
---@param rail_entity LuaEntity A *valid* rail.
---@return LuaEntity? stop_entity The stop entity, if found.
function stop_api.find_nearest_stop_from_rail(rail_entity)
	---@type Cybersyn.Internal.IterativeRailSearchState?
	local fwd_search = { rail = rail_entity, next_connected_rail = connected_rail_fwd, check = search_for_stop }
	---@type Cybersyn.Internal.IterativeRailSearchState?
	local rev_search = { rail = rail_entity, next_connected_rail = connected_rail_rev, check = search_for_stop }
	local rail_number = 1
	local cont = false
	while rail_number < MAX_RAILS_TO_SEARCH do
		if fwd_search then
			cont, stop = rail_search_iteration(fwd_search)
			if stop then return stop end
			if not cont then fwd_search = nil end
		end

		if rev_search then
			cont, stop = rail_search_iteration(rev_search)
			if stop then return stop end
			if not cont then rev_search = nil end
		end

		if not fwd_search and not rev_search then break end
		rail_number = rail_number + 1
	end
end

---Update the layout of the train stop state nearest this rail.
---@param rail_entity LuaEntity A *valid* rail.
---@return boolean #Whether the layout was updated.
function stop_api.update_layout_from_rail(rail_entity)
	local stop_entity = stop_api.find_nearest_stop_from_rail(rail_entity)
	if not stop_entity then return false end
	local stop = stop_api.get_stop_state(stop_entity.unit_number, true)
	if stop then
		stop_api.compute_layout(stop)
		return true
	else
		return false
	end
end

---Clear the layout of a train stop state.
---Also disassociates all distant combinators.
---@param stop_state Cybersyn.TrainStop A *valid* train stop state.
function stop_api.clear_layout(stop_state)
	stop_state.layout.accepted_layouts = {}
	stop_state.layout.legacy_layout_pattern = nil

	local distant_combinators = map_table(stop_state.combinator_set, function(_, comb_id)
		local comb = combinator_api.get_combinator_state(comb_id)
		if comb and comb.distance then return comb end
	end)

	for _, comb in ipairs(distant_combinators) do
		comb.stop_id = nil
		stop_state.combinator_set[comb.id] = nil
		raise_combinator_disassociated(comb, stop_state)
	end
	if #distant_combinators > 0 then
		raise_train_stop_combinator_set_changed(stop_state)
		-- Destroy the stop if there are no combinators left.
		if next(stop_state.combinator_set) == nil then
			stop_api.destroy_stop(stop_state.id)
		end
	end
end

---Iterative check function to find bbox of a station.
---@param state Cybersyn.Internal.IterativeRailSearchState
local function search_for_station_end(state)
	local current_rail = state.rail --[[@as LuaEntity]]
	if current_rail.type ~= "straight-rail" then return false end

	-- TODO: Check for splits in the track here by also evaluating `rail_connection_direction.left/right`. This would be a breaking change as current allowlists scan past splits.

	-- If we reach a stop that isn't our target stop, abort.
	---@diagnostic disable-next-line: undefined-field
	if current_rail == state.front_rail and state.front_stop ~= state.layout_stop then
		return false
		---@diagnostic disable-next-line: undefined-field
	elseif current_rail == state.back_rail and state.back_stop ~= state.layout_stop then
		return false
	end

	-- Extend the bounding box to include the current rail.
	---@diagnostic disable-next-line: undefined-field
	bbox_contain(state.bbox, current_rail.bounding_box)
	---@diagnostic disable-next-line: undefined-field
	state.rail_set[current_rail] = true
	return true
end

-- State of current equipment scan. This is a transient local value valid only
-- synchronously during each scan.
---@type Cybersyn.TrainStop.LayoutScanState
---@diagnostic disable-next-line: missing-fields
local scan_state = {}

---@param stop_state Cybersyn.TrainStop A *valid* train stop state.
---@param ignored_entity_set? {[LuaEntity]: true?} A set of entities to ignore when scanning for equipment. Used for e.g. equipment that is in the process of being destroyed.
function stop_api.compute_layout(stop_state, ignored_entity_set)
	if stop_state.is_being_destroyed then return end
	local stop_id = stop_state.id

	local stop_rail = stop_state.entity.connected_rail
	if stop_rail == nil then
		-- Disconnected station; clear whole layout.
		stop_api.clear_layout(stop_state)
		return
	end

	local rail_direction_from_stop
	if stop_state.entity.connected_rail_direction == defines_front then
		rail_direction_from_stop = defines_back
	else
		rail_direction_from_stop = defines_front
	end
	local stop_direction = stop_state.entity.direction
	local direction_from_stop = flib_direction.opposite(stop_direction)
	local is_vertical = (stop_direction == defines.direction.north or stop_direction == defines.direction.south)

	-- Compute a bounding box that encompasses the entire equipment area.
	---@type Cybersyn.Internal.IterativeRailSearchState
	local state = {
		rail = stop_rail,
		next_connected_rail = {
			rail_direction = rail_direction_from_stop,
			rail_connection_direction = defines_straight,
		},
		check = search_for_station_end,
		bbox = flib_table.deep_copy(stop_rail.bounding_box),
		layout_stop = stop_state.entity,
		rail_set = {},
	}
	local rail_number = 1
	while rail_number < MAX_RAILS_TO_SEARCH do
		local cont = rail_search_iteration(state)
		if not cont then break end
		rail_number = rail_number + 1
	end
	local bbox = state.bbox
	-- If the search ended on a curve, add 3 tiles of grace.
	if state.no_connected_rail and state.rail then
		local curve = state.rail.get_connected_rail({
					rail_direction = rail_direction_from_stop,
					rail_connection_direction = defines.rail_connection_direction.left,
				}) or
				state.rail.get_connected_rail({
					rail_direction = rail_direction_from_stop,
					rail_connection_direction = defines.rail_connection_direction.right,
				})
		if curve and (curve.type == "curved-rail-a" or curve.type == "curved-rail-b") then
			bbox_extend(bbox, direction_from_stop, 3)
		end
	end
	-- Fatten the bbox in the perpendicular direction to account for equipment
	-- alongside the rails.
	local reach = LONGEST_INSERTER_REACH
	local l, t, r, b = bbox_get(bbox)
	if is_vertical then
		l = l - reach
		r = r + reach
		bbox_set(bbox, l, t, r, b)
	else
		t = t - reach
		b = b + reach
		bbox_set(bbox, l, t, r, b)
	end
	bbox = flib_bbox.ceil(bbox)

	-- Associate distant combinators.
	local rail_set = state.rail_set
	local comb_entities = combinator_api.find_combinator_entities(stop_state.entity.surface, bbox)
	local associable_combinators = map(comb_entities, function(entity)
		local comb = combinator_api.get_combinator_state(entity.unit_number)
		if not comb then return end
		if comb.stop_id then
			-- Steal combinators that are pointing at our rails.
			if comb.stop_id ~= stop_id then
				local stop, rail = combinator_api.find_associable_entity(entity)
				if (not stop) and rail and rail_set[rail] then
					return comb
				end
			end
		else
			-- Grab unassociated combinators
			return comb
		end
	end)
	for _, combinator in pairs(associable_combinators) do
		if combinator.stop_id then
			-- Stolen combinator.
			-- Hopefully this is rare and we don't need to batch these events.
			local old_stop = stop_api.get_stop_state(combinator.stop_id)
			if old_stop then stop_api.disassociate_combinator(old_stop, combinator) end
		end
		combinator.stop_id = stop_id
		-- Measure the number of tiles back from the stop the combinator is
		combinator.distance = math.floor(dist_ortho_bbox(bbox, direction_from_stop, combinator.entity.position))
		stop_state.combinator_set[combinator.id] = true
		raise_combinator_associated(combinator, stop_state)
	end
	if #associable_combinators > 0 then
		raise_train_stop_combinator_set_changed(stop_state)
	end

	-- Now, scan for loading equipment.
	-- Create an equipment search state
	scan_state = {
		bbox = bbox,
		direction = stop_direction,
		equipment_prototype_names = {},
		equipment_prototype_types = {},
		stop = stop_state,
	}
	raise_train_stop_layout_pre_scan(scan_state)

	-- local search_area
	-- local area_delta
	-- local is_vertical
	-- if stop_direction == defines.direction.north then
	-- 	search_area = { { middle_x - reach, middle_y }, { middle_x + reach, middle_y + 6 } }
	-- 	area_delta = { 0, 7 }
	-- 	is_vertical = true
	-- elseif stop_direction == defines.direction.east then
	-- 	search_area = { { middle_x - 6, middle_y - reach }, { middle_x, middle_y + reach } }
	-- 	area_delta = { -7, 0 }
	-- 	is_vertical = false
	-- elseif stop_direction == defines.direction.south then
	-- 	search_area = { { middle_x - reach, middle_y - 6 }, { middle_x + reach, middle_y } }
	-- 	area_delta = { 0, -7 }
	-- 	is_vertical = true
	-- elseif stop_direction == defines.direction.west then
	-- 	search_area = { { middle_x, middle_y - reach }, { middle_x + 6, middle_y + reach } }
	-- 	area_delta = { 7, 0 }
	-- 	is_vertical = false
	-- else
	-- 	assert(false, "cybersyn: invalid stop direction")
	-- end
	-- local length = 1
	-- ---@type LuaEntity?
	-- local pre_rail = stop_rail
	-- local layout_pattern = { 0 }
	-- local wagon_number = 0
	-- for i = 1, 112 do
	-- 	if pre_rail then
	-- 		local rail, rail_direction, rail_connection_direction = pre_rail.get_connected_rail({
	-- 			rail_direction = rail_direction_from_stop,
	-- 			rail_connection_direction = defines_straight,
	-- 		})
	-- 		if not rail or rail_connection_direction ~= defines_straight then
	-- 			-- There is a curved rail or break in the tracks at this point
	-- 			-- We are assuming it's a curved rail, maybe that's a bad assumption
	-- 			-- We stop searching to expand the allow list after we see a curved rail
	-- 			-- We are allowing up to 3 tiles of extra allow list usage on a curved rail
	-- 			length = length + 3
	-- 			pre_rail = nil
	-- 		else
	-- 			pre_rail = rail
	-- 			length = length + 2
	-- 		end
	-- 	end
	-- 	if length >= 6 or not pre_rail then
	-- 		if not pre_rail then
	-- 			if length <= 0 then
	-- 				-- No point searching nothing
	-- 				-- Once we hit a curve and process the 3 extra tiles we break here
	-- 				-- This is the only breakpoint in this for loop
	-- 				break
	-- 			end
	-- 			-- Minimize the search_area to include only the straight section of track and the 3 tiles of the curved rail
	-- 			local missing_rail_length = 6 - length
	-- 			if missing_rail_length > 0 then
	-- 				if stop_direction == defines.direction.north then
	-- 					search_area[2][2] = search_area[2][2] - missing_rail_length
	-- 				elseif stop_direction == defines.direction.east then
	-- 					search_area[1][1] = search_area[1][1] + missing_rail_length
	-- 				elseif stop_direction == defines.direction.south then
	-- 					search_area[1][2] = search_area[1][2] + missing_rail_length
	-- 				else
	-- 					search_area[2][1] = search_area[2][1] - missing_rail_length
	-- 				end
	-- 			end
	-- 		end
	-- 		length = length - 7
	-- 		wagon_number = wagon_number + 1
	-- 		local supports_cargo = false
	-- 		local supports_fluid = false
	-- 		local entities = surface.find_entities_filtered({
	-- 			area = search_area,
	-- 			type = type_filter,
	-- 		})
	-- 		for _, entity in pairs(entities) do
	-- 			if entity ~= forbidden_entity then
	-- 				if entity.type == "inserter" then
	-- 					if not supports_cargo then
	-- 						local pos = entity.pickup_position
	-- 						local is_there
	-- 						if is_vertical then
	-- 							is_there = middle_x - 1 <= pos.x and pos.x <= middle_x + 1
	-- 						else
	-- 							is_there = middle_y - 1 <= pos.y and pos.y <= middle_y + 1
	-- 						end
	-- 						if is_there then
	-- 							supports_cargo = true
	-- 						else
	-- 							pos = entity.drop_position
	-- 							if is_vertical then
	-- 								is_there = middle_x - 1 <= pos.x and pos.x <= middle_x + 1
	-- 							else
	-- 								is_there = middle_y - 1 <= pos.y and pos.y <= middle_y + 1
	-- 							end
	-- 							if is_there then
	-- 								supports_cargo = true
	-- 							end
	-- 						end
	-- 					end
	-- 				elseif entity.type == "loader-1x1" then
	-- 					if not supports_cargo then
	-- 						local pos = entity.position
	-- 						local direction = entity.direction
	-- 						local is_there
	-- 						if is_vertical then
	-- 							is_there = middle_x - 1.5 <= pos.x and pos.x <= middle_x + 1.5
	-- 						else
	-- 							is_there = middle_y - 1.5 <= pos.y and pos.y <= middle_y + 1.5
	-- 						end
	-- 						if is_there then
	-- 							if is_vertical then
	-- 								if direction == defines.direction.east or direction == defines.direction.west then
	-- 									supports_cargo = true
	-- 								end
	-- 							elseif direction == defines.direction.north or direction == defines.direction.south then
	-- 								supports_cargo = true
	-- 							end
	-- 						end
	-- 					end
	-- 				elseif entity.type == "loader" then
	-- 					-- TODO: entities of type `loader` are 1x2 loaders. This code
	-- 					-- existed in 1.1, but 1x2 loaders are not fully supported elsewhere
	-- 					-- in the code. 1x2 loader support is a TODO.
	-- 					if not supports_cargo then
	-- 						local direction = entity.direction
	-- 						if is_vertical then
	-- 							if direction == defines.direction.east or direction == defines.direction.west then
	-- 								supports_cargo = true
	-- 							end
	-- 						elseif direction == defines.direction.north or direction == defines.direction.south then
	-- 							supports_cargo = true
	-- 						end
	-- 					end
	-- 				elseif entity.type == "pump" then
	-- 					if not supports_fluid and entity.pump_rail_target then
	-- 						local direction = entity.direction
	-- 						if is_vertical then
	-- 							if direction == defines.direction.east or direction == defines.direction.west then
	-- 								supports_fluid = true
	-- 							end
	-- 						elseif direction == defines.direction.north or direction == defines.direction.south then
	-- 							supports_fluid = true
	-- 						end
	-- 					end
	-- 				elseif entity.name == COMBINATOR_NAME then
	-- 					local param = map_data.to_comb_params[entity.unit_number]
	-- 					if param.operation == MODE_WAGON then
	-- 						local pos = entity.position
	-- 						local is_there
	-- 						if is_vertical then
	-- 							is_there = middle_x - 2.1 <= pos.x and pos.x <= middle_x + 2.1
	-- 						else
	-- 							is_there = middle_y - 2.1 <= pos.y and pos.y <= middle_y + 2.1
	-- 						end
	-- 						if is_there then
	-- 							if not stop.wagon_combs then
	-- 								stop.wagon_combs = {}
	-- 							end
	-- 							stop.wagon_combs[wagon_number] = entity
	-- 						end
	-- 					end
	-- 				end
	-- 			end
	-- 		end

	-- 		if supports_cargo then
	-- 			if supports_fluid then
	-- 				layout_pattern[wagon_number] = 3
	-- 			else
	-- 				layout_pattern[wagon_number] = 1
	-- 			end
	-- 		elseif supports_fluid then
	-- 			layout_pattern[wagon_number] = 2
	-- 		else
	-- 			--layout_pattern[wagon_number] = nil
	-- 		end
	-- 		search_area = area.move(search_area, area_delta)
	-- 	end
	-- end
	-- stop.layout_pattern = layout_pattern
	-- if is_station_or_refueler then
	-- 	for id, layout in pairs(map_data.layouts) do
	-- 		stop.accepted_layouts[id] = is_layout_accepted(layout_pattern, layout) or nil
	-- 	end
	-- else
	-- 	for id, layout in pairs(map_data.layouts) do
	-- 		stop.accepted_layouts[id] = is_refuel_layout_accepted(layout_pattern, layout) or nil
	-- 	end
	-- end
end

on_train_stop_layout_pre_scan(function(event)
	local stop = stop_api.get_stop_state(event.stop_id)
	if stop then
		stop_api.compute_layout(stop)
	end
end)
