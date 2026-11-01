--[[
	Stargate Intergalactic Bridge : camera client
	Le serveur envoie la position de la camera au seul joueur stocke. La camera est immobile (position imposee)
	mais l'orientation suit la souris : on garde les angles de vue du joueur.
]]

SGIB = SGIB or {}

local camPos = nil

net.Receive("sgib_cam", function()
	if net.ReadBool() then
		camPos = net.ReadVector()
	else
		camPos = nil
	end
end)

hook.Add("CalcView", "SGIB.Camera", function(ply, origin, angles, fov)
	if not camPos then return end
	return {
		origin = camPos,
		angles = angles,
		fov = fov,
		drawviewer = false,
	}
end)

hook.Add("HUDShouldDraw", "SGIB.HideCrosshair", function(name)
	if camPos and name == "CHudCrosshair" then return false end
end)
