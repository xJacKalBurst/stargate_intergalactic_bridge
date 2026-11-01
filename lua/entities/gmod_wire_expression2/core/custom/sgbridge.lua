--[[
	Stargate Intergalactic Bridge : extension Expression 2
	Fonctions sgBridge... qui relient une puce E2 au coeur de l'addon (lua/stargate_intergalactic_bridge/sv_core.lua).
	Toute la logique du pont (ordre des gates, composition, camera, sortie) reste dans le script E2.
]]

E2Lib.RegisterExtension("sgbridge", true,
	"Stargate Intergalactic Bridge",
	"Allows E2 chips to hold players in a stargate network and move their camera")

local isOwner = E2Lib.isOwner
local alert = {}   -- [puce] = true : puces qui s'executent a chaque capture

local function session(self)
	if not SGIB then return end
	local chip = self.entity
	local s = SGIB.GetSession(chip, self.player)
	if s and not s.e2Listener then
		s.e2Listener = true
		SGIB.SetListener(chip, function(ply, gate)
			if not (alert[chip] and IsValid(chip)) then return end
			chip.context.data.sgbridgeClk = { ply, gate }
			chip:Execute()
			chip.context.data.sgbridgeClk = nil
		end)
	end
	return s
end

registerCallback("destruct", function(self)
	alert[self.entity] = nil
	if SGIB then SGIB.Drop(self.entity) end
end)

local function toVector(v) return Vector(v[1], v[2], v[3]) end
local function toAngle(a) return Angle(a[1], a[2], a[3]) end

__e2setcost(5)

--- Declare les gates du pont, dans l'ordre : la premiere est l'entree, la deuxieme sa destination (le pont ne se declenche
--- que si la premiere est ouverte sur la deuxieme). Si une gate n'est pas valide ou ne vous appartient pas, rien n'est declare.
--- Renvoie le nombre de gates declarees.
e2function number sgBridgeSetGates(array gates)
	if not session(self) then return 0 end
	local list = {}
	for _, g in ipairs(gates) do
		if not (isentity(g) and IsValid(g) and g.IsStargate and isOwner(self, g)) then
			SGIB.SetGates(self.entity, self.player, {})
			return 0
		end
		list[#list + 1] = g
	end
	return SGIB.SetGates(self.entity, self.player, list)
end

--- La puce s'execute a chaque joueur capture (activate = 1) ou plus (activate = 0).
e2function void runOnSGBridge(activate)
	if activate ~= 0 then
		session(self)
		alert[self.entity] = true
	else
		alert[self.entity] = nil
	end
end

--- Renvoie 1 si la puce s'execute parce qu'un joueur vient d'etre capture.
e2function number sgBridgeClk()
	return self.data.sgbridgeClk and 1 or 0
end

--- Joueur qui vient d'etre capture (valide pendant l'execution declenchee par la capture).
e2function entity sgBridgeCaptured()
	local c = self.data.sgbridgeClk
	return c and c[1] or NULL
end

--- Gate par laquelle le joueur vient d'entrer.
e2function entity sgBridgeEntryGate()
	local c = self.data.sgbridgeClk
	return c and c[2] or NULL
end

--- Place la camera des joueurs stockes (leur corps suit). La camera reste immobile, la souris oriente la vue.
e2function void sgBridgeSetCamera(vector pos)
	if not session(self) then return end
	SGIB.SetCamera(self.entity, toVector(pos), nil)
end

--- Idem, et oriente la vue du joueur vers ang au moment du deplacement de la camera.
e2function void sgBridgeSetCamera(vector pos, angle ang)
	if not session(self) then return end
	SGIB.SetCamera(self.entity, toVector(pos), toAngle(ang))
end

--- Duree maximale (secondes) de stockage d'un joueur avant urgence (il meurt et les gates du pont se ferment). Defaut : 120.
e2function void sgBridgeSetMaxHold(number seconds)
	if not session(self) then return end
	SGIB.SetMaxHold(self.entity, seconds)
end

--- Joueurs actuellement stockes par cette puce.
e2function array sgBridgeHeld()
	if not session(self) then return {} end
	return SGIB.GetHeld(self.entity)
end

--- Nombre de joueurs actuellement stockes par cette puce.
e2function number sgBridgeHeldCount()
	if not session(self) then return 0 end
	return #SGIB.GetHeld(self.entity)
end

--- 1 si les joueurs stockes peuvent sortir par exitGate maintenant (gate du pont ouverte, reliee a une autre gate).
e2function number sgBridgeCanRelease(entity exitGate)
	if not session(self) then return 0 end
	return SGIB.CanRelease(self.entity, exitGate) and 1 or 0
end

--- Fait sortir les joueurs stockes par exitGate (comme une traversee normale). Renvoie le nombre de joueurs sortis.
e2function number sgBridgeRelease(entity exitGate)
	if not session(self) then return 0 end
	return SGIB.Release(self.entity, exitGate)
end

--- Urgence : les joueurs stockes meurent et les gates du pont se ferment.
e2function void sgBridgeKill()
	if not session(self) then return end
	SGIB.Emergency(self.entity)
end
