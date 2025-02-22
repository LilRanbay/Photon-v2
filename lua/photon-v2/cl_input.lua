Photon2.ClientInput = Photon2.ClientInput or {
	Configurations = {},
	Active = { Binds = {} },
	KeysPressed = {},
	KeysHeld = {},
	---@type table<string, PhotonCommand>
	Commands = {},
	Listening = false,
	---@type PhotonController | boolean
	TargetController = false,
	KeyActivities = { "OnPress", "OnHold", "OnRelease" },
	ProfileMap = { ["#global"] = "default" },
	-- Duration (in seconds) that a key needs to be pressed before the "hold" action is executed.
	HoldThreshold = 1
}

-- These keys/inputs are ignored when the cursor is visible
local mouseKeys = { 
	[MOUSE_LEFT] = true,
	[MOUSE_RIGHT] = true
}

local info, warn = Photon2.Debug.Declare( "InputConfig" )

local print, printf = info, info

---@param controller PhotonController
function Photon2.ClientInput.SetTargetController( controller )
	print( "Setting input controller: (" .. tostring( controller ) .. ")" )
	if IsValid( controller ) then
		Photon2.ClientInput.TargetController = controller
		Photon2.ClientInput.SetActiveConfiguration( Photon2.ClientInput.GetProfilePreference( controller:GetProfileName() ) )
		Photon2.ClientInput.StartListening()
	else
		Photon2.ClientInput.TargetController = false
		Photon2.ClientInput.StopListening()
	end
end

function Photon2.ClientInput.StartListening()
	-- if ( not IsValid( controller ) ) then 
	-- 	ErrorNoHaltWithStack( "ClientInput instructed to start listening with an invalid controller entity.")
	-- end
	Photon2.ClientInput.Listening = true
end

function Photon2.ClientInput.StopListening()
	Photon2.ClientInput.Listening = false
end

function Photon2.ClientInput.SetActiveConfiguration( name )
	Photon2.ClientInput.Active = Photon2.GetInputConfiguration( name )
	if not ( Photon2.ClientInput.Active ) then
		warn( "Failed to retrieve input configuration [" .. name .. "]. Using default instead.")
		Photon2.ClientInput.Active = Photon2.GetInputConfiguration( "default" )
	end
end


function Photon2.ClientInput.ExecuteActions( actions, key, press, name )
	if ( not actions ) then return end
	if ( not IsValid( Photon2.ClientInput.TargetController ) ) then return end
	-- print("Executing " .. tostring(#actions) .. " actions...")
	local controller = Photon2.ClientInput.TargetController ---@as PhotonController
	controller:InputUserCommand( actions, press, name )
end

function Photon2.ClientInput.ValidateActions( actions, key, press )
	-- print("Validating " .. tostring(input.GetKeyName(key) .. " " .. tostring(trigger)))
	if ( not actions ) then return end

	local result = {}

	for i, action in pairs( actions ) do
		local pass = true
		if ( action.ModifierConfig ) then
			for modifier, pressed in pairs( action.ModifierConfig ) do
				if ( Photon2.IsKeyDown( modifier ) ~= pressed ) then
					pass = false
					break
				end
			end
		end
		if ( pass ) then
			result[#result+1] =
			{
				Key = input.GetKeyName( key ),
				Press = press,
				Action = action
			}
		end
	end

	if ( #result > 0 ) then Photon2.ClientInput.ExecuteActions( result, key, press ) end

end

local pressedKeys = {}

function Photon2.ClientInput.SimulatePress( commandName )
	if ( not IsValid( Photon2.ClientInput.TargetController ) ) then return end
	local command = Photon2.Index.Commands[commandName]
	if ( not command ) or ( not command.OnPress ) then return end
	local result = {}
	for i, action in pairs( command.OnPress) do
		result[#result+1] = 
		{
			Key = "VIRTUAL",
			Press = "Press",
			Action = action
		}
	end
	Photon2.ClientInput.ExecuteActions( result, 0, "Press", commandName )
end

function Photon2.ClientInput.SimulateHold( commandName )
	local command = Photon2.Index.Commands[commandName]
	if ( not command ) or ( not command.OnHold ) then return end
	local result = {}
	for i, action in pairs( command.OnHold ) do
		result[#result+1] = 
		{
			Key = "VIRTUAL",
			Press = "Hold",
			Action = action
		}
	end
	Photon2.ClientInput.ExecuteActions( result, 0, "Hold", commandName )
end

function Photon2.ClientInput.SimulateRelease( commandName )
	local command = Photon2.Index.Commands[commandName]
	if ( not command ) or ( not command.OnRelease ) then return end
	local result = {}
	for i, action in pairs( command.OnRelease ) do
		result[#result+1] = 
		{
			Key = "VIRTUAL",
			Press = "Release",
			Action = action
		}
	end
	Photon2.ClientInput.ExecuteActions( result, 0, "Release", commandName )
end

function Photon2.ClientInput.OnPress( key )
	-- OCTOBER INPUT DEMO 
		pressedKeys[#pressedKeys+1] = key
	--
	if ( not Photon2.ClientInput.Listening ) then return end
	if ( mouseKeys[key] and vgui.CursorVisible() ) then return end
	if ( not Photon2.ClientInput.Active.Binds[key] ) then return end

	local binds = Photon2.ClientInput.Active.Binds[key]
	-- print("OnPress:" .. tostring( input.GetKeyName(key) ) )
	if ( binds ) then
		Photon2.ClientInput.KeysPressed[key] = RealTime()
		Photon2.ClientInput.ValidateActions(  binds.OnPress, key, "Press" )
	end
end
hook.Add( "Photon2:KeyPressed", "Photon2.ClientInput:OnPress", Photon2.ClientInput.OnPress )

function Photon2.ClientInput.OnRelease( key )
	-- OCTOBER INPUT DEMO 
		table.RemoveByValue( pressedKeys, key )
	--
	if ( not Photon2.ClientInput.Listening ) then return end
	if ( mouseKeys[key] and vgui.CursorVisible() ) then return end
	-- print("OnRelease:" .. tostring( input.GetKeyName(key) ) )
	if ( Photon2.ClientInput.KeysPressed[key] ) then
		Photon2.ClientInput.KeysPressed[key] = nil

		local binds = Photon2.ClientInput.Active.Binds[key]

		Photon2.ClientInput.ValidateActions(  binds.OnRelease, key, "Release" )
	elseif ( Photon2.ClientInput.KeysHeld[key] ) then
		-- Release will not run if key is configured for hold
		Photon2.ClientInput.KeysHeld[key] = nil
	end
end
hook.Add( "Photon2:KeyReleased", "Photon2.ClientInput:OnRelease", Photon2.ClientInput.OnRelease )

-- Scans keys registered as "pressed" to check when they reach the "held" threshold.
function Photon2.ClientInput.ScanPressed()
	if ( not Photon2.ClientInput.Listening ) then return end
	for key, time in pairs( Photon2.ClientInput.KeysPressed ) do

		if ( not Photon2.ClientInput.Active.Binds[key] ) then return end

		local binds = Photon2.ClientInput.Active.Binds[key]

		if ( RealTime() >= ( time + Photon2.ClientInput.HoldThreshold ) and ( binds.OnHold ) ) then
			Photon2.ClientInput.KeysPressed[key] = nil
			Photon2.ClientInput.KeysHeld[key] = RealTime()
			Photon2.ClientInput.ValidateActions(  binds.OnHold, key, "Hold" )
		end
	end
end
hook.Add( "Think", "Photon2.ClientInput:Scan", Photon2.ClientInput.ScanPressed )

function Photon2.ClientInput.Initialize()
	info("Initializing client input...")
	Photon2.ClientInput.LoadPreferencesFile()
	if ( not Photon2.Library.InputConfigurations:Get( "user" ) ) then
		local config = Photon2.Library.InputConfigurations:GetCopy( "default" )
		if ( not config ) then
			warn( "Unable to retrieve default input configuration! This may indicate a library load failure!" )
			timer.Simple( 5, Photon2.ClientInput.Initialize )
			return
		end
		config.Name = "user"
		config.Title = "Default (User)"
		config.Author = "user"
		Photon2.Library.InputConfigurations:SaveToDataAndRegister( config )
	else
		info("\tInitialization complete.")
	end
end

function Photon2.ClientInput.LoadPreferencesFile()
	info("\tLoading user preferences file (photon_v2/user/profile_input_map.json)...")
	local raw = file.Read( "photon_v2/user/profile_input_map.json" )
	local prefs = util.JSONToTable( raw or "" )
	if ( not prefs ) then
		info("\tPreferences file does not exist or is corrupt. A new file will be created.")
	end
	Photon2.ClientInput.ProfileMap = prefs or { ["#global"] = "user" }
	if ( not prefs ) then Photon2.ClientInput.SavePreferencesFile() end
end

function Photon2.ClientInput.SavePreferencesFile()
	info("Saving preferences file.")
	file.Write( "photon_v2/user/profile_input_map.json", util.TableToJSON( Photon2.ClientInput.ProfileMap ) )
end

function Photon2.ClientInput.SetProfilePreference( profileName, configName )
	Photon2.ClientInput.LoadPreferencesFile()
	info( "Setting profile [%s] to use input configuration [%s]", profileName, configName )
	if ( configName == "user" and profileName ~= "#global" ) then configName = nil end
	Photon2.ClientInput.ProfileMap[profileName] = configName
	Photon2.ClientInput.SavePreferencesFile()
	if ( IsValid( Photon2.ClientInput.TargetController ) ) then
		Photon2.ClientInput.SetActiveConfiguration( 
			Photon2.ClientInput.GetProfilePreference( Photon2.ClientInput.TargetController:GetProfileName() ) )
	end
end

function Photon2.ClientInput.ExportProfileToJson( profile )
	-- local profile = Photon2.Library.InputConfigurations[profileName]
	-- if ( not profile ) then
	-- 	error( "Client input profile name [" .. tostring( profileName ) .. "] could not be found in the Library.")
	-- end
	profile = table.Copy( profile )
	
	local newBinds = {}

	for key, commands in pairs( profile.Binds ) do
		local keyName = input.GetKeyName( key )
		for _, command in ipairs( commands ) do
			if ( istable( command.Modifiers ) ) then
				local newModifiers = {}
				for i,  modifierKey in ipairs( command.Modifiers ) do
					newModifiers[i] = input.GetKeyName( modifierKey )
				end
				command.Modifiers = newModifiers
			end
		end
		newBinds[keyName] = profile.Binds[key]
	end

	profile.Binds = newBinds

	return util.TableToJSON( profile, true )
end

function Photon2.ClientInput.ImportProfileFromJson( jsonText )
	local profile = util.JSONToTable( jsonText )
	if not ( profile ) then
		warn( "Failed convert JSON to table. There is either a syntax error or the source file was corrupt. Default configuration is being returned instead." )
		return Photon2.GetInputConfiguration( "default" )
	end
	local newBinds = {}
	for key, commands in pairs( profile.Binds ) do
		local keyCode = input.GetKeyCode( key )
		newBinds[keyCode] = newBinds[keyCode] or {}
		for cmdIndex, command in ipairs( commands ) do
			if ( istable( command.Modifiers ) ) then
				local newModifiers = {}
				for i, modifierKey in ipairs( command.Modifiers ) do
					newModifiers[i] = input.GetKeyCode( modifierKey )
				end
				command.Modifiers = newModifiers
			end
			newBinds[keyCode][cmdIndex] = command
		end
	end

	profile.Binds = newBinds

	return profile
end

function Photon2.ClientInput.GetProfilePreference( profileName )
	return Photon2.ClientInput.ProfileMap[profileName] or Photon2.ClientInput.ProfileMap["#global"]
end

hook.Add( "InitPostEntity", "Photon2.ClientInput:Initialize", Photon2.ClientInput.Initialize )


local keyRenames = {
	["LEFTARROW"] = "◄",
	["RIGHTARROW"] = "►",
	["UPARROW"] = "▲",
	["DOWNARROW"] = "▼",
	["KP_END"] = "NUM1",
	["KP_DOWNARROW"] = "NUM2",
	["KP_PGDN"] = "NUM3",
	["KP_LEFTARROW"] = "NUM4",
	["KP_5"] = "NUM5",
	["KP_RIGHTARROW"] = "NUM6",
	["KP_HOME"] = "NUM7",
	["KP_UPARROW"] = "NUM8",
	["KP_PGUP"] = "NUM9",
	["KP_INS"] = "NUM0",
}

function Photon2.ClientInput.GetKeyPrintName( keyNum )
	local name = input.GetKeyName( keyNum )
	return string.upper( keyRenames[name] or name )
end

--[[
		==== ILLUM ====
		misc: hold for flood, release for takedown?
--]]


-- PrintTable( Photon2.ClientInput.Active )

-- Photon2.ClientInput.StartListening()

--[[
		Actions:
			1. SET: Channel's mode is set to the specified value.
			
			2. TOGGLE: Toggles between the specified value and OFF. 
			   If the value is set to something other than the target value, the channel will
			   first change to the target value, then OFF.
			
			3. TOGGLE_OFF: Toggles between a non-OFF value and OFF. This differs
			   from TOGGLE as the channel will turn off whenever it isn't already
			   OFF. Otherwise the channel is set to the default target value.

			4. CYCLE: Moves sequentially through a collection of values upon each
			   activation, one at a time. If a collection of values isn't specified,
			   all available modes are utilized as found in the vehicle file or
			   all its components.

			5. TOGGLE_ON: Set's the channel's mode to the specified value, but only
			   when the mode is OFF. If the mode is set to a value other than OFF,
			   no change will be applied.

		Key behaviors:
			1. OnPress: When the key is pressed down.
			2. OnRelease: When the key is released.
			3. OnHold: When the key is pressed and held for a certain duration (1 second).

		Modifiers:
			Allows for modifier keys (Shift, Alt, Control) to be used for multi-key binds.
			Actions that use modifier keys will only fire those actions so long as the modifer
			keys are held during during the event (press, release, or hold). If Ctrl+1 is pressed, 
			the main key is [1] and the modifier would be Ctrl, and the OnPress event would be 
			executed. If both keys were held, the OnHold event would be executed. If Ctrl was 
			then released before [1] was released, the related OnRelease event would NOT execute.

			Multiple modifier keys can be required as well, and similarly, corresponding actions
			will only execute as long as EVERY modifier key is being held during each event.

		----- 
		UNDECIDED ON IMPLEMENTATION...

		Active Input State:
			Primarily tracks the current index of cycle actions. Each action entry is assigned
			a sequential and unique index and its value is tracked. An internal table 
			maintains a direct map to these actions that is treated independently of the key
			hierarchy. This is processed and managed automatically without surfacing
			to the user.

		-----
--]]

surface.CreateFont( "PH2Demo", {
	font = "Roboto Light",
	size = 64,
	weight = 100,
	outline = true
} )

local inputDisplayConVar = GetConVar("ph2_display_input")

hook.Add( "HUDPaint", "Photon2:KeyDemo", function()
	if ( inputDisplayConVar:GetBool() ) then
		local pressedKeysString = ""
		for i=1, #pressedKeys do
			pressedKeysString = pressedKeysString .. input.GetKeyName(pressedKeys[i]) .. " (" .. tostring( pressedKeys[i] ) ..")"
			if ( i < #pressedKeys ) then
				pressedKeysString = pressedKeysString .. " + "
			end

		end
		draw.DrawText( pressedKeysString, "PH2Demo", ScrW() * 0.5, ScrH() * 0.75, color_white, TEXT_ALIGN_CENTER )
	end
end)