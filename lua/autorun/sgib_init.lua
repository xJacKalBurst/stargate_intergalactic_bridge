--[[
	Stargate Intergalactic Bridge : chargement
	Addon plug and play : a copier dans garrysmod/addons/. Aucun fichier du jeu, du CAP ou de l'EAP n'est modifie.
]]

SGIB = SGIB or {}

local DIR = "stargate_intergalactic_bridge/"
local SCRIPT_DIR = "data/expression2/stargate_intergalactic_bridge/"

if SERVER then
	AddCSLuaFile(DIR .. "cl_core.lua")
	AddCSLuaFile(DIR .. "cl_scripts.lua")
	-- les scripts E2 fournis voyagent comme des fichiers Lua (seul format que le jeu envoie) puis sont recopies cote client
	for _, f in ipairs(file.Find(SCRIPT_DIR .. "*.lua", "LUA")) do
		AddCSLuaFile(SCRIPT_DIR .. f)
	end
	include(DIR .. "sv_core.lua")
else
	include(DIR .. "cl_core.lua")
	include(DIR .. "cl_scripts.lua")
end
