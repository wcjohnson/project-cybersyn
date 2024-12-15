-- Base types and library code for manipulating train stops with Cybersyn state.
if not stop_api then stop_api = {} end

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

---Associate a single combinator with a train stop.
---@param stop Cybersyn.TrainStop A *valid* train stop state.
---@param combinator Cybersyn.Combinator A *valid* combinator state.
function stop_api.associate_combinator(stop, combinator)
	if combinator.stop_id or stop.is_being_destroyed then return false end
	local comb_id = combinator.id
	if stop.combinator_set[comb_id] then return false end
	stop.combinator_set[comb_id] = true
	combinator.stop_id = stop.id
	raise_combinator_associated(combinator, stop)
	raise_train_stop_combinator_set_changed(stop)
end

---Disassociate a single combinator from a train stop.
---@param stop Cybersyn.TrainStop A *valid* train stop state.
---@param combinator Cybersyn.Combinator A *valid* combinator state.
function stop_api.disassociate_combinator(stop, combinator)
	if not combinator.stop_id or stop.is_being_destroyed then return false end
	local comb_id = combinator.id
	if not stop.combinator_set[comb_id] then return false end
	stop.combinator_set[comb_id] = nil
	combinator.stop_id = nil
	raise_combinator_disassociated(combinator, stop)
	raise_train_stop_combinator_set_changed(stop)
	if not next(stop.combinator_set) then
		stop_api.destroy_stop(stop.id)
	end
end
