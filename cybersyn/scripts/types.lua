-- Definitions of globally-utilized types and enumerations exposed at the
-- root level. Types used in events and global state should be defined here.
-- Types specific to particular APIs should be defined alongside those APIs.

---@alias UnitNumber uint A Factorio `unit_number` associated uniquely with a particular `LuaEntity`.

---@alias UnitNumberSet {[UnitNumber]: true} A collection of Factorio entities referenced by their `unit_number`.

---@alias PlayerIndex uint A Factorio `player_index` associated uniquely with a particular `LuaPlayer`.

---@class Cybersyn.Combinator.Ephemeral An opaque reference to EITHER a live combinator OR its ghost.
---@field public entity? LuaEntity The primary entity of the combinator OR its ghost.

---@class Cybersyn.Combinator: Cybersyn.Combinator.Ephemeral An opaque reference to a fully realized and built combinator that has been indexed by Cybersyn and tracked in game state.
---@field public id UnitNumber The immutable unit number of the combinator entity.
---@field public stop_id? UnitNumber The unit number of the train stop this combinator is associated with, if any.
---@field public output? LuaEntity The hidden output entity used to write the combinator's output, if it exists.
---@field public distance? uint If this field exists, it indicates the combinator is distant from its associated train stop along the nearby rail by this many tiles. Used for e.g. wagon control combs.
---@field public is_being_destroyed true? `true` if the combinator is being removed from state at this time.

---@class Cybersyn.Combinator.Settings: Cybersyn.Combinator.Ephemeral Transient object allowing manipulation of the settings of a Cybersyn combinator OR its ghost. Not to be held long-term or stored.
---@field public map_data MapData Reference to global storage, in the event we implement settings that need this.
---@field public control_behavior LuaArithmeticCombinatorControlBehavior?
---@field public parameters ArithmeticCombinatorParameters?

---@class Cybersyn.Combinator.PlayerUiState Per-player state of open Cybersyn combinator UIs.
---@field public open_combinator? Cybersyn.Combinator.Ephemeral The combinator OR ghost currently open in the player's UI, if any.

---@class Cybersyn.TrainStop An opaque reference to a train stop entity that is managed by Cybersyn.
---@field public entity LuaEntity The train stop entity.
---@field public id UnitNumber The unit number of the train stop entity.
---@field public combinator_set UnitNumberSet The set of combinators associated with this train stop, by unit number.
---@field public is_being_destroyed true? `true` if the associated train stop is being removed from state at this time.
---@field public is_being_created true? `true` if the associated train stop is being added to state at this time.
---@field public layout Cybersyn.TrainStop.Layout Information about the equipment that makes up the train stop.

---@class Cybersyn.TrainStop.Layout Information about the equipment that makes up the train stop.
---@field public cargo_loader_map {[UnitNumber]: uint} Map of equipment that can load cargo to tile indices relative to the train stop.
---@field public fluid_loader_map {[UnitNumber]: uint} Map of equipment that can load fluid to tile indices relative to the train stop.
---@field public loading_equipment_pattern (0|1|2|3)[] Auto-allowlist car pattern, inferred from equipment. 0 = no equipment, 1 = cargo, 2 = fluid, 3 = both.
---@field public accepted_layouts {[uint]: true?} Set of accepted train layouts.
---@field public bbox BoundingBox? The bounding box used when scanning for equipment.
---@field public rail_bbox BoundingBox? The bounding box for only the rails.
---@field public rail_set UnitNumberSet The set of rails associated to this stop.
---@field public direction defines.direction? The direction from the train stop towards the equipment, if known.
