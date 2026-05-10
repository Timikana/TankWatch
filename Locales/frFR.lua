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
L["Profile '%s' already exists. Overwrite?"]     = "Le profil '%s' existe déjà. Écraser ?"
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
L["Open BossWatch options"] = "Ouvrir les options BossWatch"

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
L["Background color:"]      = "Couleur du fond :"
L["Use textured background"] = "Utiliser une texture de fond"
L["Background texture"]     = "Texture du fond"
L["Background color mode"]  = "Mode couleur du fond"
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
L["CurseForge:"]    = "CurseForge :"
L["Wago:"]          = "Wago :"
L["Discord:"]       = "Discord :"
L["Discord (support / bugs / suggestions):"] = "Discord (support / bugs / suggestions) :"
L["Click a field above and Ctrl+C to copy."] = "Clique un champ ci-dessus puis Ctrl+C pour copier."
L["open options"]   = "ouvrir les options"

-- Blizzard settings
L["Tank visibility with boss-cast debuff stack tracking — v%s\nClick the button below to open the TankWatch configuration panel."] =
    "Visibilité des tanks avec suivi des stacks des debuffs lancés par les boss — v%s\nCliquez sur le bouton ci-dessous pour ouvrir le panneau de configuration de TankWatch."
L["Open TankWatch options"]                  = "Ouvrir les options de TankWatch"
L["You can also use the slash command: /tankw"] = "Vous pouvez aussi utiliser la commande : /tankw"

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
L["long alias for /tankw"]                     = "alias long pour /tankw"
L["|cff00ff96TankWatch|r v%s loaded — type |cffffff00/tankw|r for options"] =
    "|cff00ff96TankWatch|r v%s chargé — tapez |cffffff00/tankw|r pour les options"

-- Section headers
L["General"]    = "Général"
L["Position"]   = "Position"
L["Dimensions"] = "Dimensions"
L["Textures"]   = "Textures"
L["Background"] = "Fond"
L["Range Fade"] = "Estompage hors de portée"
L["Absorb shield"]      = "Bouclier d'absorption"
L["Show absorb shield"] = "Afficher le bouclier d'absorption"
L["Absorb color"]       = "Couleur du bouclier"
L["Overlay a translucent shield bar showing the tank's current absorb amount."] =
    "Affiche une barre translucide de bouclier représentant le montant d'absorption actuel du tank."
L["Color and alpha of the absorb shield overlay."] =
    "Couleur et transparence du bouclier d'absorption."
L["Absorb texture"] = "Texture du bouclier"
L["Status bar texture used for the absorb shield overlay."] =
    "Texture de la barre utilisée pour le bouclier d'absorption."
L["Absorb side"] = "Côté du bouclier"
L["Which side of the bar the shield grows from."] =
    "Côté de la barre où le bouclier se remplit (gauche ou droite)."

-- Power bar (mana / rage / énergie / puissance runique / fureur / souffrance)
L["Power bar"]               = "Barre de ressource"
L["Show power bar"]          = "Afficher la barre de ressource"
L["Power bar height"]        = "Hauteur de la barre"
L["Power texture"]           = "Texture"
L["Power color mode"]        = "Mode de couleur"
L["By power type"]           = "Selon le type de ressource"
L["Power static color"]      = "Couleur statique"
L["Display a thin power bar (rage / mana / runic power / etc.) below the health bar."] =
    "Affiche une barre fine de ressource (mana, rage, énergie, puissance runique, fureur, souffrance...) sous la barre de vie."
L["Height in pixels of the power bar. 0 hides the bar entirely."] =
    "Hauteur en pixels de la barre. 0 cache la barre."
L["Status bar texture used for the power bar."] =
    "Texture utilisée pour la barre de ressource."
L["How the power bar is colored: automatic by power type (rage = red, mana = blue, etc.) or a fixed custom color."] =
    "Coloration de la barre : automatique selon le type (rage = rouge, mana = bleu, énergie = jaune, etc.) ou couleur fixe personnalisée."

-- Power text
L["Power Text"]              = "Texte de ressource"
L["Show Power Text"]         = "Afficher le texte de ressource"
L["Power text position"]     = "Position du texte"
L["Power text Offset X"]     = "Décalage X du texte"
L["Power text Offset Y"]     = "Décalage Y du texte"
L["Power format"]            = "Format de la ressource"
L["Display the power value (rage / mana / etc.) as text."] =
    "Affiche la valeur de la ressource (mana, rage, énergie...) en texte."
L["Anchor point of the power text on its bar."] =
    "Point d'ancrage du texte de ressource sur sa barre."
L["Horizontal offset of the power text."] = "Décalage horizontal du texte de ressource."
L["Vertical offset of the power text."]   = "Décalage vertical du texte de ressource."
L["Format of the power value: current value, or current / max."] =
    "Format : valeur actuelle, ou actuelle / max."

-- Compact mode + presets
L["Compact mode (debuffs only)"]      = "Mode compact (debuffs uniquement)"
L["Show class icon"]                  = "Afficher l'icône de classe"
L["Hide health/power/absorb bars and texts. Only the debuff icons remain (with the class icon if enabled below)."] =
    "Masque les barres de vie/ressource/absorption et les textes. Seules les icônes de debuff restent (avec l'icône de classe si l'option ci-dessous est cochée)."
L["Show a small class icon glued to the left of the debuff row. Only available in compact mode."] =
    "Affiche une petite icône de classe collée à gauche de la rangée de debuffs. Disponible uniquement en mode compact."

L["Presets"]                 = "Préréglages"
L["Apply"]                   = "Appliquer"
L["Apply preset (creates a new profile, original preserved)"] =
    "Appliquer un préréglage (crée un nouveau profil, l'original reste intact)"
L["Full — bars + auras (default)"]            = "Complet — barres + auras (défaut)"
L["Compact — class icon + auras only"]        = "Compact — icône de classe + auras uniquement"
L["Minimal — auras only (no class icon)"]     = "Minimal — auras uniquement (pas d'icône)"
L["Pre-configured display modes. Applying creates a new profile copying your current one with the preset's display settings overlaid — your filters, position, fonts and colors are preserved."] =
    "Modes d'affichage pré-configurés. Appliquer crée un nouveau profil en copiant l'actuel avec les réglages d'affichage du préréglage par-dessus — tes filtres, position, polices et couleurs sont préservés."
L["Apply the selected preset by creating a new profile."] =
    "Applique le préréglage sélectionné en créant un nouveau profil."
L["New profile name (will copy '%s' and apply the preset):"] =
    "Nom du nouveau profil (copie '%s' et applique le préréglage) :"
L["preset applied as new profile '%s'"] = "préréglage appliqué dans le nouveau profil '%s'"
L["Name"]       = "Nom"
L["Health Text"] = "Texte de vie"
L["Display"]    = "Affichage"
L["Color mode"] = "Mode de couleur"
L["Static color"]      = "Couleur statique"
L["Background color"]  = "Couleur de fond"
L["Panel opacity"]     = "Opacité du panneau"
L["Health bar"]        = "Barre de vie"
L["Icons"]             = "Icônes"
L["Options window"]    = "Fenêtre d'options"
L["alias"]             = "alias"

-- Layout tooltips
L["Toggle a draggable handle on the tank container so you can move it on screen."] =
    "Affiche une poignée pour déplacer le conteneur des tanks à l'écran."
L["Stop the simulation."] = "Arrêter la simulation."
L["Simulate %d tank frame(s) with fake debuffs and HP."] =
    "Simule %d cadre(s) de tank avec des debuffs et PV factices."
L["Master switch for the addon. When off, TankWatch frames stay hidden."] =
    "Interrupteur principal de l'addon. Désactivé, les cadres TankWatch restent cachés."
L["Show a minimap button. Left-click: options, right-click: toggle mover."] =
    "Affiche un bouton sur la minimap. Clic gauche : options, clic droit : mover."
L["When TankWatch frames are visible: only in raid, in any group, or always."] =
    "Quand TankWatch s'affiche : seulement en raid, en groupe quelconque, ou toujours."
L["Opacity of this options window. Saved account-wide."] =
    "Opacité de cette fenêtre d'options. Enregistré pour tout le compte."
L["Anchor point on the screen used as origin for the X/Y offsets."] =
    "Point d'ancrage à l'écran utilisé comme origine pour les décalages X/Y."
L["Direction additional tank frames stack from the first one."] =
    "Direction dans laquelle les cadres de tank supplémentaires s'empilent."
L["Horizontal offset from the anchor point."] = "Décalage horizontal depuis le point d'ancrage."
L["Vertical offset from the anchor point."]   = "Décalage vertical depuis le point d'ancrage."
L["Width of each tank frame in pixels."]      = "Largeur de chaque cadre de tank, en pixels."
L["Height of each tank frame in pixels."]     = "Hauteur de chaque cadre de tank, en pixels."
L["Vertical gap between stacked tank frames."] = "Espace vertical entre les cadres de tank empilés."
L["Overall scale of all tank frames."]        = "Échelle globale de tous les cadres de tank."

-- Bars tooltips
L["Status bar texture used for the tank health bar."] =
    "Texture de la barre de progression utilisée pour la barre de vie."
L["How the health bar is colored: by class, fixed green, or one custom color."] =
    "Coloration de la barre de vie : par classe, vert fixe, ou couleur personnalisée."
L["Fixed color used when the mode above is set to 'Custom static'."] =
    "Couleur fixe utilisée quand le mode ci-dessus est sur 'Personnalisée'."
L["Color used behind the bar fill: a static color or the tank's class color."] =
    "Couleur utilisée derrière le remplissage de la barre : couleur fixe ou couleur de classe du tank."
L["Custom color used for the health bar background."] =
    "Couleur personnalisée pour le fond de la barre de vie."
L["Use a status-bar texture for the background (otherwise: flat color)."] =
    "Utilise une texture de barre pour le fond (sinon : couleur unie)."
L["Opacity of the empty (un-filled) part of the health bar."] =
    "Opacité de la partie vide (non remplie) de la barre de vie."
L["Texture used for the health bar background when the option above is enabled."] =
    "Texture utilisée pour le fond de la barre de vie quand l'option ci-dessus est activée."
L["Reduce the alpha of tank frames whose unit is out of 40-yard range."] =
    "Réduit l'alpha des cadres dont le tank est hors de portée (40m)."
L["Alpha applied to out-of-range tank frames."] =
    "Alpha appliqué aux cadres des tanks hors de portée."

-- Text tooltips
L["Show the tank's name on the frame."] = "Affiche le nom du tank sur le cadre."
L["Anchor point where the name is attached on the frame."] =
    "Point d'ancrage où le nom est attaché sur le cadre."
L["Horizontal offset of the name from its anchor."] = "Décalage horizontal du nom depuis son ancrage."
L["Vertical offset of the name from its anchor."]   = "Décalage vertical du nom depuis son ancrage."
L["Trim the name after this many characters. 0 disables trimming."] =
    "Tronque le nom au-delà de ce nombre de caractères. 0 désactive."
L["Display HP value as text on the health bar."] =
    "Affiche la valeur de PV en texte sur la barre de vie."
L["Anchor point of the HP text on the bar."] = "Point d'ancrage du texte de vie sur la barre."
L["Horizontal offset of the HP text."] = "Décalage horizontal du texte de vie."
L["Vertical offset of the HP text."]   = "Décalage vertical du texte de vie."
L["Format of the HP value. Percent is unavailable in 12.0 (secret-tagged HP)."] =
    "Format de la valeur de vie. Le pourcentage est indisponible en 12.0 (PV protégés)."
L["Font used for every text on the tank frames."] =
    "Police utilisée pour tous les textes sur les cadres de tank."
L["Base font size in points."] = "Taille de police de base, en points."
L["Black outline drawn around text for readability."] =
    "Contour noir autour du texte pour la lisibilité."

-- Auras tooltips
L["Show the tank's boss-cast debuffs as icons on the frame."] =
    "Affiche les debuffs lancés par les boss en icônes sur le cadre du tank."
L["Hide debuffs that don't have a stack count (applications == 1)."] =
    "Masque les debuffs qui n'ont pas de stacks (applications == 1)."
L["By default only boss-cast HARMFUL auras show. Use the Filters tab to whitelist M+ debuffs or blacklist noise."] =
    "Par défaut, seuls les debuffs HARMFUL lancés par les boss s'affichent. Utilise l'onglet Filtres pour whitelister les debuffs M+ ou blacklister le bruit."
L["Maximum number of debuff icons shown per tank frame."] =
    "Nombre maximum d'icônes de debuff affichées par cadre de tank."
L["Size of each debuff icon in pixels."] = "Taille de chaque icône de debuff, en pixels."
L["Gap between debuff icons in pixels."] = "Espace entre les icônes de debuff, en pixels."
L["Where the debuff row attaches on the tank frame."] =
    "Où la rangée de debuffs s'attache sur le cadre du tank."
L["Direction icons stack horizontally from the anchor."] =
    "Direction dans laquelle les icônes s'empilent horizontalement depuis l'ancrage."
L["Horizontal offset of the debuff row."] = "Décalage horizontal de la rangée de debuffs."
L["Vertical offset of the debuff row."]   = "Décalage vertical de la rangée de debuffs."
L["Anchor point of the stack-count text on each icon."] =
    "Point d'ancrage du texte de stacks sur chaque icône."
L["Font size for the stack number. 0 auto-scales with icon size."] =
    "Taille de police pour le nombre de stacks. 0 = auto selon la taille de l'icône."
L["Horizontal offset of the stack-count text from its anchor."] =
    "Décalage horizontal du texte de stacks depuis son ancrage."
L["Vertical offset of the stack-count text from its anchor."] =
    "Décalage vertical du texte de stacks depuis son ancrage."
L["Show remaining duration on each debuff icon."] =
    "Affiche la durée restante sur chaque icône de debuff."
L["Anchor point of the timer text on each icon."] =
    "Point d'ancrage du texte de timer sur chaque icône."
L["Font size for the timer text. 0 auto-scales with icon size."] =
    "Taille de police pour le texte de timer. 0 = auto selon la taille de l'icône."
L["Horizontal offset of the timer text from its anchor."] =
    "Décalage horizontal du texte de timer depuis son ancrage."
L["Vertical offset of the timer text from its anchor."] =
    "Décalage vertical du texte de timer depuis son ancrage."

-- Filters tooltips
L["How TankWatch decides who counts as a tank in your group."] =
    "Comment TankWatch détermine qui compte comme tank dans le groupe."
L["Add yourself to the tank list when your active spec role is TANK, even if the raid leader didn't /maintank you."] =
    "T'ajoute à la liste des tanks si ta spé active a le rôle TANK, même si le RL ne t'a pas /maintank."
L["Which debuffs to show: every HARMFUL aura, only those cast by bosses, or only spells in your whitelist."] =
    "Quels debuffs afficher : toutes les auras HARMFUL, uniquement celles lancées par les boss, ou uniquement les sorts de la whitelist."

-- Profiles tooltips
L["Create a new profile copying the currently active settings."] =
    "Crée un nouveau profil en copiant les réglages actuellement actifs."
L["Reset the active profile back to default values."] =
    "Réinitialise le profil actif aux valeurs par défaut."
L["Delete the active profile (Default cannot be deleted)."] =
    "Supprime le profil actif (Default ne peut pas être supprimé)."
L["Re-build the export string from the current profile values."] =
    "Reconstruit la chaîne d'export à partir des valeurs du profil actuel."
L["Highlight the export text so you can Ctrl+C to copy it."] =
    "Surligne le texte d'export pour pouvoir faire Ctrl+C."
L["Decode the export string and create a new profile from it."] =
    "Décode la chaîne d'export et crée un nouveau profil à partir d'elle."

-- Color picker
L["Click to choose a color"] = "Cliquer pour choisir une couleur"

-- About
L["Click a URL to select it, then Ctrl+C to copy."] =
    "Clique une URL pour la sélectionner, puis Ctrl+C pour copier."
L["Drag to resize"] = "Glisser pour redimensionner"
L["Right-click to reset size"] = "Clic droit : réinitialiser la taille"
L["Profile"] = "Profil"
L["tanks"]   = "tanks"
L["Default: "] = "Défaut : "
L["no match"]  = "aucun résultat"
L["Click to collapse/expand this section."] = "Cliquer pour replier/déplier cette section."
L["Reset this section to default values."]  = "Réinitialiser cette section aux valeurs par défaut."
L["Search options…"]  = "Rechercher des options…"
L["Filter the panel: type any keyword from a label or tooltip. Sections without a match are auto-collapsed."] =
    "Filtre le panneau : tape un mot-clé d'un label ou d'une infobulle. Les sections sans correspondance sont repliées."
L["Clear the search."] = "Effacer la recherche."
L["No options match your search."] = "Aucune option ne correspond à ta recherche."
L["Classic build — UI not fully tested. Report issues on GitHub / Discord."] =
    "Build Classic — UI pas complètement testée. Remonte les bugs sur GitHub / Discord."
L["Changelog"] = "Nouveautés"
L["Full GitHub history: https://github.com/Timikana/TankWatch/releases"] =
    "Historique complet sur GitHub : https://github.com/Timikana/TankWatch/releases"
L["CHANGELOG_BODY"] = [[
## v1.4.2

|cffffd700Nouveau|r — Commande slash renommée : /tankw (alias /tankwatch)
- /tw était trop court et risquait de coller avec d'autres addons ;
  même convention que /bossw côté BossWatch.

|cffffd700Nouveau|r — Onglets sur plusieurs rangées
- Quand le panneau est trop étroit pour caser tous les onglets sur
  une seule rangée, la barre wrap sur plusieurs rangées. Les rangées
  du bas passent au-dessus de celles du haut pour pas que les bords
  soient clippés.

|cffffd700Nouveau|r — Support MoP Classic 5.5
- TankWatch tourne maintenant sur Mists of Pandaria Classic via un .toc
  séparé (Interface 50500). Un seul zip CurseForge sert retail et Classic.
- C_UnitAuras n'est pas dispo sur Classic ; le scan des debuffs utilise
  alors l'API legacy UnitAura — l'affichage des debuffs boss fonctionne
  pareil sur les deux clients.
- C_AddOns.GetAddOnMetadata / IsAddOnLoaded retombent sur les globales
  legacy pour que le numéro de version et l'onglet BossWatch frère
  fonctionnent aussi sur Classic.

## v1.4.1

|cffffd700Nouveau|r — Onglets latéraux d'addon
- Onglets discrets sur le bord gauche du panneau pour basculer entre
  TankWatch et BossWatch en un clic.
- Le second onglet n'apparaît que si l'addon frère est installé aussi.
- Style moderne : fond verre sombre, liseré doré sur l'addon actif,
  halo au survol.

## v1.4.0

|cffffd700Nouveau|r — Panneau d'options moderne et responsive
- Poignée de redimensionnement en bas à droite ; taille et position sauvegardées par compte.
- Clic droit sur la poignée pour remettre le panneau à sa taille par défaut (720×620).
- Mémoire de défilement par onglet : chaque onglet retient son offset.
- Fondu subtil au changement d'onglet ; le pied de page affiche le profil actif + le nombre de tanks.

|cffffd700Nouveau|r — Sections repliables
- Chaque section a un chevron replier/déplier ET toute la barre d'en-tête
  (titre + ligne dorée) est cliquable pour basculer.
- Bouton de réinitialisation par section (icône refresh à droite) qui restaure les défauts
  de cette section uniquement — tes autres réglages restent intacts.
- L'état replié est conservé entre les reloads.

|cffffd700Nouveau|r — Barre de recherche (en haut à droite)
- Tape un mot-clé d'un libellé ou d'une infobulle ; les widgets correspondants
  sont rassemblés sur une page de résultats avec un fil d'Ariane vers leur onglet/section.
- Les onglets affichent un compteur de hits pendant une recherche active.
- Effacer la recherche replace tout dans son onglet d'origine.

|cffffd700Nouveau|r — Disposition auto-flow
- Les widgets de la colonne droite (menus, sliders) suivent désormais le bord droit
  quand tu élargis le panneau, au lieu de laisser un trou qui s'agrandit.

|cffffd700Nouveau|r — Onglet Nouveautés
- Cet onglet ! Blocs par version avec un label localisé
  (Nouveautés / Neuerungen / Novedades / Novità / Novidades / Что нового /
  변경 사항 / 更新日志 / 更新日誌).

|cffffd700Amélioré|r
- Chaînes de sections + collapse traduites dans 9 langues.
- Boutons de test chaînés entre eux pour rester groupés à toute largeur de panneau.
- Bouton "Off" élargi pour que son texte ne déborde pas sur le bouton "1".
- Espacement plus aéré entre les sections (28px).

## v1.3.0

|cffffd700Nouveau|r — Mode compact (devient le défaut pour les nouvelles installations)
- Icône de classe + débuffs lancés par les boss uniquement. PV/ressource/bouclier/nom tous masqués.
- Bascule dans Disposition > Général. Sous-option pour masquer l'icône de classe (debuffs uniquement).

|cffffd700Nouveau|r — Préréglages d'affichage (onglet Profils)
- Menu déroulant Complet / Compact / Minimal.
- Non destructif : clone ton profil actuel et applique les flags d'affichage du préréglage par-dessus.

|cffffd700Nouveau|r — Barre de ressource
- Barre optionnelle (rage / mana / puissance runique / énergie / fureur / souffrance) sous les PV.
- Couleur auto par type de ressource ou couleur perso, texture LSM.

|cffffd700Amélioré|r — Mode test
- Les PV et boucliers s'animent, les durées de débuffs cyclent, les stacks changent en direct,
  les barres de ressource tickent à des vitesses différentes selon le type.

|cffffd700Corrigé|r
- Suppression des menus de format PV/ressource peu fiables (problèmes de valeurs secrètes 12.0).
- Le texte PV/nom passe toujours au-dessus du bouclier d'absorption.
- La poignée de déplacement flotte au-dessus des cadres pour rester saisissable.

## v1.2.2

- Réorganisation du panneau d'options : Estompage hors de portée dans Disposition,
  fusion de la texture/couleur de la barre PV, fusion Aura Taille+Disposition en Icônes,
  curseur d'opacité du panneau déplacé dans À propos > Fenêtre d'options.
- 552 nouvelles traductions sur 8 langues (deDE/esES/itIT/ptBR/ruRU/koKR/zhCN/zhTW).
- Les infobulles apparaissent aussi sur les sous-contrôles des sliders (steppers, curseur).

## v1.2.1

- Ajout du lien d'invitation Discord dans l'onglet À propos.

## v1.2.0

|cffffd700Nouveau|r — Bouclier d'absorption
- Barre de bouclier translucide superposée à la barre PV (Frappe de mort, Mot de gloire, etc.).
- Bleu ciel par défaut, entièrement personnalisable, texture LSM, côté inversable.

|cffffd700Amélioré|r
- La poignée de déplacement flotte au-dessus des cadres de tank.
- Espacement plus serré dans l'onglet Barres (plus de chevauchement entre l'aperçu de texture et le menu côté).

|cffffd700Corrigé|r
- Suppression des formats PV Pourcent / Actuel+Pourcent — pas fiables sur les membres du groupe en 12.0.

|cffffd700Empaquetage|r
- Toutes les libs embarquées (LibStub, CallbackHandler, LibSharedMedia, LibDataBroker)
  apparaissent dans la liste "Bibliothèques embarquées" de CurseForge avec leurs bonnes versions.

## v1.1.5

- Dialogue de confirmation d'écrasement à l'import traduit en 9 langues.

## v1.1.4

- Importer un profil dont le nom existe déjà demande désormais
  "Le profil 'X' existe déjà. Écraser ?".

## v1.1.3

- Correction du portrait vert sur certaines configs (le logo s'affiche désormais correctement).

## v1.1.2

- logo.png inclus dans le paquet pour que l'icône portrait s'affiche depuis CurseForge.

## v1.1.1

- Correction d'un crash sur la boîte de dialogue de nom de profil (Nouveau / Importer).

## v1.1.0

|cffffd700Nouveau|r — Panneau d'options moderne
- Refonte complète avec le template moderne de Blizzard.
- ÉCHAP ferme le panneau.
- Opacité ajustable, infobulles complètes sur tous les contrôles.
- Séparateurs dorés, défilement fluide sur les pages longues.
- Liens CurseForge et Wago.io dans À propos.

## v1.0.4

- Apparaît automatiquement dans Titan Panel / ChocolateBar via un launcher LibDataBroker.
- Badge "NEW" sur les options fraîchement ajoutées (s'efface au premier survol/clic).
- 8 nouvelles ébauches de locales (deDE/esES/itIT/ptBR/ruRU/koKR/zhCN/zhTW).

## v1.0.3

- Sortie sur Wago.io en complément de CurseForge.

## v1.0.2

- Personnalisation du fond (couleur/texture, couleur perso ou de classe, alpha).
- Clic droit pendant le déplacement verrouille la position.

## v1.0.1

- Correction d'un problème critique qui pouvait empêcher de cliquer sur des objets de sac
  quand TankWatch était chargé.
- Le mover affiche désormais la taille réelle du contenu visible.

## v1.0.0

- Première version publique sur CurseForge.
- Détection des tanks (rôle raid / /maintank / 5-man / solo).
- Icônes de débuff lancés par les boss avec |cffffd700le compteur de stacks affiché ÉNORME au
  centre de l'icône|r — la fonctionnalité phare.
- Whitelist / blacklist par ID de sort (parfait pour les débuffs de trash M+).
- Profils par perso avec export / import.
]]
L["Font (applies to all text)"] = "Police (s'applique à tous les textes)"
