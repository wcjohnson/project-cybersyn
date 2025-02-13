-- flib_gui typing causes a lot of extraneous missing fields errors
---@diagnostic disable: missing-fields

local flib_gui = require("__flib__.gui")

combinator_api.register_combinator_mode({
	name = "station_control",
	localized_string = "cybersyn-gui.comb2",
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
				name = "enable_train_count",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "enable_train_count" },
				tooltip = { "cybersyn-gui.enable-train-count-tooltip" },
				caption = { "cybersyn-gui.enable-train-count-description" },
			},
			{
				type = "checkbox",
				name = "enable_manual_inventory",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "enable_manual_inventory" },
				tooltip = { "cybersyn-gui.enable-manual-inventory-tooltip" },
				caption = { "cybersyn-gui.enable-manual-inventory-description" },
			},
		})
	end,
	update_gui = function(parent, settings, changed_setting)
		parent["enable_train_count"].state = combinator_api.read_setting(settings,
			combinator_api.settings.enable_train_count)
		parent["enable_manual_inventory"].state = combinator_api.read_setting(settings,
			combinator_api.settings.enable_manual_inventory)
	end,
})
