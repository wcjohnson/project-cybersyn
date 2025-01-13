-- Base types and library code for manipulating Cybersyn combinators.

local flib_position = require("__flib__.position")
local distance_squared = flib_position.distance_squared
local INF = math.huge

if not combinator_api then combinator_api = {} end

-- TODO: make this customizable. (how?)
-- Set of entity names that should be considered combinators.
local combinator_names_set = {
	[COMBINATOR_NAME] = true,
}

-- List of entity names that should be considered combinators.
local combinator_names = map_table(combinator_names_set, function(v, k) return k end)

---Get a list of all entity names corresponding to combinators.
function combinator_api.get_combinator_names()
	return combinator_names
end

---Check if a string is the name of a combinator entity.
---@param name string?
function combinator_api.is_combinator_name(name)
	return combinator_names_set[name or ""] or false
end

---@param combinator Cybersyn.Combinator.Ephemeral?
---@return boolean?
local function is_valid(combinator)
	return combinator and combinator.entity and combinator.entity.valid
end
combinator_api.is_valid = is_valid

---Check if a combinator is a ghost.
---@param combinator Cybersyn.Combinator.Ephemeral?
---@return boolean is_ghost `true` if combinator is a ghost
---@return boolean is_valid `true` if combinator is valid, ghost or no
function combinator_api.is_ghost(combinator)
	if (not combinator) or (not combinator.entity) or (not combinator.entity.valid) then return false, false end
	if combinator.entity.name == "entity-ghost" then return true, true else return false, true end
end

---Retrieve a real combinator from storage by its `unit_number`.
---@param combinator_id UnitNumber?
---@param skip_validation? boolean If `true`, blindly returns the storage object without validating actual existence.
---@return Cybersyn.Combinator?
function combinator_api.get_combinator_state(combinator_id, skip_validation)
	if not combinator_id then return nil end
	local combinator = (storage --[[@as MapData]]).combinators[combinator_id]
	if skip_validation then
		return combinator
	else
		return is_valid(combinator) and combinator or nil
	end
end

---Get the `unit_number` of the train stop associated with this combinator, if any.
---@param combinator Cybersyn.Combinator
---@return UnitNumber?
function combinator_api.get_associated_train_stop_id(combinator)
	return combinator.stop_id
end

---Attempt to convert an ephemeral combinator reference to a realized combinator reference.
---@param ephemeral Cybersyn.Combinator.Ephemeral
---@return Cybersyn.Combinator?
function combinator_api.realize(ephemeral)
	if ephemeral and ephemeral.entity and ephemeral.entity.valid then
		local combinator = (storage --[[@as MapData]]).combinators[ephemeral.entity.unit_number]
		if combinator == ephemeral or is_valid(combinator) then return combinator end
	end
	return nil
end

---Convert a Factorio entity to an ephemeral combinator reference. Must be
---a *valid* combinator or a ghost.
---@param entity LuaEntity
---@return Cybersyn.Combinator.Ephemeral
function combinator_api.to_ephemeral_reference(entity)
	return {
		entity = entity,
	}
end

---Locate all `LuaEntity`s corresponding to combinators within the given area.
---@param surface LuaSurface
---@param area BoundingBox?
---@param position MapPosition?
---@param radius number?
---@return LuaEntity[]
function combinator_api.find_combinator_entities(surface, area, position, radius)
	return surface.find_entities_filtered({
		area = area,
		position = position,
		radius = radius,
		name = combinator_api.get_combinator_names(),
	})
end

---Locate all `LuaEntity`s corresponding to combinator ghosts within the given area.
---@param surface LuaSurface
---@param area BoundingBox?
---@param position MapPosition?
---@param radius number?
---@return LuaEntity[]
function combinator_api.find_combinator_entity_ghosts(surface, area, position, radius)
	return surface.find_entities_filtered({
		area = area,
		position = position,
		radius = radius,
		ghost_name = combinator_api.get_combinator_names(),
	})
end

---Given a combinator, find the nearby `LuaEntity` that will determine its
---association.
---@param comb LuaEntity A *valid* combinator entity.
---@return LuaEntity? stop_entity The closest-to-front train stop within the combinator's association zone.
---@return LuaEntity? rail_entity The closest-to-front straight rail with a train stop within the combinator's association zone.
function combinator_api.find_associable_entity(comb)
	local pos_x, pos_y = pos_get(comb.position)
	-- We need to account for the direction the combinator is facing. If
	-- the combinator would associate ambiguously with multiple stops or rails,
	-- we prefer the one that is closer to the front of the combinator.
	local front = pos_move(comb.position, comb.direction, 1)
	local search_area
	if comb.direction == defines.direction.north or comb.direction == defines.direction.south then
		search_area = {
			{ pos_x - 1.5, pos_y - 2 },
			{ pos_x + 1.5, pos_y + 2 },
		}
	else
		search_area = {
			{ pos_x - 2, pos_y - 1.5 },
			{ pos_x + 2, pos_y + 1.5 },
		}
	end
	local stop = nil
	local rail = nil
	local stop_dist = INF
	local rail_dist = INF
	local entities = comb.surface.find_entities_filtered({ area = search_area, name = { "train-stop", "straight-rail" } })
	for _, cur_entity in pairs(entities) do
		if cur_entity.name == "train-stop" then
			local dist = distance_squared(front, cur_entity.position)
			if dist < stop_dist then
				stop_dist = dist
				stop = cur_entity
			end
		elseif cur_entity.type == "straight-rail" then
			-- Prefer rails with stops, then prefer rails nearer the
			-- front of the combinator.
			if stop_api.find_stop_from_rail(cur_entity) then
				local dist = distance_squared(front, cur_entity.position)
				if dist < rail_dist then
					rail_dist = dist
					rail = cur_entity
				end
			end
		end
	end
	return stop, rail
end
