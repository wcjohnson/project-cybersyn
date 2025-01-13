-- Stop equipment detection and auto-allowlist generation.

if _G._require_guard_stop_layout_equipment then
	return
else
	_G._require_guard_stop_layout_equipment = true
end

local flib_bbox = require("__flib__.bounding-box")

-- TODO: make this customizable. Since this is also used by main.lua to connect to build events, however this is done will have to be very early in the control phase.
local equipment_types_set = { inserter = true, ["loader-1x1"] = true, pump = true, loader = true }
local equipment_types = map_table(equipment_types_set, function(_, k) return k end)
local equipment_names_set = {}
local equipment_names = map_table(equipment_names_set, function(_, k) return k end)

---Get a list of prototype types of equipment that might be used for loading and unloading at a stop.
---@return string[]
function stop_api.get_equipment_types()
	return equipment_types
end

---Check if a string is a type of a piece of equipment that might be used for loading and unloading at a stop.
---@param type string?
function stop_api.is_equipment_type(type)
	return equipment_types_set[type or ""] or false
end

---Get a list of prototype names of equipment that might be used for loading and unloading at a stop.
---@return string[]
function stop_api.get_equipment_names()
	return equipment_names
end

---Check if a string is the name of a piece of equipment that might be used for loading and unloading at a stop.
---@param name string?
function stop_api.is_equipment_name(name)
	return equipment_names_set[name or ""] or false
end

---@param layout_pattern (0|1|2|3)[]
---@param layout (0|1|2)[]
---@return boolean
function is_refuel_layout_accepted(layout_pattern, layout)
	local valid = true
	for i, v in ipairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and (p == 1 or p == 3)) or (v == 2 and (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	if valid or not layout[0] then return valid end
	for i, v in irpairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and (p == 1 or p == 3)) or (v == 2 and (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	return valid
end

---@param layout_pattern (0|1|2|3)[]
---@param layout (0|1|2)[]
---@return boolean
function is_station_layout_accepted(layout_pattern, layout)
	local valid = true
	for i, v in ipairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and not (p == 1 or p == 3)) or (v == 2 and not (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	if valid or not layout[0] then return valid end
	-- LORD: does this code even make sense? `valid` is already false at this point...?
	for i, v in irpairs(layout) do
		local p = layout_pattern[i] or 0
		if (v == 1 and not (p == 1 or p == 3)) or (v == 2 and not (p == 2 or p == 3)) then
			valid = false
			break
		end
	end
	return valid
end

---Register or unregister a piece of loading equipment for the given stop.
---(If `false` is passed for both `is_fluid` and `is_cargo`, the equipment is unregistered.)
---@param stop_id UnitNumber The ID of the stop to register the equipment with.
---@param entity LuaEntity A *valid* equipment entity.
---@param pos MapPosition The effective position of the equipment for loading/unloading (for an inserter this may be e.g. the drop position). When unregistering equipment, this value is ignored.
---@param is_cargo boolean Whether the equipment can load/unload cargo.
---@param is_fluid boolean Whether the equipment can load/unload fluid.
---@return boolean #Whether the equipment was registered.
function stop_api.register_loading_equipment(stop_id, entity, pos, is_cargo, is_fluid)
	local stop_state = stop_api.get_stop_state(stop_id)
	if not stop_state then return false end
	local equipment_id = entity.unit_number --[[@as UnitNumber]]
	-- Compute position relative to stop.
	local tile_index = math.floor(dist_ortho_bbox(stop_state.layout.bbox, stop_state.layout.direction, pos))
	if is_cargo then
		stop_state.layout.cargo_loader_map[equipment_id] = tile_index
	else
		stop_state.layout.cargo_loader_map[equipment_id] = nil
	end
	if is_fluid then
		stop_state.layout.fluid_loader_map[equipment_id] = tile_index
	else
		stop_state.layout.fluid_loader_map[equipment_id] = nil
	end
	stop_api.enqueue_stop_update(stop_id, StopUpdateFlags.EQUIPMENT)
	return true
end

---Get car index from tile index. Assumes hard-coded length of 6 tiles per car.
---@param tile_index integer
---@return integer car_index 1-based index of car; 0 in the event of a problem.
local function get_car_index_from_tile_index(tile_index)
	if tile_index % 7 == 0 then return 0 end -- gap between cars
	local res = math.floor(tile_index / 7) + 1
	-- Users needing degenerately-long trains should use custom allowlists.
	if res < 1 or res > 32 then return 0 else return res end
end

---Recompute the stop's layout pattern from its loader maps.
---@param stop Cybersyn.TrainStop
---@param flags int
local function check_loading_equipment_pattern(stop, flags)
	-- Equipment pattern only needs to be updated when equipment or type changes.
	if not bit32.band(flags, bit32.bor(StopUpdateFlags.EQUIPMENT, StopUpdateFlags.TYPE)) then return end

	-- TODO: I think this could theoretically be changed to allow for modded
	-- wagons, provided that those modded wagons had tile-aligned length and
	-- gap sizes. This would require that the train layout system be changed
	-- to reflect the actual wagon items, along with some way of calculating
	-- the width in tiles of the wagons and their gaps.

	local max_car = 1
	local layout_pattern = { 0 }
	for _, tile_index in pairs(stop.layout.cargo_loader_map) do
		local car_index = get_car_index_from_tile_index(tile_index)
		if car_index == 0 then goto continue end
		if car_index > max_car then max_car = car_index end
		local previous_pattern = layout_pattern[car_index]
		if (previous_pattern == 2) or (previous_pattern == 3) then
			layout_pattern[car_index] = 3
		else
			layout_pattern[car_index] = 1
		end
		::continue::
	end
	for _, tile_index in pairs(stop.layout.fluid_loader_map) do
		local car_index = get_car_index_from_tile_index(tile_index)
		if car_index == 0 then goto continue end
		if car_index > max_car then max_car = car_index end
		local previous_pattern = layout_pattern[car_index]
		if (previous_pattern == 1) or (previous_pattern == 3) then
			layout_pattern[car_index] = 3
		else
			layout_pattern[car_index] = 2
		end
		::continue::
	end
	for i = 1, max_car do
		if layout_pattern[i] == nil then layout_pattern[i] = 0 end
	end
	if not table_compare(layout_pattern, stop.layout.loading_equipment_pattern) then
		stop.layout.loading_equipment_pattern = layout_pattern
		raise_train_stop_loading_equipment_pattern_changed(stop)
		stop_api.check_all_layouts(stop)
	end
end

-- Whenever a stop undergoes state update, check its loading equipment pattern.
on_train_stop_state_check(check_loading_equipment_pattern)

---Check if a stop accepts a given layout from the train layout cache.
---@param stop_state Cybersyn.TrainStop A *valid* train stop state.
---@param layout_id integer The ID of the layout to check.
---@return boolean #Whether the stop's accepted layout cache was changed.
local function check_if_accepts_layout(stop_state, layout_id)
	local map_data = storage --[[@as MapData]]
	local layout = map_data.train_layouts[layout_id] or {}
	local is_accepted = false
	if stop_api.is_refueler(stop_state.id) then
		is_accepted = is_refuel_layout_accepted(stop_state.layout.loading_equipment_pattern, layout)
	elseif stop_api.is_station(stop_state.id) then
		is_accepted = is_station_layout_accepted(stop_state.layout.loading_equipment_pattern, layout)
	end
	local set_value = is_accepted and true or nil
	if set_value ~= stop_state.layout.accepted_layouts[layout_id] then
		stop_state.layout.accepted_layouts[layout_id] = set_value
		return true
	else
		return false
	end
end

---Recheck a single cached train layout against this stop's layout pattern.
---@param stop_state Cybersyn.TrainStop A *valid* train stop state.
---@param layout_id integer The ID of the layout to check.
function stop_api.check_one_layout(stop_state, layout_id)
	if check_if_accepts_layout(stop_state, layout_id) then
		raise_train_stop_accepted_layouts_changed(stop_state)
	end
end

---Recheck all cached train layouts against this stop's layout pattern.
---@param stop_state Cybersyn.TrainStop A *valid* train stop state.
function stop_api.check_all_layouts(stop_state)
	local map_data = storage --[[@as MapData]]
	local updated = false
	for layout_id in pairs(map_data.layouts) do
		updated = updated or check_if_accepts_layout(stop_state, layout_id)
	end
	if updated then
		raise_train_stop_accepted_layouts_changed(stop_state)
	end
end

---Rebuild the entire loader map for a stop by scanning its bbox for equipment. This should only be called by `update_layout`.
---@param stop_state Cybersyn.TrainStop A *valid* train stop state.
---@param ignored_entity_set UnitNumberSet? A set of equipment entities to ignore.
function internal_scan_equipment(stop_state, ignored_entity_set)
	local bbox = stop_state.layout.bbox
	local stop_entity = stop_state.entity

	stop_state.layout.cargo_loader_map = {}
	stop_state.layout.fluid_loader_map = {}

	local equipment_by_type = stop_entity.surface.find_entities_filtered({
		area = bbox,
		type = stop_api.get_equipment_types(),
	})
	for _, equipment in pairs(equipment_by_type) do
		if (not ignored_entity_set) or (not ignored_entity_set[equipment.unit_number]) then
			raise_train_stop_equipment_found(equipment, stop_state, false)
		end
	end

	local equipment_by_name = stop_entity.surface.find_entities_filtered({
		area = bbox,
		name = stop_api.get_equipment_names(),
	})
	for _, equipment in pairs(equipment_by_name) do
		if (not ignored_entity_set) or (not ignored_entity_set[equipment.unit_number]) then
			raise_train_stop_equipment_found(equipment, stop_state, false)
		end
	end
end

on_train_stop_equipment_found(function(equipment, stop_state, is_being_destroyed)
	local rail_bbox = stop_state.layout.rail_bbox
	local stop_bbox = stop_state.layout.bbox
	local register_flag = true
	if is_being_destroyed then register_flag = false end
	if (not rail_bbox) or (not stop_bbox) then return end
	if equipment.type == "inserter" then
		if flib_bbox.contains_position(rail_bbox, equipment.pickup_position) then
			stop_api.register_loading_equipment(stop_state.id, equipment, equipment.pickup_position, register_flag, false)
		elseif flib_bbox.contains_position(rail_bbox, equipment.drop_position) then
			stop_api.register_loading_equipment(stop_state.id, equipment, equipment.drop_position, register_flag, false)
		else
			stop_api.register_loading_equipment(stop_state.id, equipment, equipment.position, false, false)
		end
	elseif equipment.type == "pump" then
		if equipment.pump_rail_target then
			local rail = equipment.pump_rail_target
			if rail and flib_bbox.contains_position(rail_bbox, rail.position) then
				stop_api.register_loading_equipment(stop_state.id, equipment, equipment.position, false, register_flag)
				return
			end
		end
		-- Fallthrough: remove pump from stop equipment manifest
		stop_api.register_loading_equipment(stop_state.id, equipment, equipment.position, false, false)
	elseif equipment.type == "loader-1x1" then
		if flib_bbox.contains_position(stop_bbox, equipment.position) then
			stop_api.register_loading_equipment(stop_state.id, equipment, equipment.position, register_flag, false)
		else
			stop_api.register_loading_equipment(stop_state.id, equipment, equipment.position, false, false)
		end
	elseif equipment.type == "loader" then
		-- TODO: support 2x1 loaders.
	end
end)

local rail_types = { "straight-rail", "curved-rail-a", "curved-rail-b" }

-- When a piece of equipment is built, use `find_stop_from_rail` to determine if it impacts a stop.
on_equipment_built(function(equipment, is_being_destroyed)
	local surface = equipment.surface
	-- Determine stop state from equipment position.
	if equipment.type == "inserter" then
		local rails = surface.find_entities_filtered({
			type = rail_types,
			position = equipment.pickup_position,
		})
		if rails[1] then
			local stop = stop_api.find_stop_from_rail(rails[1])
			if stop then
				raise_train_stop_equipment_found(equipment, stop, is_being_destroyed)
			end
		end

		rails = surface.find_entities_filtered({
			type = rail_types,
			position = equipment.drop_position,
		})
		if rails[1] then
			local stop = stop_api.find_stop_from_rail(rails[1])
			if stop then
				raise_train_stop_equipment_found(equipment, stop, is_being_destroyed)
			end
		end
	elseif equipment.type == "pump" then
		if equipment.pump_rail_target then
			local stop = stop_api.find_stop_from_rail(equipment.pump_rail_target)
			if stop then
				raise_train_stop_equipment_found(equipment, stop, is_being_destroyed)
			end
		end
	elseif equipment.type == "loader-1x1" then
		local position = equipment.position
		local direction = equipment.direction
		local area = flib_bbox.ensure_explicit(flib_bbox.from_position(position))
		if direction == defines.direction.east or direction == defines.direction.west then
			area.left_top.x = area.left_top.x - 1
			area.right_bottom.x = area.right_bottom.x + 1
		else
			area.left_top.y = area.left_top.y - 1
			area.right_bottom.y = area.right_bottom.y + 1
		end
		local rails = surface.find_entities_filtered({
			type = rail_types,
			area = area,
		})
		if rails[1] then
			local stop = stop_api.find_stop_from_rail(rails[1])
			if stop then
				raise_train_stop_equipment_found(equipment, stop, is_being_destroyed)
			end
		end
	elseif equipment.type == "loader" then
		-- TODO: support 2x1 loaders
	end
end)

--- Update related stop's loading equipment when an inserter is rotated.
---@param entity LuaEntity A *valid* inserter entity.
function internal_inserter_rotated(entity)
	-- Find every stop the inserter could possibly interact with and invoke
	-- registration for each of them, which should correctly detect whether
	-- the inserter belongs there or not.
	local area = flib_bbox.from_dimensions(entity.position, LONGEST_INSERTER_REACH, LONGEST_INSERTER_REACH)
	local rails = entity.surface.find_entities_filtered({
		type = rail_types,
		area = area,
	})
	if #rails == 0 then return end
	local stop_set = transform_table(rails,
		function(_, rail)
			return stop_api.find_stop_from_rail(rail), true
		end
	) --[[@as table<Cybersyn.TrainStop, boolean>]]
	for stop in pairs(stop_set) do
		raise_train_stop_equipment_found(entity, stop, false)
	end
end
