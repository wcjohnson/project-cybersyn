local flib_gui = require("__flib__.gui")

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

---@param sprite string
---@param caption LocalisedString
local function create_status_entry(sprite, caption)
	return {
		type = "flow",
		direction = "horizontal",
		style_mods = {
			horizontal_spacing = 8,
			vertical_align = "center",
			horizontally_stretchable = true,
		},
		children = {
			{
				type = "sprite",
				sprite = sprite,
				style = "status_image",
				style_mods = { stretch_image_to_widget_size = true },
			},
			{
				type = "label",
				caption = caption,
			},
		},
	}
end

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

	-- Update statuses
	local statuses = window.frame.vflow.statuses
	statuses.clear()
	flib_gui.add(statuses, {
		create_status_entry(
			is_ghost and STATUS_SPRITES_GHOST or STATUS_SPRITES[comb_entity.status] or
			STATUS_SPRITES_DEFAULT,
			{ is_ghost and STATUS_NAMES_GHOST or STATUS_NAMES[comb_entity.status] or STATUS_NAMES_DEFAULT }
		),
		create_status_entry(YELLOW, "No providers on the same network match any of this station's requests."),
	})
end
