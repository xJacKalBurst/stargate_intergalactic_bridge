# Stargate Intergalactic Bridge

Gére un pont intergalactique comme dans la série Stargate Atlantis, dans le jeu Garry's Mod, compatible des addons CAP et EAP (Au moins un est requis)

Addon plug and play pour Garry's Mod (CAP et EAP, y compris mélangés). Il n'ajoute aucune entité : il fournit des
fonctions que les puces appellent, et la logique du pont reste dans le script.

## Installation
Copier le dossier `stargate_intergalactic_bridge` dans `garrysmod/addons/`, puis relancer le jeu (ou le serveur).
Les scripts fournis apparaissent dans l'éditeur E2, dossier `stargate_intergalactic_bridge`
(recopiés à chaque démarrage : faire une copie sous un autre nom avant de les modifier).

## Principe
- Le joueur qui entre dans une gate du pont (ouverte et reliée à une autre gate) n'est pas téléporté : l'addon
  rejoue l'effet d'entrée, le son et le flash du CAP/EAP, puis stocke le joueur (invisible, non solide, entrées bloquées).
- Sa caméra est un point fixe que le script déplace ; la souris oriente la vue.
- À la dernière gate, `sgBridgeRelease` replace le joueur devant l'horizon source et utilise la téléportation native
  (même position d'entrée, même vitesse, mêmes effets).
- Urgence (puce supprimée, durée maximale dépassée, `sgBridgeKill`) : le joueur meurt, les gates du pont se ferment.

## Fonctions E2
| Fonction | Rôle |
|---|---|
| `sgBridgeSetGates(array)` | gates du pont (celles dont vous êtes propriétaire) ; renvoie le nombre retenu |
| `runOnSGBridge(1)` / `sgBridgeClk()` | la puce s'exécute à chaque capture |
| `sgBridgeCaptured()` / `sgBridgeEntryGate()` | joueur capturé / gate d'entrée (pendant cette exécution) |
| `sgBridgeSetCamera(vector)` / `sgBridgeSetCamera(vector, angle)` | place la caméra (et le corps) ; l'angle oriente la vue à ce moment |
| `sgBridgeHeld()` / `sgBridgeHeldCount()` | joueurs stockés par cette puce |
| `sgBridgeCanRelease(entity)` / `sgBridgeRelease(entity)` | sortie par la gate donnée (doit être ouverte) |
| `sgBridgeSetMaxHold(number)` | durée maximale de stockage avant urgence (120 s par défaut) |
| `sgBridgeKill()` | urgence |

## Script fourni
`sgib_pont` : câbler le wirelink de chaque stargate sur G1, G2, ... dans l'ordre du pont (2 à 8 gates).
Ouvrir G1 -> G2 (entrée `Open` ou au DHD), puis entrer dans G1.

## Ce que l'addon ne modifie pas
Aucun fichier du CAP, de l'EAP ou de Garry's Mod. Il ajoute seulement des hooks (`StarGate.Teleport`, `Lib.Teleport`)
et lit les entités des gates. Le supprimer remet tout à l'état normal.
