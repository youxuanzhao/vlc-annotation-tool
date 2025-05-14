-- VLC Lua Extension for Annotating Video with Timestamps, Descriptions, and Shot Types
--
-- Global variables
local FILE_EXTENSION = ".txt"
local main_dialog = nil -- Reference to the main annotation dialog
local timestamp_label = nil -- Reference to the label displaying the timestamp
local reopen_main_dialog = false -- Flag to reopen the main dialog after the warning popup

function descriptor()
	return {
		title = "VLC Annotation Tool",
		version = "1.0",
		author = "Youxuan Zhao",
		capabilities = { "input-listener" },
	}
end

function activate()
	vlc.msg.info("Annotation Tool Activated")
	create_annotation_popup() -- Open the annotation window when the extension is activated
end

function deactivate()
	vlc.msg.info("Annotation Tool Deactivated")
	if main_dialog then
		main_dialog:delete()
		main_dialog = nil
	end
end

function input_changed()
	vlc.msg.info("Input Changed")
end

-- Creates the annotation popup
function create_annotation_popup()
	if main_dialog then
		vlc.msg.info("Annotation window is already open")
		return -- Prevent multiple popups
	end

	main_dialog = vlc.dialog("Annotate Video")

	-- Current Timestamp Box
	main_dialog:add_label("Current Timestamp:", 1, 1, 1)
	timestamp_label = main_dialog:add_label(get_current_timestamp(), 2, 1, 2)

	-- Input for Description
	main_dialog:add_label("Description:", 1, 2, 1)
	local description_input = main_dialog:add_text_input("", 2, 2, 3)

	-- Input for Shot Type
	main_dialog:add_label("Type of Shot:", 1, 3, 1)
	local type_input = main_dialog:add_text_input("", 2, 3, 3)

	-- Refresh Button
	main_dialog:add_button("Refresh Timestamp", function()
		refresh_timestamp()
	end, 1, 4, 1)

	-- Save Button
	main_dialog:add_button("Save", function()
		local description = description_input:get_text()
		local shot_type = type_input:get_text()

		-- Do not save if description is empty
		if description == "" or description == nil then
			vlc.msg.warn("Description is required. Annotation not saved.")
			return
		end

		-- Set shot type to "N/A" if it's empty
		if shot_type == "" or shot_type == nil then
			shot_type = "N/A"
		end

		save_annotation(timestamp_label:get_text(), description, shot_type)
	end, 3, 4, 1)

	-- Cancel Button
	main_dialog:add_button("Cancel", function()
		main_dialog:delete()
		main_dialog = nil
	end, 4, 4, 1)
end

-- Refreshes the timestamp label to the current timestamp
function refresh_timestamp()
	if timestamp_label then
		timestamp_label:set_text(get_current_timestamp())
		vlc.msg.info("Timestamp refreshed to: " .. get_current_timestamp())
	end
end

-- Gets the current timestamp in the video and formats it as HH:MM:SS
function get_current_timestamp()
	local input = vlc.object.input()
	if input then
		local time_in_seconds = vlc.var.get(input, "time") / 1e6 -- Time in seconds (orignially in microseconds)
		if time_in_seconds then
			local hours = math.floor(time_in_seconds / 3600)
			local minutes = math.floor((time_in_seconds % 3600) / 60)
			local seconds = math.floor(time_in_seconds % 60)
			return string.format("%02d:%02d:%02d", hours, minutes, seconds)
		end
	end
	return "00:00:00" -- Default value if no input is playing or time is unavailable
end

-- Saves the annotation to a .txt file and handles overwriting of existing annotations
function save_annotation(timestamp, description, shot_type)
	local input = vlc.object.input()
	if not input then
		return
	end

	-- Get the file path
	local uri = vlc.input.item():uri()
	local path = vlc.strings.decode_uri(uri):gsub("file://", "")
	local base_name = path:match("(.+)%..+$")
	local txt_file_path = base_name .. FILE_EXTENSION

	-- Read existing annotations
	local annotations = {}
	local existing_line = nil
	local file = io.open(txt_file_path, "r")
	if file then
		for line in file:lines() do
			local existing_timestamp = line:match("^(%d%d:%d%d:%d%d)")
			if existing_timestamp == timestamp then
				existing_line = line -- Save the existing annotation for comparison
			else
				table.insert(annotations, line) -- Keep other annotations
			end
		end
		file:close()
	end

	-- If an annotation with the same timestamp exists, show a warning popup
	if existing_line then
		-- Close the main dialog temporarily
		main_dialog:delete()
		main_dialog = nil
		reopen_main_dialog = true

		-- Show the warning popup
		create_warning_popup(
			existing_line,
			string.format("%s\t%s\t%s", timestamp, description, shot_type),
			txt_file_path,
			annotations,
			description,
			shot_type
		)
		return
	end

	-- Add the new annotation (no overwrite needed)
	table.insert(annotations, string.format("%s\t%s\t%s", timestamp, description, shot_type))
	write_annotations_to_file(txt_file_path, annotations)
end

-- Writes the annotations to the file after sorting them
function write_annotations_to_file(txt_file_path, annotations)
	-- Sort annotations by timestamp
	table.sort(annotations, function(a, b)
		local t1 = a:match("^(%d%d:%d%d:%d%d)")
		local t2 = b:match("^(%d%d:%d%d:%d%d)")
		return t1 < t2
	end)

	-- Write sorted annotations back to the file
	local file = io.open(txt_file_path, "w")
	if file then
		for _, line in ipairs(annotations) do
			file:write(line .. "\n")
		end
		file:close()
		vlc.msg.info("Annotation saved and file sorted: " .. txt_file_path)
	else
		vlc.msg.err("Failed to open file for writing: " .. txt_file_path)
	end
end

-- Creates a warning popup for overwriting annotations
function create_warning_popup(existing_annotation, new_annotation, txt_file_path, annotations, description, shot_type)
	local warning_dialog = vlc.dialog("Warning: Overwriting Annotation")
	warning_dialog:add_label("An annotation with the same timestamp already exists:", 1, 1, 2)
	warning_dialog:add_label(existing_annotation, 1, 2, 2)
	warning_dialog:add_label("New annotation:", 1, 3, 2)
	warning_dialog:add_label(new_annotation, 1, 4, 2)

	-- Proceed Button
	warning_dialog:add_button("Proceed", function()
		-- Overwrite the existing annotation
		table.insert(annotations, new_annotation)
		write_annotations_to_file(txt_file_path, annotations)
		warning_dialog:delete()

		-- Reopen the main annotation dialog
		if reopen_main_dialog then
			create_annotation_popup()
			reopen_main_dialog = false
		end
	end, 1, 5, 1)

	-- Cancel Button
	warning_dialog:add_button("Cancel", function()
		warning_dialog:delete()

		-- Reopen the main annotation dialog
		if reopen_main_dialog then
			create_annotation_popup()
			reopen_main_dialog = false
		end
	end, 4, 5, 1)

	-- Refresh and Proceed Button
	warning_dialog:add_button("Refresh and Proceed", function()
		-- Refresh the timestamp
		local refreshed_timestamp = get_current_timestamp()
		local refreshed_annotation = string.format("%s\t%s\t%s", refreshed_timestamp, description, shot_type)

		-- Overwrite the existing annotation with the refreshed timestamp
		table.insert(annotations, refreshed_annotation)
		write_annotations_to_file(txt_file_path, annotations)
		warning_dialog:delete()

		-- Reopen the main annotation dialog
		if reopen_main_dialog then
			create_annotation_popup()
			reopen_main_dialog = false
		end
	end, 2, 5, 1)
end
