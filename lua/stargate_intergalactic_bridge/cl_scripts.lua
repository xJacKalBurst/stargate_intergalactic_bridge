--[[
	Stargate Intergalactic Bridge : installation des scripts E2 fournis
	L'editeur E2 lit le dossier data/expression2 de CE poste. Au demarrage, les scripts de l'addon sont recopies dans
	data/expression2/stargate_intergalactic_bridge/ (ecrases a chaque demarrage : faites une copie sous un autre nom avant de les modifier).
]]

local SRC = "data/expression2/stargate_intergalactic_bridge/"
local DST = "expression2/stargate_intergalactic_bridge"

local function install()
	if not file.IsDir("expression2", "DATA") then file.CreateDir("expression2") end
	if not file.IsDir(DST, "DATA") then file.CreateDir(DST) end
	for _, name in ipairs(file.Find(SRC .. "*.lua", "LUA")) do
		local text = file.Read(SRC .. name, "LUA")
		if text then
			file.Write(DST .. "/" .. string.StripExtension(name) .. ".txt", text)
		end
	end
end

local ok, err = pcall(install)
if not ok then print("[SGIB] Installation des scripts E2 impossible : " .. tostring(err)) end
