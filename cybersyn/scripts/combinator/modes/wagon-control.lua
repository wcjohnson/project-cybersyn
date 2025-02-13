-- flib_gui typing causes a lot of extraneous missing fields errors
---@diagnostic disable: missing-fields

local flib_gui = require("__flib__.gui")

combinator_api.register_combinator_mode({
	name = "wagon_control",
	localized_string = "cybersyn-gui.wagon-control",
	create_gui = function(parent)
		flib_gui.add(parent, {
			{
				type = "label",
				style = "heading_2_label",
				caption = { "cybersyn-gui.settings" },
				style_mods = { top_padding = 8 },
			},
			{
				type = "checkbox",
				name = "enable_slot_barring",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "enable_slot_barring" },
				tooltip = { "cybersyn-gui.enable-slot-barring-tooltip" },
				caption = { "cybersyn-gui.enable-slot-barring-description" },
			},
		})
	end,
	update_gui = function(parent, settings, changed_setting)
		parent["enable_slot_barring"].state = combinator_api.read_setting(settings,
			combinator_api.settings.enable_slot_barring)
	end,
})
