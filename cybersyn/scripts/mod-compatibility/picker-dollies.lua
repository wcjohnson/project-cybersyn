local picker_dollies_compat = {}

-- TODO: there is a new picker dollies fork under a new name i think?
function picker_dollies_compat.setup_picker_dollies_compat()
	IS_PICKER_DOLLIES_PRESENT = remote.interfaces["PickerDollies"] and
			remote.interfaces["PickerDollies"]["add_blacklist_name"]
	if IS_PICKER_DOLLIES_PRESENT then
		remote.call("PickerDollies", "add_blacklist_name", COMBINATOR_NAME)
		remote.call("PickerDollies", "add_blacklist_name", COMBINATOR_OUT_NAME)
	end
end

return picker_dollies_compat
