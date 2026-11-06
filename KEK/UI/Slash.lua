-- KEK — commandes /kek.
local _, ns = ...
local L = ns.L

local VIEWS = {
  membres = "roster", bande = "roster", fil = "feed", morts = "deaths", shame = "deaths",
  soiree = "session", ["soirée"] = "session", recap = "session", course = "race", atelier = "craft",
  besoins = "craft", options = "settings", reglages = "settings", ["réglages"] = "settings",
}

local HELP = {
  L["/kek — ouvrir ou fermer la fenêtre"],
  L["/kek code <mot> — rejoindre une bande (vide : passer par la guilde)"],
  L["/kek ajouter <perso> — retrouver un ami qui n'apparaît pas"],
  L["/kek besoin [quantité] <objet> [: note] — dire à la bande ce dont tu as besoin"],
  L["/kek besoin [fois] composants <recette> — demander ce qui te manque pour une recette"],
  L["/kek fil | morts | soiree | course | atelier | options — aller à une vue"],
  L["/kek test — afficher des notifications d'exemple"],
  L["/kek autotest — vérifier KEK dans ton jeu et obtenir un rapport à partager"],
  L["/kek deplacer — déplacer les notifications"],
  L["/kek reset — tout effacer"],
}

SLASH_KEK1 = "/kek"
SlashCmdList.KEK = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    ns.Window:Toggle()
  elseif cmd == "code" then
    local code = (rest or ""):lower():gsub("[^%w]", "")
    ns.Comm:SetCode(code)
    ns.Print(code ~= "" and string.format(L["bande « %s » : recherche de tes amis…"], code) or L["passage par la guilde."])
  elseif cmd == "ajouter" or cmd == "add" then
    if rest == "" then
      ns.Print(L["indique le nom d'un perso : /kek ajouter Gromgar"])
    else
      ns.Comm:AddPeer(rest)
    end
  elseif cmd == "autotest" or cmd == "test-jeu" then
    ns.Print(L["autotest en cours (5 secondes)…"])
    ns.Autotest:Run()
  elseif cmd == "rapport" then
    if not ns.Autotest:ShowLast() then ns.Print(L["aucun rapport : tape /kek autotest."]) end
  elseif cmd == "besoin" or cmd == "need" then
    if rest == "" then
      ns.db.ui.craftTab = "needs"
      ns.Window:Open("craft")
      return
    end
    -- « 10 Viande de coyote : pour la cuisine », ou avec un lien d'objet (Maj+clic)
    local qty, item = rest:match("^(%d+)%s*[xX]?%s+(.+)$")
    item = item or rest
    -- « /kek besoin 5 composants Ragoût de coyote » : ce qui te manque pour fabriquer la recette 5 fois
    local recipeText = item:match("^[Cc]ompos%a*%s+(.+)$")
    if recipeText then
      local recipe = ns.Craft:FindRecipe(recipeText)
      if not recipe then
        ns.Print(string.format(L["recette « %s » inconnue : ouvre une fois ta fenêtre de métier pour que KEK mémorise ses composants."], recipeText))
      else
        ns.Window.byId.craft:RequestReagents(recipe, tonumber(qty) or 1)
      end
      return
    end
    local note
    local link = item:match("(|c%x+|Hitem:.-|h.-|h|r)")
    if link then
      note = item:sub(item:find(link, 1, true) + #link):match("^%s*[:%-]?%s*(.-)%s*$")
      item = link
    else
      local name, n = item:match("^(.-)%s+:%s*(.+)$")
      if name then item, note = name, n end
    end
    local ok, need, fresh = ns.Craft:AddNeed(item, tonumber(qty) or 1, note or "")
    if ok then
      local label = (need.k or need.s or "?") .. ((need.q or 1) > 1 and (" ×" .. need.q) or "")
      ns.Print(string.format(fresh and L["besoin ajouté : %s. La bande est prévenue."] or L["besoin mis à jour : %s."], label))
    else
      ns.Print(L["indique un objet : /kek besoin 10 Viande de coyote : pour la cuisine"])
    end
  elseif cmd == "diag" then
    local diag = ns.db.diag or {}
    ns.Print(string.format(L["version %s · %s · %d action(s) bloquée(s) enregistrée(s)"], ns.VERSION, ns.Comm:StatusText(), #diag))
    for i = 1, math.min(5, #diag) do
      local d = diag[i]
      ns.Print(string.format("%s %s · %s · %s", ns.U.ShortDate(d.t), ns.U.Clock(d.t), tostring(d.f), tostring(d.v)))
    end
  elseif cmd == "test" then
    ns.Toasts:Demo()
  elseif cmd == "deplacer" or cmd == "déplacer" then
    ns.Toasts:Unlock()
  elseif cmd == "reset" then
    ns.UI.Confirm(L["Effacer toutes les données de KEK et recharger l'interface ?"], function() ns:ResetAll() end)
  elseif VIEWS[cmd] then
    ns.Window:Open(VIEWS[cmd])
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end

ns:On("READY", function()
  if not ns.db.ui.welcomed then
    ns.db.ui.welcomed = true
    ns.Print(L["installé ! Tape /kek ou clique sur le feu de camp près de la minicarte."])
  end
end)
