-- Base types and library code for manipulating train stops with Cybersyn state.

if not stop_api then stop_api = {} end

local defines_front = defines.rail_direction.front
local defines_back = defines.rail_direction.back

local connected_rail_fs = {
	rail_direction = defines_front,
	rail_connection_direction = defines.rail_connection_direction.straight,
}
local connected_rail_fl = {
	rail_direction = defines_front,
	rail_connection_direction = defines.rail_connection_direction.left,
}
local connected_rail_fr = {
	rail_direction = defines_front,
	rail_connection_direction = defines.rail_connection_direction.right,
}
local connected_rail_bs = {
	rail_direction = defines_back,
	rail_connection_direction = defines.rail_connection_direction.straight,
}
local connected_rail_bl = {
	rail_direction = defines_back,
	rail_connection_direction = defines.rail_connection_direction.left,
}
local connected_rail_br = {
	rail_direction = defines_back,
	rail_connection_direction = defines.rail_connection_direction.right,
}

---Opposite of Factorio's `stop.connected_rail`. Finds the stop that a specific
---rail entity is connected to.
---@param rail_entity LuaEntity A *valid* rail entity.
---@return LuaEntity? stop_entity The stop entity for which `connected_rail` is the given rail entity, if it exists.
function stop_api.get_connected_stop(rail_entity)
	---@type LuaEntity?
	local stop_entity = rail_entity.get_rail_segment_stop(defines_front)
	if not stop_entity then
		stop_entity = rail_entity.get_rail_segment_stop(defines_back)
	end
	if stop_entity then
		local connected_rail = stop_entity.connected_rail
		if connected_rail and (connected_rail.unit_number == rail_entity.unit_number) then
			return stop_entity
		end
	end
end

---Retrieve all rail entities connected to the given rail entity.
---@param rail_entity LuaEntity A *valid* rail entity.
---@return LuaEntity? rail_fs The rail entity connected to the given rail entity in the front-straight direction, if it exists.
---@return LuaEntity? rail_fl The rail entity connected to the given rail entity in the front-left direction, if it exists.
---@return LuaEntity? rail_fr The rail entity connected to the given rail entity in the front-right direction, if it exists.
---@return LuaEntity? rail_bs The rail entity connected to the given rail entity in the back-straight direction, if it exists.
---@return LuaEntity? rail_bl The rail entity connected to the given rail entity in the back-left direction, if it exists.
---@return LuaEntity? rail_br The rail entity connected to the given rail entity in the back-right direction, if it exists.
function stop_api.get_all_connected_rails(rail_entity)
	local get_connected_rail = rail_entity.get_connected_rail
	return
			get_connected_rail(connected_rail_fs),
			get_connected_rail(connected_rail_fl),
			get_connected_rail(connected_rail_fr),
			get_connected_rail(connected_rail_bs),
			get_connected_rail(connected_rail_bl),
			get_connected_rail(connected_rail_br)
end

---Locate all `LuaEntity`s corresponding to train stops within the given area.
---@param surface LuaSurface
---@param area BoundingBox?
---@param position MapPosition?
---@param radius number?
---@return LuaEntity[]
function stop_api.find_stop_entities(surface, area, position, radius)
	return surface.find_entities_filtered({
		area = area,
		position = position,
		radius = radius,
		name = "train-stop",
	})
end

---Locate all combinators that could potentially be associated to this stop.
---@param stop_entity LuaEntity A *valid* train stop entity.
---@return LuaEntity[]
function stop_api.find_associable_combinators(stop_entity)
	local pos_x = stop_entity.position.x
	local pos_y = stop_entity.position.y
	return combinator_api.find_combinator_entities(stop_entity.surface, {
		{ pos_x - 2, pos_y - 2 },
		{ pos_x + 2, pos_y + 2 },
	})
end

---@param stop Cybersyn.TrainStop?
---@return boolean?
local function is_valid(stop)
	return stop and stop.entity and stop.entity.valid
end
stop_api.is_valid = is_valid

---Retrieve a train-stop state from storage by its `unit_number`.
---@param stop_id UnitNumber?
---@param skip_validation? boolean If `true`, blindly returns the storage object without validating the entity's actual existence.
---@return Cybersyn.TrainStop?
function stop_api.get_stop_state(stop_id, skip_validation)
	if not stop_id then return nil end
	local stop = (storage --[[@as MapData]]).train_stops[stop_id]
	if skip_validation then
		return stop
	else
		return is_valid(stop) and stop or nil
	end
end
