local RED = "utility/status_not_working"
local GREEN = "utility/status_working"
local YELLOW = "utility/status_yellow"

local STATUS_SPRITES = {}
STATUS_SPRITES[defines.entity_status.working] = GREEN
STATUS_SPRITES[defines.entity_status.normal] = GREEN
STATUS_SPRITES[defines.entity_status.no_power] = RED
STATUS_SPRITES[defines.entity_status.low_power] = YELLOW
STATUS_SPRITES[defines.entity_status.disabled_by_control_behavior] = RED
STATUS_SPRITES[defines.entity_status.disabled_by_script] = RED
STATUS_SPRITES[defines.entity_status.marked_for_deconstruction] = RED
local STATUS_SPRITES_DEFAULT = RED
local STATUS_SPRITES_GHOST = YELLOW

local STATUS_NAMES = {}
STATUS_NAMES[defines.entity_status.working] = "entity-status.working"
STATUS_NAMES[defines.entity_status.normal] = "entity-status.normal"
STATUS_NAMES[defines.entity_status.ghost] = "entity-status.ghost"
STATUS_NAMES[defines.entity_status.no_power] = "entity-status.no-power"
STATUS_NAMES[defines.entity_status.low_power] = "entity-status.low-power"
STATUS_NAMES[defines.entity_status.disabled_by_control_behavior] = "entity-status.disabled"
STATUS_NAMES[defines.entity_status.disabled_by_script] = "entity-status.disabled-by-script"
STATUS_NAMES[defines.entity_status.marked_for_deconstruction] = "entity-status.marked-for-deconstruction"
local STATUS_NAMES_DEFAULT = "entity-status.disabled"
local STATUS_NAMES_GHOST = "entity-status.ghost"

---Update thumbnail and status section of the combinator gui window.
---@param window LuaGuiElement Reference to the root window of the comb gui.
---@param combinator Cybersyn.Combinator.Ephemeral
function internal_update_combinator_gui_status_section(window, combinator)
	local is_ghost, is_valid = combinator_api.is_ghost(combinator)
	if not is_valid then return end
	local comb_entity = combinator.entity --[[@as LuaEntity]]

	-- Update entity preview
	local preview = window.frame.vflow.preview_frame.preview
	preview.entity = comb_entity

	-- Update status
	local status = window.frame.vflow.status
	status.status_sprite.sprite = is_ghost and STATUS_SPRITES_GHOST or STATUS_SPRITES[comb_entity.status] or
			STATUS_SPRITES_DEFAULT
	status.status_label.caption = {
		is_ghost and STATUS_NAMES_GHOST or STATUS_NAMES[comb_entity.status] or STATUS_NAMES_DEFAULT
	}
end
