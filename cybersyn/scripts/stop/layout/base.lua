-- Basic stop layout detection and event handling.

if _G._require_guard_stop_layout_base then
	return
else
	_G._require_guard_stop_layout_base = true
end

local flib_bbox = require("__flib__.bounding-box")
local flib_table = require("__flib__.table")
local flib_direction = require("__flib__.direction")
local rail_search = require("scripts.stop.search")
local bbox_contain = bbox_contain
local bbox_extend = bbox_extend

local get_stop_state = stop_api.get_stop_state
local get_connected_stop = stop_api.get_connected_stop
local get_all_connected_rails = stop_api.get_all_connected_rails
local find_stop_from_rail = stop_api.find_stop_from_rail

local defines_front = defines.rail_direction.front
local defines_back = defines.rail_direction.back
local defines_straight = defines.rail_connection_direction.straight

-- Maximum number of rail entities to search in iterative rail searches.
local MAX_RAILS_TO_SEARCH = 112 -- TODO: why 112?

---Clear a railset from the global rail cache.
---@param rail_set UnitNumberSet A set of rail unit numbers.
local function clear_rail_set_from_storage(rail_set)
	local map_data = (storage --[[@as MapData]])
	for rail_id in pairs(rail_set) do
		map_data.rail_to_stop[rail_id] = nil
	end
end

---Add a railset to the global rail cache mapped to the given stop id.
---@param rail_set UnitNumberSet A set of rail unit numbers.
---@param stop_id UnitNumber The ID of the stop to associate the rails with.
local function add_rail_set_to_storage(rail_set, stop_id)
	local map_data = (storage --[[@as MapData]])
	for rail_id in pairs(rail_set) do
		map_data.rail_to_stop[rail_id] = stop_id
	end
end

---Clear the layout of a train stop state.
---@param stop_state Cybersyn.TrainStop A *valid* train stop state.
local function clear_layout(stop_state)
	clear_rail_set_from_storage(stop_state.layout.rail_set)
	stop_state.layout.rail_set = {}
	stop_state.layout.cargo_loader_map = {}
	stop_state.layout.fluid_loader_map = {}
	stop_state.layout.loading_equipment_pattern = {}
	stop_state.layout.accepted_layouts = {}
	raise_train_stop_accepted_layouts_changed(stop_state)

	-- Reassociate all combinators.
	local combs = map_table(stop_state.combinator_set, function(_, comb_id)
		local comb = combinator_api.get_combinator_state(comb_id)
		if comb then return comb end
	end)
	stop_api.reassociate_combinators(combs)
end

---@class Cybersyn.Internal.StopBboxSearchState: Cybersyn.Internal.IterativeRailSearchState
---@field public bbox BoundingBox The bounding box being computed.
---@field public rail_set UnitNumberSet The set of rails used to generate the bbox.
---@field public layout_stop LuaEntity The stop entity that the layout is being computed for.
---@field public ignore_set UnitNumberSet? Set of rail entities to ignore when scanning.

---Iterative check function to find bbox of a station.
---@param state Cybersyn.Internal.StopBboxSearchState
local function search_for_station_end(state)
	local current_rail = state.rail --[[@as LuaEntity]]
	if current_rail.type ~= "straight-rail" then return false end
	if state.ignore_set and state.ignore_set[current_rail.unit_number] then return false end

	-- TODO: Check for splits in the track here by also evaluating `rail_connection_direction.left/right`. This would be a breaking change as current allowlists scan past splits.

	-- If we reach a stop that isn't our target stop, abort.
	if current_rail == state.front_rail and state.front_stop ~= state.layout_stop then
		return false
	elseif current_rail == state.back_rail and state.back_stop ~= state.layout_stop then
		return false
	end

	-- Extend the bounding box to include the current rail.
	bbox_contain(state.bbox, current_rail.bounding_box)
	state.rail_set[current_rail.unit_number] = true
	return true
end

---Recompute the layout of a train stop.
---@param stop_state Cybersyn.TrainStop A train stop state. Will be validated by this method.
---@param ignored_entity_set? UnitNumberSet A set of entities to ignore when scanning for equipment. Used for e.g. equipment that is in the process of being destroyed.
function stop_api.compute_layout(stop_state, ignored_entity_set)
	if (not stop_state) or stop_state.is_being_destroyed or (not stop_api.is_valid(stop_state)) then return end
	local stop_id = stop_state.id
	local stop_entity = stop_state.entity

	local stop_rail = stop_entity.connected_rail
	if stop_rail == nil then
		-- Disconnected station; clear whole layout.
		clear_layout(stop_state)
		return
	end

	local rail_direction_from_stop
	if stop_entity.connected_rail_direction == defines_front then
		rail_direction_from_stop = defines_back
	else
		rail_direction_from_stop = defines_front
	end
	local stop_direction = stop_entity.direction
	local direction_from_stop = flib_direction.opposite(stop_direction)
	local is_vertical = (stop_direction == defines.direction.north or stop_direction == defines.direction.south)

	-- Iteratively search for the collection of rails that defines the automatic
	-- bounding box of the station.
	---@type Cybersyn.Internal.StopBboxSearchState
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
		ignore_set = ignored_entity_set,
	}
	rail_search.search(state, MAX_RAILS_TO_SEARCH)
	local bbox = state.bbox
	local rail_set = state.rail_set

	-- If the search ended on a curve, add 3 tiles of grace, and add the curve
	-- to the rail set.
	if state.no_connected_rail and state.rail then
		local curve_left = state.rail.get_connected_rail({
			rail_direction = rail_direction_from_stop,
			rail_connection_direction = defines.rail_connection_direction.left,
		})
		local curve_right = state.rail.get_connected_rail({
			rail_direction = rail_direction_from_stop,
			rail_connection_direction = defines.rail_connection_direction.right,
		})
		if curve_left and (curve_left.type ~= "curved-rail-a" and curve_left.type ~= "curved-rail-b") then curve_left = nil end
		if curve_right and (curve_right.type ~= "curved-rail-a" and curve_right.type ~= "curved-rail-b") then curve_right = nil end
		if curve_left and ignored_entity_set and ignored_entity_set[curve_left.unit_number] then curve_left = nil end
		if curve_right and ignored_entity_set and ignored_entity_set[curve_right.unit_number] then
			curve_right = nil
		end

		if curve_left or curve_right then
			bbox_extend(bbox, direction_from_stop, 3)
			if curve_left then rail_set[curve_left.unit_number] = true end
			if curve_right then rail_set[curve_right.unit_number] = true end
		end
	end

	-- Update the rail set caches.
	stop_state.layout.rail_bbox = flib_bbox.ceil(bbox)
	clear_rail_set_from_storage(stop_state.layout.rail_set)
	stop_state.layout.rail_set = rail_set
	add_rail_set_to_storage(rail_set, stop_id)

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
	stop_state.layout.bbox = bbox
	stop_state.layout.direction = direction_from_stop

	-- Reassociate combinators. Combinators in the bbox as well as combinators
	-- that were associated but may be outside the new bbox must all be checked.
	local comb_entities = combinator_api.find_combinator_entities(stop_state.entity.surface, bbox)
	local comb_set = transform_table(comb_entities, function(_, entity)
		if (not ignored_entity_set) or (not ignored_entity_set[entity.unit_number]) then
			return entity.unit_number, true
		else
			return nil, nil
		end
	end)
	for comb_id in pairs(stop_state.combinator_set) do comb_set[comb_id] = true end
	local reassociable_combs = map_table(comb_set, function(_, comb_id)
		local comb = combinator_api.get_combinator_state(comb_id)
		if comb then return comb end
	end)
	stop_api.reassociate_combinators(reassociable_combs)

	-- Since `reassociate_combinators` can cause significant state
	-- changes, check for safety, although this shouldn't ever happen.
	if stop_state.is_being_destroyed or (not stop_api.is_valid(stop_state)) then return end

	-- Scan for loading equipment.
	raise_train_stop_layout_pre_scan(stop_state)
	internal_scan_equipment(stop_state, ignored_entity_set)
	raise_train_stop_layout_post_scan(stop_state)
end

---Reassociate a combinator after it is rotated.
---@param entity LuaEntity A *valid* combinator entity.
function internal_combinator_rotated(entity)
	local combinator = combinator_api.get_combinator_state(entity.unit_number)
	if combinator then
		stop_api.reassociate_combinators({ combinator })
	end
end

-- When a stop is built, perform an initial layout scan.
on_train_stop_post_created(function(stop)
	stop_api.compute_layout(stop)
end)

-- When rails are built, we need to re-evaluate layouts of affected stops.
-- We must be efficient and rely heavily on the rail cache, as building rails
-- is common/spammy.
---@param rail LuaEntity
function internal_rail_built(rail)
	-- If this is the connected-rail of a stop, we must update that stop's
	-- layout first to populate the rail cache.
	local connected_stop = get_connected_stop(rail)
	local stop_id0
	if connected_stop then
		local connected_stop_state = get_stop_state(connected_stop.unit_number, true)
		if connected_stop_state then
			stop_id0 = connected_stop_state.id
			stop_api.compute_layout(connected_stop_state)
		end
	end

	-- Update any stop layout whose rail cache contains an adjacent rail.
	local rail1, rail2, rail3, rail4, rail5, rail6 = get_all_connected_rails(rail)
	local stop_id1, stop_id2, stop_id3, stop_id4, stop_id5

	-- This loop is hand-unrolled for performance reasons.
	-- We want to avoid creating Lua garbage here as this is called per rail.
	-- Also avoid any duplicate calls to `compute_layout`.
	if rail1 then
		local stop = find_stop_from_rail(rail1)
		local stop_id = stop and stop.id
		if stop and stop_id ~= stop_id0 then
			stop_id1 = stop_id
			stop_api.compute_layout(stop)
		end
	end
	if rail2 then
		local stop = find_stop_from_rail(rail2)
		local stop_id = stop and stop.id
		if stop and stop_id ~= stop_id0 and stop_id ~= stop_id1 then
			stop_id2 = stop_id
			stop_api.compute_layout(stop)
		end
	end
	if rail3 then
		local stop = find_stop_from_rail(rail3)
		local stop_id = stop and stop.id
		if stop and stop_id ~= stop_id0 and stop_id ~= stop_id1 and stop_id ~= stop_id2 then
			stop_id3 = stop_id
			stop_api.compute_layout(stop)
		end
	end
	if rail4 then
		local stop = find_stop_from_rail(rail4)
		local stop_id = stop and stop.id
		if stop and stop_id ~= stop_id0 and stop_id ~= stop_id1 and stop_id ~= stop_id2 and stop_id ~= stop_id3 then
			stop_id4 = stop_id
			stop_api.compute_layout(stop)
		end
	end
	if rail5 then
		local stop = find_stop_from_rail(rail5)
		local stop_id = stop and stop.id
		if stop and stop_id ~= stop_id0 and stop_id ~= stop_id1 and stop_id ~= stop_id2 and stop_id ~= stop_id3 and stop_id ~= stop_id4 then
			stop_id5 = stop_id
			stop_api.compute_layout(stop)
		end
	end
	if rail6 then
		local stop = find_stop_from_rail(rail6)
		local stop_id = stop and stop.id
		if stop and stop_id ~= stop_id0 and stop_id ~= stop_id1 and stop_id ~= stop_id2 and stop_id ~= stop_id3 and stop_id ~= stop_id4 and stop_id ~= stop_id5 then
			stop_api.compute_layout(stop)
		end
	end
end

-- When a rail is being destroyed, we need to re-evaluate layouts of affected stops.
---@param rail LuaEntity
function internal_rail_broken(rail)
	-- TODO: it is possible that breaking a rail would remove a split in the tracks,
	-- causing a stop that was not associated with that rail to be enlarged. That case requires a more complex
	-- algorithm and isn't handled right now.
	local stop = find_stop_from_rail(rail)
	if stop then
		stop_api.compute_layout(stop, { [rail.unit_number] = true })
	end
end
