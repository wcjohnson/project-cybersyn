-- Lifecycle management for train stops.
-- Train stop state is only created/destroyed in this module.

---Create a stored train-stop state.
---@param stop_entity LuaEntity A *valid* reference to a train stop.
---@return Cybersyn.TrainStop #The new stop state.
function stop_api.create_stop_state(stop_entity)
	local map_data = (storage --[[@as MapData]])
	local id = stop_entity.unit_number
	if not id then
		-- Should be impossible.
		error("Train-stop entity has no unit number.")
	end
	if map_data.train_stops[id] then
		error("Train-stop state already exists.")
	end
	map_data.train_stops[id] = {
		id = id,
		entity = stop_entity,
		combinator_set = {},
		layout = {
			accepted_layouts = {},
		},
	} --[[@as Cybersyn.TrainStop]]

	return map_data.train_stops[id]
end

---Destroy a stored train-stop state.
---@param stop_id UnitNumber
---@return boolean `true` if the state was removed, `false` if it was not found.
function stop_api.destroy_stop_state(stop_id)
	local map_data = (storage --[[@as MapData]])
	if map_data.train_stops[stop_id] then
		map_data.train_stops[stop_id] = nil
		return true
	end
	return false
end

---Full teardown of a train-stop, dissociating combinators and firing events.
---@param stop_id UnitNumber
function stop_api.destroy_stop(stop_id)
	local stop = stop_api.get_stop_state(stop_id, true)
	if not stop then return end

	stop.is_being_destroyed = true

	-- Disassociate all associated combinators
	local associated_combs = map_table(stop.combinator_set, function(_, comb_id)
		return combinator_api.get_combinator_state(comb_id)
	end)
	for _, comb in ipairs(associated_combs) do
		comb.stop_id = nil
		stop.combinator_set[comb.id] = nil
		raise_combinator_disassociated(comb, stop)
	end
	if #associated_combs > 0 then
		raise_train_stop_combinator_set_changed(stop)
	end

	-- Remove the stop itself.
	raise_train_stop_destroyed(stop)
	stop_api.destroy_stop_state(stop_id)
end

---Create a new train-stop state if an unassociated combinator can be found
---near the stop. Associates all nearby unassociated combinators to the
---newly created stop state.
---@param stop_entity LuaEntity A *valid* reference to a train stop.
function stop_api.create_stop_if_nearby_combinator(stop_entity)
	local stop_id = stop_entity.unit_number --[[@as uint]]
	local stop = stop_api.get_stop_state(stop_id, true)
	if stop then
		-- Should be impossible
		return
	end

	-- Locate unassociated combinators nearby; if no unassociated combinators are
	-- found, no stop is created.
	local combs = stop_api.find_associable_combinators(stop_entity)
	if #combs == 0 then return end
	local unassociated_combs = map(combs, function(comb)
		local comb_id = comb.unit_number --[[@as uint]]
		local comb_state = combinator_api.get_combinator_state(comb_id)
		if comb_state and (not comb_state.stop_id) then
			return comb_state
		end
	end)
	if #unassociated_combs == 0 then return end

	-- Create stop state and associate all nearby unassociated combinators.
	stop = stop_api.create_stop_state(stop_entity)
	for _, comb_state in ipairs(unassociated_combs) do
		comb_state.stop_id = stop_id
		comb_state.distance = nil
		stop.combinator_set[comb_state.id] = true
	end

	-- Fire events
	stop.is_being_created = true
	raise_train_stop_created(stop)
	for _, comb_state in ipairs(unassociated_combs) do
		raise_combinator_associated(comb_state, stop)
	end
	raise_train_stop_combinator_set_changed(stop)
	stop.is_being_created = nil
	raise_train_stop_post_created(stop)
end

on_train_stop_post_created(function(stop)
	-- Perform initial scan of stop layout
	stop_api.compute_layout(stop)
end)
