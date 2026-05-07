local addonName, TW = ...

if GetLocale() ~= "frFR" then return end

local L = TW.L

-- Tabs
L["Layout"] = "Disposition"
L["Bars"]   = "Barres"
L["Text"]   = "Texte"
L["Auras"]  = "Auras"
L["About"]  = "À propos"

-- Window
L["TankWatch — Options"] = "TankWatch — Options"

-- Layout
L["Unlock / Lock Mover"] = "Déverrouiller / Verrouiller"
L["Test:"]               = "Test :"
L["Off"]                 = "Off"
L["Enable"]              = "Activé"
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

-- About
L["See every tank in your group with their boss-cast debuffs and stack counts."] =
    "Voir tous les tanks de votre groupe avec leurs debuffs lancés par les boss et le nombre de stacks."
L["Author:"]        = "Auteur :"
L["Slash commands"] = "Commandes slash"
L["open options"]   = "ouvrir les options"

-- Blizzard settings
L["Tank visibility with boss-cast debuff stack tracking — v%s\nClick the button below to open the TankWatch configuration panel."] =
    "Visibilité des tanks avec suivi des stacks des debuffs lancés par les boss — v%s\nCliquez sur le bouton ci-dessous pour ouvrir le panneau de configuration de TankWatch."
L["Open TankWatch options"]                  = "Ouvrir les options de TankWatch"
L["You can also use the slash command: /tw"] = "Vous pouvez aussi utiliser la commande : /tw"

-- Slash help
L["commands:"]                  = "commandes :"
L["toggle mover"]               = "afficher / cacher le mover"
L["simulate N tanks (0-8)"]     = "simuler N tanks (0 à 8)"
L["reset all settings + reload"] = "réinitialiser et recharger l'UI"
L["|cff00ff96TankWatch|r v%s loaded — type |cffffff00/tw|r for options"] =
    "|cff00ff96TankWatch|r v%s chargé — tapez |cffffff00/tw|r pour les options"
