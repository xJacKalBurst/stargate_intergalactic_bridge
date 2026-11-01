--[[
	Stargate Intergalactic Bridge : coeur serveur

	Principe : une "session" est creee par une puce (E2, plus tard Starfall / E3) qui declare les gates du pont.
	Quand un joueur entre dans l'horizon d'une gate du pont (ouverte et reliee a une autre gate), la teleportation
	native du CAP / de l'EAP est annulee (hook StarGate.Teleport / Lib.Teleport) et le joueur est "stocke" :
	invisible, non solide, entrees bloquees, avec sa camera detachee placee ou le script le demande.
	Le script decide de tout le reste (composition des gates, deplacement de la camera, moment de la sortie).

	API (appelee par les extensions E2 / Starfall / E3) :
		SGIB.SetGates(chip, owner, gates)       declare les gates du pont, dans l'ordre (1 = entree, 2 = sa destination)
		SGIB.SetCamera(chip, pos, ang)          place la camera (et le corps) des joueurs stockes ; ang optionnel
		SGIB.SetMaxHold(chip, secondes)         duree maximale de stockage avant urgence
		SGIB.SetListener(chip, fn)              fn(joueur, gate) est appelee a chaque capture
		SGIB.GetHeld(chip)                      tableau des joueurs stockes
		SGIB.CanRelease(chip, exitGate)         true si la sortie par exitGate est possible maintenant
		SGIB.Release(chip, exitGate)            fait sortir les joueurs stockes par exitGate (nombre de joueurs sortis)
		SGIB.Emergency(chip)                    urgence : tue les joueurs stockes et ferme les gates du pont
		SGIB.Drop(chip)                         la puce disparait : urgence s'il reste des joueurs, puis session supprimee
]]

SGIB = SGIB or {}
SGIB.Sessions = SGIB.Sessions or {}   -- [puce] = session
SGIB.Held = SGIB.Held or {}           -- [joueur] = enregistrement de stockage
SGIB.Pending = SGIB.Pending or {}     -- [joueur] = true entre l'interception et le stockage effectif

util.AddNetworkString("sgib_cam")

local DEFAULT_MAX_HOLD = 120          -- secondes avant urgence si le script ne libere jamais le joueur
local DEFAULT_CAM_DISTANCE = 300      -- camera par defaut : distance devant la gate de destination
local WATCHDOG_INTERVAL = 1

-- ============================================================================
-- Sessions
-- ============================================================================

local function newSession(chip, owner)
	return {
		chip = chip,
		owner = owner,
		gates = {},          -- [gate] = true
		list = {},           -- gates dans l'ordre du pont : [1] = gate d'entree, [2] = sa destination
		held = {},           -- [joueur] = true
		camPos = nil,
		camAng = nil,
		maxHold = DEFAULT_MAX_HOLD,
		listener = nil,
	}
end

function SGIB.GetSession(chip, owner)
	local s = SGIB.Sessions[chip]
	if not s and IsValid(chip) then
		s = newSession(chip, owner)
		SGIB.Sessions[chip] = s
	end
	return s
end

local function findSession(gate)
	for _, s in pairs(SGIB.Sessions) do
		if s.gates[gate] then return s end
	end
end

function SGIB.SetGates(chip, owner, gates)
	local s = SGIB.GetSession(chip, owner)
	if not s then return 0 end
	s.gates = {}
	s.list = {}
	local n = 0
	for _, g in ipairs(gates) do
		if IsValid(g) and g.IsStargate then
			-- une gate n'appartient qu'a un seul pont : la derniere declaration l'emporte
			for _, other in pairs(SGIB.Sessions) do
				if other ~= s then other.gates[g] = nil end
			end
			s.gates[g] = true
			n = n + 1
			s.list[n] = g
		end
	end
	return n
end

function SGIB.SetMaxHold(chip, seconds)
	local s = SGIB.GetSession(chip)
	if s then s.maxHold = math.max(1, seconds) end
end

function SGIB.SetListener(chip, fn)
	local s = SGIB.GetSession(chip)
	if s then s.listener = fn end
end

function SGIB.GetHeld(chip)
	local out = {}
	local s = SGIB.Sessions[chip]
	if s then
		for ply in pairs(s.held) do
			if IsValid(ply) then out[#out + 1] = ply end
		end
	end
	return out
end

-- ============================================================================
-- Outils : effets natifs, camera
-- ============================================================================

-- Rejoue ce que l'horizon fait juste avant une teleportation : effet d'entree et son
local function playEnter(horizon, ply)
	if not IsValid(horizon) then return end
	if horizon.EnterEffectEntity then horizon:EnterEffectEntity(ply) end
	local snd = horizon.Sounds and horizon.Sounds.Teleport
	if snd and #snd > 0 then
		horizon:EmitSound(snd[math.random(#snd)], 90, math.random(90, 110))
	end
end

-- Meme chose sur l'horizon d'arrivee (le CAP le fait 0,05 s apres la teleportation)
local function playExit(horizon, ply)
	timer.Simple(0.05, function()
		if IsValid(horizon) and IsValid(ply) then playEnter(horizon, ply) end
	end)
end

local function sendCamera(ply, pos)
	net.Start("sgib_cam")
	net.WriteBool(pos ~= nil)
	if pos then net.WriteVector(pos) end
	net.Send(ply)
end

-- Camera par defaut : devant la gate de destination, tournee vers elle
local function defaultCamera(horizon, ply)
	local target = IsValid(horizon) and horizon.Target
	if not IsValid(target) then return ply:GetPos(), nil end
	local f = target:GetForward()
	return target:GetPos() + f * DEFAULT_CAM_DISTANCE, (-f):Angle()
end

local function placeCamera(ply, rec, pos, ang)
	rec.cam = pos
	ply:SetPos(pos)               -- le corps suit la camera : le serveur envoie au client ce qui est autour de ce point
	if ang then ply:SetEyeAngles(ang) end
	sendCamera(ply, pos)
end

function SGIB.SetCamera(chip, pos, ang)
	local s = SGIB.GetSession(chip)
	if not s then return end
	s.camPos = pos
	s.camAng = ang
	for ply in pairs(s.held) do
		local rec = SGIB.Held[ply]
		if IsValid(ply) and rec then placeCamera(ply, rec, pos, ang) end
	end
end

-- ============================================================================
-- Stockage / restitution d'un joueur
-- ============================================================================

local blockedFlags = { "DisableSpawning", "DisableSuicide", "DisableNoclip" }  -- reconnus par l'EAP

local function hide(ply, rec)
	rec.god = ply:HasGodMode()
	rec.notarget = ply:IsFlagSet(FL_NOTARGET)
	ply:SetNoDraw(true)
	ply:DrawViewModel(false)
	ply:DrawWorldModel(false)
	ply:SetMoveType(MOVETYPE_NONE)
	ply:SetSolid(SOLID_NONE)
	ply:AddFlags(FL_NOTARGET)
	ply:GodEnable()
	ply:Flashlight(false)
	for _, f in ipairs(blockedFlags) do ply[f] = true end
end

local function unhide(ply)
	local rec = SGIB.Held[ply]
	if not IsValid(ply) or not rec then return end
	ply:SetNoDraw(false)
	ply:DrawViewModel(true)
	ply:DrawWorldModel(true)
	ply:SetSolid(SOLID_BBOX)
	ply:SetMoveType(MOVETYPE_WALK)
	if not rec.notarget then ply:RemoveFlags(FL_NOTARGET) end
	if not rec.god then ply:GodDisable() end
	for _, f in ipairs(blockedFlags) do ply[f] = nil end
	sendCamera(ply, nil)
end

-- Oublie le joueur sans toucher a son etat (mort, deconnexion)
local function forget(ply)
	local rec = SGIB.Held[ply]
	if rec and rec.session then rec.session.held[ply] = nil end
	SGIB.Held[ply] = nil
	SGIB.Pending[ply] = nil
end

local function store(session, ply, horizon, gate, rec)
	if not (IsValid(ply) and ply:Alive()) then
		SGIB.Pending[ply] = nil
		return
	end
	-- premier joueur d'un nouveau passage : on oublie la camera du passage precedent
	if next(session.held) == nil then session.camPos, session.camAng = nil, nil end
	rec.session = session
	rec.gate = gate
	rec.horizon = horizon
	rec.t0 = CurTime()
	SGIB.Held[ply] = rec
	SGIB.Pending[ply] = nil
	session.held[ply] = true
	hide(ply, rec)
	local pos, ang = session.camPos, session.camAng
	if not pos then pos, ang = defaultCamera(horizon, ply) end
	placeCamera(ply, rec, pos, ang)
	if session.listener then
		local ok, err = pcall(session.listener, ply, gate)
		if not ok then ErrorNoHalt("[SGIB] ", tostring(err), "\n") end
	end
end

-- ============================================================================
-- Interception : meme signature pour le CAP (StarGate.Teleport) et l'EAP (Lib.Teleport)
-- ============================================================================

local function intercept(flashMessage)
	return function(ply, horizon, attached)
		if not (IsValid(ply) and ply:IsPlayer() and IsValid(horizon)) then return end
		if SGIB.Held[ply] or SGIB.Pending[ply] then return false end

		local gate = horizon:GetParent()
		if not IsValid(gate) then return end
		local session = findSession(gate)
		if not session then return end

		-- memes conditions que la teleportation native : sinon on la laisse faire (qui tue le joueur)
		if not horizon:IsOpen() or horizon.Unstable or horizon.ShuttingDown then return end
		local target = horizon.Target
		if not IsValid(target) then return end
		local dir = (horizon:GetVelocity() - ply:GetVelocity()):GetNormalized()
		if horizon:GetForward():DotProduct(dir) < 0 then return end
		-- le pont ne s'applique que si la gate d'entree est ouverte sur la premiere destination du pont
		local tgate = target:GetParent()
		if session.list[1] ~= gate or session.list[2] ~= tgate then return end
		if IsValid(tgate) and tgate.IsStargate and tgate:IsBlocked() then return end

		-- position d'entree dans le repere de l'horizon, pour sortir plus tard au meme endroit
		local _, lang = WorldToLocal(vector_origin, ply:EyeAngles(), horizon:GetPos(), horizon:GetAngles())
		local rec = {
			lpos = horizon:WorldToLocal(ply:GetPos()),
			lvel = horizon:WorldToLocal(ply:GetVelocity() + horizon:GetPos()),
			lang = lang,
		}

		SGIB.Pending[ply] = true
		-- meme aspect que le passage normal : effet d'entree, son, flash d'ecran
		playEnter(horizon, ply)
		playExit(target, ply)
		umsg.Start(flashMessage, ply)
		umsg.End()

		-- le reste hors du callback de collision
		timer.Simple(0, function()
			if IsValid(ply) then store(session, ply, horizon, gate, rec) end
		end)
		return false
	end
end

hook.Add("StarGate.Teleport", "SGIB.Intercept", intercept("StarGate.CalcView.TeleportEffectStart"))
hook.Add("Lib.Teleport", "SGIB.Intercept", intercept("Lib.CalcView.TeleportEffectStart"))

-- ============================================================================
-- Sortie
-- ============================================================================

-- Horizon source (gate qui a compose) et horizon d'arrivee d'un lien ouvert dont exitGate est l'arrivee.
-- Attention : l'horizon d'arrivee n'a pas de Target (seul l'horizon sortant en a un) ; la gate d'arrivee garde en revanche
-- la gate qui l'appelle dans gate.Target (CAP : ActivateStargate, "e.Target = self.Entity").
local function exitHorizons(exitGate)
	if not IsValid(exitGate) then return end
	local srcGate = exitGate.Target
	if not (IsValid(srcGate) and srcGate.IsStargate and srcGate.IsOpen and exitGate.IsOpen) then return end
	local src = srcGate.EventHorizon
	if not (IsValid(src) and src.Teleport and src.GetEntitiesForTeleport and src:IsOpen()) then return end
	local exitH = src.Target
	if not (IsValid(exitH) and exitH:GetParent() == exitGate) then return end
	return exitH, src
end

function SGIB.CanRelease(chip, exitGate)
	local s = SGIB.Sessions[chip]
	if not s or not s.gates[exitGate] then return false end
	return exitHorizons(exitGate) ~= nil
end

function SGIB.Release(chip, exitGate)
	local s = SGIB.Sessions[chip]
	if not s or not s.gates[exitGate] then return 0 end
	local exitH, src = exitHorizons(exitGate)
	if not exitH then return 0 end

	local count = 0
	for ply in pairs(s.held) do
		local rec = SGIB.Held[ply]
		if IsValid(ply) and rec then
			unhide(ply)
			forget(ply)

			-- le joueur reapparait devant l'horizon source, comme s'il y entrait, puis la teleportation native fait le reste
			local _, ang = LocalToWorld(vector_origin, rec.lang, src:GetPos(), src:GetAngles())
			ply:SetPos(src:LocalToWorld(rec.lpos))
			ply:SetEyeAngles(ang)
			ply:SetLocalVelocity(src:LocalToWorld(rec.lvel) - src:GetPos())

			playEnter(src, ply)
			local attached = src:GetEntitiesForTeleport(ply) or { Entity = ply, Attached = {} }
			src:Teleport(ply, false, attached)
			playExit(exitH, ply)
			count = count + 1
		end
	end
	return count
end

-- ============================================================================
-- Urgences : le joueur meurt, les gates du pont se ferment
-- ============================================================================

local function closeGate(gate)
	if not IsValid(gate) then return end
	if gate.IsOpen and gate.DeactivateStargate then
		gate:DeactivateStargate(true)
	elseif gate.EmergencyShutdown and (gate.Dialling or gate.Active) then
		gate:EmergencyShutdown()
	end
end

local function killHeld(ply)
	if not SGIB.Held[ply] then return end
	unhide(ply)
	forget(ply)
	if IsValid(ply) and ply:Alive() then ply:Kill() end
end

function SGIB.Emergency(chip)
	local s = SGIB.Sessions[chip]
	if not s then return end
	local hadHeld = next(s.held) ~= nil
	for ply in pairs(s.held) do killHeld(ply) end
	if hadHeld then
		for gate in pairs(s.gates) do closeGate(gate) end
	end
end

function SGIB.Drop(chip)
	SGIB.Emergency(chip)
	SGIB.Sessions[chip] = nil
end

-- Surveillance : puce disparue, duree maximale depassee
timer.Create("SGIB.Watchdog", WATCHDOG_INTERVAL, 0, function()
	for chip, s in pairs(SGIB.Sessions) do
		if not IsValid(chip) then
			SGIB.Drop(chip)
		else
			for ply in pairs(s.held) do
				local rec = SGIB.Held[ply]
				if not IsValid(ply) then
					s.held[ply] = nil
				elseif rec and CurTime() - rec.t0 > s.maxHold then
					SGIB.Emergency(chip)
					break
				end
			end
		end
	end
end)

hook.Add("PlayerDeath", "SGIB.Death", function(ply)
	if SGIB.Held[ply] then unhide(ply) forget(ply) end
end)
hook.Add("PlayerSilentDeath", "SGIB.Death", function(ply)
	if SGIB.Held[ply] then unhide(ply) forget(ply) end
end)
hook.Add("PlayerDisconnected", "SGIB.Disconnect", function(ply)
	forget(ply)
end)

-- ============================================================================
-- Joueur stocke : plus aucune action possible, visibilite autour de la camera
-- ============================================================================

hook.Add("StartCommand", "SGIB.Lock", function(ply, cmd)
	if SGIB.Held[ply] then
		cmd:ClearMovement()
		cmd:ClearButtons()
	end
end)

hook.Add("SetupPlayerVisibility", "SGIB.PVS", function(ply)
	local rec = SGIB.Held[ply]
	if rec and rec.cam then AddOriginToPVS(rec.cam) end
end)

local function denyIfHeld(ply)
	if SGIB.Held[ply] then return false end
end

for _, name in ipairs({
	"PlayerNoClip", "PlayerSwitchWeapon", "PlayerSwitchFlashlight", "PlayerUse", "PlayerCanPickupWeapon",
	"PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerSpawnNPC", "PlayerSpawnVehicle",
	"PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerSpawnObject", "CanProperty", "CanTool",
}) do
	hook.Add(name, "SGIB.Deny", denyIfHeld)
end
