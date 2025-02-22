Photon2.Index = Photon2.Index or {}
Photon2.Index.Tones = Photon2.Index.Tones or {}
Photon2.Index.Profiles = Photon2.Index.Profiles or { Map = {}, Vehicles = {} }

--[[
	Profiles = {
		Map = {
			["prop_vehicle_jeep"] = {
				["models/sentry/20fpiu_new.mdl"] = {
					["~default"] = "photon_sgm_fpiu20",
					["20fpiu_new_sgm"] = "photon_sgm_fpiu20"
				}
			}
		},
		Vehicles = {
			["sgm_fpiu_2020_new"] = "photon_sgm_fpiu20"
		}	
	}
]]

local print = Photon2.Debug.PrintF
local printf = Photon2.Debug.PrintF

local info, warn = Photon2.Debug.Declare( "Index" )

local lastSave = SysTime()
local doubleSaveThreshold = 1

local index = Photon2.Index
local library = Photon2.Library
local debug = Photon2.Debug

local toneNameToNumber = {}
local toneNumberToName = {}

for i=1, 10 do
	toneNumberToName[i] = "T" .. tostring(i)
	toneNameToNumber["T" .. tostring(i)] = i
end

function Photon2.Index.CompileSiren( siren )
	if ( not isstring( siren.Name ) ) then 
		ErrorNoHaltWithStack( "Siren Name must be defined and must be a string. Received: " .. tostring( siren.Name ) )
		return nil
	end

	local result = table.Copy(siren)
	
	result.Sounds = result.Sounds or {}

	local buildTones = false

	if ( not result.Tones ) then
		result.Tones = {}
		buildTones = true
	end

	for name, sound in pairs( result.Sounds ) do
		sound.Name = name
		sound.Siren = result.Name
		if ( not sound.Label ) then
			sound.Label = name
		end
		if ( not sound.Icon ) then
			sound.Icon = string.lower( sound.Name )
		end
		if ( buildTones ) then
			if ( sound.Default ) then
				result.Tones[sound.Default] = sound
			end
		end
		local id = string.lower( result.Name .. "/" .. sound.Name )
		Photon2.Index.Tones[id] = sound
	end

	local numericTones = {}
	local sortedTones = {}

	for toneName, tone in pairs( result.Tones ) do
		if ( toneNameToNumber[toneName] ) then
			numericTones[#numericTones+1] = { toneName, toneNameToNumber[toneName] }
		end
	end

	table.SortByMember( numericTones, 2, true )

	for i=1, #numericTones do
		sortedTones[i] = numericTones[i][1]
		sortedTones[numericTones[i][1]] = i
	end


	if ( result.Tones.OFF == nil ) then
		result.Tones.OFF = { Default = "OFF", Name = "OFF", Label = "OFF", Icon = "siren" }
	end

	result.OrderedTones = sortedTones

	return result
	-- Photon2.Index.Sirens[result.Name] = result
	
	-- printf( "Compiling siren [%s] and adding to index.", result.Name )
	-- return Photon2.Index.Sirens[result.Name]
end

function index.ProcessSirenLibrary()
	for name, data in pairs ( library.Sirens ) do
		index.CompileSiren( data )
	end
end

function Photon2.GetSirenTone( name )
	local result = Photon2.Index.Tones[name]
	if ( result ) then return result end
	
	local split = string.Split( name, "/" )
	local siren = Photon2.GetSiren( split[1] )
	if ( siren ) and siren.Sounds[string.upper(split[2] or "")] then 
		return Photon2.GetSirenTone( name )
	else
		print( "Unable to find siren tone: " .. tostring( name ) )
	end
	return nil
end


-- Compiles a configuration with Library inheritance support
function Photon2.Index.CompileInputConfiguration( config )
	local inheritancePath = nil

	local binds = config.Binds
	if ( config.Inherit ) then
		local searching = true
		local currentParent = config.Inherit
		if ( currentParent ) then
			inheritancePath = { config.Name }
			inheritancePath[#inheritancePath+1] = currentParent
			while ( searching ) do
				-- local nextParent = Photon2.Library.InputConfigs[currentParent]
				local nextParent = Photon2.Library.InputConfigurations:Get( currentParent )
				if ( nextParent and nextParent.Inherit ) then
					inheritancePath[#inheritancePath+1] = nextParent.Inherit
					currentParent = nextParent.Inherit
				else
					searching = false
				end
			end
			binds = {}
			for i=#inheritancePath, 1, -1 do
				local parentConfig = Photon2.Library.InputConfigurations:Get(inheritancePath[i])
				-- local parentConfig = Photon2.Library.InputConfigs[inheritancePath[i]]
				for key, commands in pairs( parentConfig.Binds ) do
					binds[key] = commands
				end
			end
			config.Binds = binds
		end
	end
	
	local keys = config.Binds
	
	binds = {}

	-- Loads commands into the configuration
	for key, commands in pairs( keys ) do
		binds[key] = {}
		for _, commandEntry in pairs ( commands ) do
			local command = Photon2.GetCommand( commandEntry.Command )
			if ( not command ) then
				info( "Input profile [%s] references command [%s], which is not defined on this server. Ignoring.", commandEntry.Command, config.Name )
				continue
			end
			for _, event in pairs( Photon2.ClientInput.KeyActivities ) do
				if ( command[event] ) then
					binds[key][event] = binds[key][event] or {}

					binds[key][event][#binds[key][event]+1] = {
						Action = "META",
						Value = command.Name
					}

					for _, action in pairs( command[event] ) do
						binds[key][event][#binds[key][event]+1] = table.Copy( action )
						binds[key][event][#binds[key][event]].Modifiers = commandEntry.Modifiers
					end
				end
			end
		end
	end

	-- Processes actual command actions and optimize
	for key, keyConfig in pairs( binds ) do
		local modifiers = {}
		local actions = {}
		for _, activity in pairs( Photon2.ClientInput.KeyActivities ) do
			if ( istable( keyConfig[activity] ) ) then
				for _, action in pairs( keyConfig[activity] ) do
					action.ModifierConfig = {}
					if ( istable( action.Modifiers ) ) then
						for _, modifierKey in pairs( action.Modifiers ) do
							modifiers[modifierKey] = true
							action.ModifierConfig[modifierKey] = true
						end
					end
					actions[#actions+1] = action
				end
			end
		end
		for i, action in pairs( actions ) do
			-- Process modifier keys
			for modifierKey, _ in pairs( modifiers ) do
				if ( action.ModifierConfig[modifierKey] == nil ) then
					action.ModifierConfig[modifierKey] = false
				end
			end
			-- Process value mapping
			if ( istable( action.Value ) ) then
				action.ValueMap = {}
				for j, value in pairs( action.Value ) do
					action.ValueMap[value] = j
				end
			end
		end
	end

	-- Build map that indexes by command
	local commandMap = {}
	for key, commands in pairs( config.Binds ) do
		for i, command in ipairs( commands ) do
			commandMap[command.Command] = commandMap[command.Command] or {}
			local displayKey = ""
			if ( command.Modifiers ) then
				for _i, modifier in ipairs( command.Modifiers ) do
					displayKey = displayKey .. Photon2.ClientInput.GetKeyPrintName( modifier ) .. " + "
				end
			end
			displayKey = displayKey .. Photon2.ClientInput.GetKeyPrintName( key )
			commandMap[command.Command][#commandMap[command.Command]+1] = {
				Key = key,
				Modifiers = command.Modifiers,
				Display = displayKey
			}
		end
	end

	return {
		Name = config.Name,
		Title = config.Title,
		Author = config.Author,
		Binds = binds,
		Map = commandMap
	}
end

