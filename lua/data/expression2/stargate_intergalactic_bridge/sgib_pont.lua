@name SGIB Pont intergalactique
@inputs G1:wirelink G2:wirelink G3:wirelink G4:wirelink G5:wirelink G6:wirelink G7:wirelink G8:wirelink Open
@persist Gates:table GateEnts:array N Step State T Hold CamDist CamUp DialTimeout ExitDelay

# ===========================================================================
#  Pont intergalactique : le joueur qui traverse G1 est stocke, puis suit le pont gate apres gate.
#  Cablage : la sortie "wirelink" de chaque stargate vers G1, G2, ... dans l'ordre du pont (2 a 8 gates).
#  Entree "Open" (impulsion) : compose G1 -> G2 (ou composez G1 -> G2 vous-meme, au DHD).
#  Deroulement : G1 -> G2 ouvert, le joueur entre dans G1, camera devant G2 ; le lien se ferme ;
#  G2 compose G3, camera devant G3 ; ... ; a la derniere gate le joueur sort par l'horizon.
#  Etats : 0 repos / 1 vue devant la gate de destination / 2 fermeture du lien / 3 composition du lien suivant / 4 apres la sortie
# ===========================================================================

if (first() | dupefinished()) {
    Hold = 3           # secondes de vue devant chaque gate avant d'enchainer
    CamDist = 300      # distance de la camera devant la gate
    CamUp = 0          # hauteur de la camera par rapport au centre de la gate
    DialTimeout = 40   # secondes maximum pour qu'un lien se ferme ou s'ouvre (sinon urgence : le joueur meurt)
    ExitDelay = 3      # secondes entre la sortie du joueur et la fermeture du dernier lien
    State = 0
    runOnSGBridge(1)
    interval(100)
}

function void addGate(W:wirelink) {
    if (W:entity():isValid()) {
        N++
        Gates[N, wirelink] = W
        GateEnts[N, entity] = W:entity()
    }
}

function void camTo(K) {
    local E = GateEnts[K, entity]
    sgBridgeSetCamera(E:pos() + E:forward() * CamDist + E:up() * CamUp, (-E:forward()):toAngle())
}

function void closeAll() {
    for (I = 1, N) {
        Gates[I, wirelink]:stargateClose()
    }
}

# Declaration des gates du pont (a la mise en place, a la duplication et a chaque changement de cablage)
if (first() | dupefinished() | ~G1 | ~G2 | ~G3 | ~G4 | ~G5 | ~G6 | ~G7 | ~G8) {
    Gates = table()
    GateEnts = array()
    N = 0
    addGate(G1)
    addGate(G2)
    addGate(G3)
    addGate(G4)
    addGate(G5)
    addGate(G6)
    addGate(G7)
    addGate(G8)
    sgBridgeSetGates(GateEnts)
}

# Impulsion Open : compose le premier lien
if (~Open & Open & State == 0 & N >= 2) {
    Gates[1, wirelink]:stargateDial(GateEnts[2, entity]:stargateAddress())
}

# Un joueur vient d'entrer dans G1 : il est stocke, la camera va devant la gate de destination
if (sgBridgeClk()) {
    if (State == 0 & N >= 2 & sgBridgeEntryGate() == GateEnts[1, entity]) {
        Step = 1
        State = 1
        T = curtime() + Hold
        camTo(2)
    } else {
        sgBridgeKill()
    }
}

# Joueur mort ou parti pendant le transit : on referme tout
if (State >= 1 & State <= 3 & sgBridgeHeldCount() == 0) {
    closeAll()
    State = 0
}

# 1 : vue devant la gate de destination, puis sortie (derniere gate) ou fermeture du lien
if (State == 1 & curtime() >= T) {
    if (Step + 1 == N) {
        if (sgBridgeCanRelease(GateEnts[N, entity])) {
            sgBridgeRelease(GateEnts[N, entity])
            State = 4
            T = curtime() + ExitDelay
        } elseif (curtime() > T + DialTimeout) {
            sgBridgeKill()
            State = 0
        }
    } else {
        Gates[Step, wirelink]:stargateClose()
        State = 2
        T = curtime() + DialTimeout
    }
}

# 2 : attente de la fermeture des deux gates, puis la gate de destination compose la suivante
if (State == 2) {
    if (Gates[Step, wirelink]:stargateGetWire("Active") == 0 & Gates[Step + 1, wirelink]:stargateGetWire("Active") == 0) {
        Gates[Step + 1, wirelink]:stargateDial(GateEnts[Step + 2, entity]:stargateAddress())
        Step++
        State = 3
        T = curtime() + DialTimeout
    } elseif (curtime() > T) {
        sgBridgeKill()
        State = 0
    }
}

# 3 : attente de l'ouverture du lien, la camera passe devant la gate suivante
if (State == 3) {
    if (Gates[Step, wirelink]:stargateGetWire("Open") == 1) {
        camTo(Step + 1)
        State = 1
        T = curtime() + Hold
    } elseif (curtime() > T) {
        sgBridgeKill()
        State = 0
    }
}

# 4 : le joueur est sorti, on ferme le dernier lien
if (State == 4 & curtime() >= T) {
    Gates[N - 1, wirelink]:stargateClose()
    State = 0
}

interval(100)
