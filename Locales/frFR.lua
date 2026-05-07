local addonName, TW = ...

if GetLocale() ~= "frFR" then return end

local L = TW.L

-- Tabs
L["Layout"]   = "Disposition"
L["Bars"]     = "Barres"
L["Text"]     = "Texte"
L["Auras"]    = "Auras"
L["Profiles"] = "Profils"
L["About"]    = "À propos"

-- Profiles
L["Active profile"]                              = "Profil actif"
L["Character:"]                                  = "Personnage :"
L["New..."]                                      = "Nouveau..."
L["Reset"]                                       = "Réinitialiser"
L["Delete"]                                      = "Supprimer"
L["Name of the new profile (copies current settings):"] = "Nom du nouveau profil (copie les réglages actuels) :"
L["Name for the imported profile:"]              = "Nom du profil à importer :"
L["Reset profile '%s' to defaults?"]             = "Réinitialiser le profil '%s' aux valeurs par défaut ?"
L["Delete profile '%s'?"]                        = "Supprimer le profil '%s' ?"
L["cannot delete Default"]                       = "impossible de supprimer Default"
L["profile '%s' created"]                        = "profil '%s' créé"
L["profile '%s' imported"]                       = "profil '%s' importé"
L["import failed:"]                              = "échec de l'import :"
L["import box is empty"]                         = "la zone d'import est vide"
L["Export"]                                      = "Exporter"
L["Import"]                                      = "Importer"
L["Refresh export"]                              = "Rafraîchir l'export"
L["Select all"]                                  = "Tout sélectionner"
L["Import as new profile..."]                    = "Importer comme nouveau profil..."

-- Minimap button
L["Show minimap button"] = "Bouton minimap"
L["Left-click: options"] = "Clic gauche : options"
L["Right-click: mover"]  = "Clic droit : mover"
L["Drag: reposition"]    = "Glisser : repositionner"

-- Range fade
L["Fade out-of-range tanks"] = "Estomper les tanks hors de portée"
L["Out-of-range alpha"]      = "Alpha hors de portée"

-- Filters
L["Filters"]                                                              = "Filtres"
L["Whitelist (always show)"]                                              = "Whitelist (toujours afficher)"
L["Blacklist (never show)"]                                               = "Blacklist (ne jamais afficher)"
L["Spell ID:"]                                                            = "ID du sort :"
L["Add"]                                                                  = "Ajouter"
L["unknown spell ID %d"]                                                  = "ID de sort inconnu %d"
L["Whitelist forces a debuff to show even if it isn't boss-cast (e.g. M+ trash debuffs). Blacklist hides a debuff even if it is boss-cast. Both keyed by spell ID."] =
    "La whitelist force un debuff à s'afficher même s'il n'est pas lancé par un boss (ex : trash en M+). La blacklist masque un debuff même s'il est lancé par un boss. Les deux sont indexées par ID de sort."
L["Only boss-cast HARMFUL auras are shown by default. Use the Filters tab to whitelist M+ debuffs or blacklist noise."] =
    "Par défaut, seules les auras HARMFUL lancées par les boss sont affichées. Utilise l'onglet Filtres pour whitelister les debuffs M+ ou blacklister le bruit."

-- Filters: tank inclusion section
L["Tank detection"]                            = "Détection des tanks"
L["Detection mode"]                            = "Mode de détection"
L["Group role (auto-set from spec)"]           = "Rôle de groupe (auto via spé)"
L["Only /maintank (raid)"]                     = "/maintank uniquement (raid)"
L["Either role or /maintank"]                  = "Rôle ou /maintank"
L["Force-include tanks"]                       = "Inclure de force comme tank"
L["Always include me if my spec is tank"]      = "Toujours m'inclure si ma spé est tank"
L["Always include these players (added on top of detected tanks):"] =
    "Toujours inclure ces joueurs (en plus des tanks détectés) :"
L["Always include these players (added on top of RL-assigned tanks):"] =
    "Toujours inclure ces joueurs (en plus des tanks assignés par le RL) :"
L["Player name:"]                              = "Nom du joueur :"
L["Debuff filters"]                            = "Filtres de debuffs"
L["Filter mode"]                               = "Mode de filtre"
L["All harmful debuffs"]                       = "Tous les debuffs nocifs"
L["Boss-cast only"]                            = "Lancés par un boss uniquement"
L["Whitelist only"]                            = "Whitelist uniquement"
L["Whitelist always shows regardless of mode. Blacklist always hides."] =
    "La whitelist affiche toujours peu importe le mode. La blacklist masque toujours."
L["Whitelist forces a debuff to show even if it isn't boss-cast (e.g. M+ trash debuffs). Blacklist hides a debuff even if it is boss-cast."] =
    "La whitelist force un debuff à s'afficher même s'il n'est pas lancé par un boss (ex : trash en M+). La blacklist masque un debuff même s'il est lancé par un boss."

-- Window
L["TankWatch — Options"] = "TankWatch — Options"

-- Layout
L["Unlock / Lock Mover"] = "Déverrouiller / Verrouiller"
L["Test:"]               = "Test :"
L["Off"]                 = "Off"
L["Enable"]              = "Activé"
L["Show in"]               = "Afficher en"
L["Raid only"]             = "Raid uniquement"
L["Raid or 5-man"]         = "Raid ou groupe 5"
L["Always (incl. solo)"]   = "Toujours (incl. solo)"
L["Anchor"]              = "Ancrage"
L["Grow Direction"]      = "Direction"
L["Down"]                = "Bas"
L["Up"]                  = "Haut"
L["Offset X"]            = "Décalage X"
L["Offset Y"]            = "Décalage Y"
L["Width"]               = "Largeur"
L["Height"]              = "Hauteur"
L["Spacing"]             = "Espacement"
L["Scale"]               = "Échelle"

-- 9-point anchor
L["Top Left"]     = "Haut gauche"
L["Top"]          = "Haut"
L["Top Right"]    = "Haut droite"
L["Left"]         = "Gauche"
L["Center"]       = "Centre"
L["Right"]        = "Droite"
L["Bottom Left"]  = "Bas gauche"
L["Bottom"]       = "Bas"
L["Bottom Right"] = "Bas droite"

-- Bars
L["Health Texture"]      = "Texture de la barre"
L["Health Color"]        = "Couleur de la vie"
L["Class color"]         = "Couleur de classe"
L["Reaction (green)"]    = "Réaction (vert)"
L["Custom static"]       = "Personnalisée"
L["Custom color:"]       = "Couleur personnalisée :"
L["HP background alpha"] = "Alpha fond vie"

-- Text
L["Show Name"]               = "Afficher le nom"
L["Name Position"]           = "Position du nom"
L["Name Offset X"]           = "Décalage X nom"
L["Name Offset Y"]           = "Décalage Y nom"
L["Name max length (0=off)"] = "Longueur max du nom (0=off)"
L["Show Health Text"]        = "Afficher le texte de vie"
L["HP text position"]        = "Position du texte de vie"
L["HP text Offset X"]        = "Décalage X texte de vie"
L["HP text Offset Y"]        = "Décalage Y texte de vie"
L["HP format"]               = "Format de la vie"
L["Percent (50%)"]           = "Pourcentage (50%)"
L["Current (50M)"]           = "Actuel (50M)"
L["Current + Percent"]       = "Actuel + pourcentage"
L["Current / Max"]           = "Actuel / Max"

-- Font
L["Font (applies to all text)"] = "Police (s'applique à tous les textes)"
L["Font"]          = "Police"
L["Font Size"]     = "Taille de police"
L["Outline"]       = "Contour"
L["None"]          = "Aucun"
L["Thick Outline"] = "Contour épais"

-- Auras
L["Show Auras"]              = "Afficher les auras"
L["Only debuffs with stacks"] = "Uniquement les debuffs avec stacks"
L["Only boss-cast HARMFUL auras are shown. The stack count is rendered big in the icon center."] =
    "Seules les auras HARMFUL lancées par les boss sont affichées. Le nombre de stacks est rendu en gros au centre de l'icône."
L["Max Count"]   = "Nombre max"
L["Size"]        = "Taille"
L["Grow X"]      = "Sens horizontal"

-- Aura text positioning (stack / timer)
L["Stack count"]            = "Stacks"
L["Stack anchor"]           = "Ancrage stacks"
L["Stack size (0 = auto)"]  = "Taille stacks (0 = auto)"
L["Stack offset X"]         = "Décalage X stacks"
L["Stack offset Y"]         = "Décalage Y stacks"
L["Timer"]                  = "Timer"
L["Show timer"]             = "Afficher le timer"
L["Timer anchor"]           = "Ancrage timer"
L["Timer size (0 = auto)"]  = "Taille timer (0 = auto)"
L["Timer offset X"]         = "Décalage X timer"
L["Timer offset Y"]         = "Décalage Y timer"

-- About
L["See every tank in your group with their boss-cast debuffs and stack counts."] =
    "Voir tous les tanks de votre groupe avec leurs debuffs lancés par les boss et le nombre de stacks."
L["Author:"]        = "Auteur :"
L["Slash commands"] = "Commandes slash"
L["GitHub repo:"]   = "Dépôt GitHub :"
L["Report a bug:"]  = "Signaler un problème :"
L["Click a field above and Ctrl+C to copy."] = "Clique un champ ci-dessus puis Ctrl+C pour copier."
L["open options"]   = "ouvrir les options"

-- Blizzard settings
L["Tank visibility with boss-cast debuff stack tracking — v%s\nClick the button below to open the TankWatch configuration panel."] =
    "Visibilité des tanks avec suivi des stacks des debuffs lancés par les boss — v%s\nCliquez sur le bouton ci-dessous pour ouvrir le panneau de configuration de TankWatch."
L["Open TankWatch options"]                  = "Ouvrir les options de TankWatch"
L["You can also use the slash command: /tw"] = "Vous pouvez aussi utiliser la commande : /tw"

-- Slash help
L["commands:"]                  = "commandes :"
L["combat lockdown"]            = "verrou de combat actif"
L["toggle mover"]               = "afficher / cacher le mover"
L["simulate N tanks (0-8)"]     = "simuler N tanks (0 à 8)"
L["reset all settings + reload"] = "réinitialiser et recharger l'UI"
L["print roster role/maintank info"]        = "afficher le rôle et /maintank de chaque membre"
L["roster diagnostic:"]                     = "diagnostic du roster :"
L["print every HARMFUL aura on each tank unit"] = "lister tous les debuffs HARMFUL sur chaque tank"
L["aura diagnostic:"]                       = "diagnostic des auras :"
L["long alias for /tw"]                     = "alias long pour /tw"
L["|cff00ff96TankWatch|r v%s loaded — type |cffffff00/tw|r for options"] =
    "|cff00ff96TankWatch|r v%s chargé — tapez |cffffff00/tw|r pour les options"
