-- KEK — page « KEK » dans le menu Options du jeu (onglet AddOns), avec les contrôles natifs.
--
-- Le code de la bande, le pseudo et l'ajout d'amis restent dans la fenêtre de KEK : le menu Options
-- n'a pas de champ de texte. Les deux endroits lisent et écrivent les mêmes réglages.
-- Tout passe par les fonctions officielles (Settings.*). Si elles ne répondent pas comme prévu,
-- KEK se replie sur une page simple avec un bouton qui ouvre ses réglages : jamais d'erreur.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local Options = ns:NewModule("Options", 85)

local S -- l'API Settings du jeu

local ALERTS = {
  { "level", L["Niveaux"], L["Un ami monte de niveau."] },
  { "loot", L["Butin"], L["Un ami trouve un objet rare ou épique."] },
  { "death", L["Morts"], L["Un ami meurt (et le Hall of Shame s'en souviendra)."] },
  { "boss", L["Boss vaincus"], L["Un ami vient à bout d'un boss."] },
  { "skill", L["Paliers de métier"], L["Un ami atteint 75, 150, 225 ou 300 dans un métier."] },
  { "presence", L["Connexions"], L["Un ami se connecte ou se déconnecte."] },
  { "need", L["Besoins"], L["Un ami indique un objet dont il a besoin (et KEK te dit si tu l'as)."] },
}

-- Ouvre la fenêtre de KEK par-dessus le menu Options (sans fermer celui-ci).
local function openKEK(view)
  ns.Window:Open(view)
  if ns.Window.frame then ns.Window.frame:Raise() end
end

-- Un réglage modifié ici doit se voir aussitôt dans la fenêtre de KEK.
local function changed()
  if ns.Window and ns.Window.RequestRefresh then ns.Window:RequestRefresh() end
end

-- ------------------------------------------------------------------ contrôles natifs
local function varType(kind)
  local VT = S.VarType
  return (VT and VT[kind]) or (kind == "Boolean" and "boolean" or "number")
end

local function proxy(category, key, kind, name, default, get, set)
  local setting = S.RegisterProxySetting(category, "KEK_" .. key, varType(kind), name, default, get, set)
  if not setting then error("RegisterProxySetting : aucun réglage créé") end
  return setting
end

local function checkbox(category, key, name, tooltip, default, get, set)
  local setting = proxy(category, key, "Boolean", name, default, get, set)
  local create = S.CreateCheckbox or S.CreateCheckBox
  create(category, setting, tooltip)
end

local function dropdown(category, key, name, tooltip, default, choices, get, set)
  local setting = proxy(category, key, "Number", name, default, get, set)
  local function options()
    local container = S.CreateControlTextContainer()
    for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
    return container:GetData()
  end
  local create = S.CreateDropdown or S.CreateDropDown
  create(category, setting, options, tooltip)
end

local function slider(category, key, name, tooltip, default, lo, hi, step, formatter, get, set)
  local setting = proxy(category, key, "Number", name, default, get, set)
  local opts = S.CreateSliderOptions(lo, hi, step)
  local label = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
  if label and opts.SetLabelFormatter then opts:SetLabelFormatter(label.Right, formatter) end
  S.CreateSlider(category, setting, opts, tooltip)
end

local function button(layout, name, text, onClick, tooltip)
  if not CreateSettingsButtonInitializer then return end
  layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
end

local function header(layout, text)
  if not CreateSettingsListSectionHeaderInitializer then return end
  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

function Options:BuildNative()
  local category, layout = S.RegisterVerticalLayoutCategory("KEK")
  local a = ns.db.alerts

  header(layout, L["Ta bande"])
  button(layout, L["Fenêtre de KEK"], L["Ouvrir"], function() openKEK() end,
    L["Membres, fil, Hall of Shame, soirée, course au 60 et atelier."])
  button(layout, L["Code, pseudo et amis"], L["Modifier"], function() openKEK("settings") end,
    L["Le code secret de la bande, ton pseudo et l'ajout d'un ami se règlent dans la fenêtre de KEK."])

  header(layout, L["Notifications"])
  for _, row in ipairs(ALERTS) do
    local key = row[1]
    checkbox(category, "alert_" .. key, row[2], row[3], true,
      function() return a[key] and true or false end,
      function(v) a[key] = v and true or false; changed() end)
  end
  checkbox(category, "sound", L["Sons"], L["Joue un son avec chaque notification."], true,
    function() return a.sound and true or false end,
    function(v) a.sound = v and true or false; changed() end)
  checkbox(category, "self", L["Mes propres exploits"], L["Affiche aussi une notification pour tes propres exploits."], false,
    function() return a.self and true or false end,
    function(v) a.self = v and true or false; changed() end)
  dropdown(category, "lootQuality", L["Butin à partager"], L["À partir de quelle qualité ton butin est annoncé à la bande."], 4,
    { { 3, L["Rare et +"] }, { 4, L["Épique et +"] } },
    function() return a.lootQuality or 4 end,
    function(v) a.lootQuality = tonumber(v) or 4; changed() end)
  button(layout, L["Aperçu"], L["Tester"], function() ns.Toasts:Demo() end, L["Affiche des notifications d'exemple."])
  button(layout, L["Position des notifications"], L["Déplacer"], function() ns.Toasts:Unlock() end,
    L["Fais glisser les notifications où tu veux, puis valide."])

  header(layout, L["Interface"])
  checkbox(category, "minimap", L["Bouton sur la minicarte"], L["Affiche le bouton de KEK autour de la minicarte."], true,
    function() return ns.MinimapButton:Wanted() end,
    function(v) ns.MinimapButton:SetWanted(v); changed() end)
  slider(category, "scale", L["Taille de la fenêtre"], L["Agrandit ou réduit la fenêtre de KEK."], 1, 0.8, 1.3, 0.05,
    function(v) return string.format("%d %%", math.floor(v * 100 + 0.5)) end,
    function() return ns.db.ui.scale or 1 end,
    function(v) ns.Window:SetScale(tonumber(v) or 1); changed() end)
  button(layout, L["Autotest"], L["Lancer"], function() ns.Autotest:Run() end,
    L["Vérifie KEK dans ton jeu et produit un rapport à copier-coller."])

  -- la page n'apparaît dans le menu qu'une fois entièrement construite
  S.RegisterAddOnCategory(category)
  self.category = category
end

-- ------------------------------------------------------------------ repli : page simple
function Options:BuildSimple()
  local panel = CreateFrame("Frame")
  panel.name = "KEK"
  panel:Hide()
  local logo = panel:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(UI.Media("logo"))
  logo:SetSize(48, 48)
  logo:SetPoint("TOPLEFT", 16, -16)
  local title = UI.Title(panel, 20)
  title:SetPoint("LEFT", logo, "RIGHT", 12, 6)
  title:SetText("KEK")
  local text = UI.Text(panel, 13, C.muted)
  text:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
  text:SetWidth(420)
  text:SetWordWrap(true)
  text:SetJustifyH("LEFT")
  text:SetText(L["Tous les réglages de KEK (bande, notifications, interface) sont dans sa fenêtre."])
  local open = UI.Button(panel, { text = L["Ouvrir les réglages de KEK"], icon = "gear", style = "primary", h = 32,
    onClick = function() openKEK("settings") end })
  open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)

  if S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory then
    local category = S.RegisterCanvasLayoutCategory(panel, "KEK")
    S.RegisterAddOnCategory(category)
    self.category = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  self.simple = panel
end

function Options:OnLogin()
  S = Settings
  local ok = false
  if S and S.RegisterVerticalLayoutCategory and S.RegisterProxySetting and S.RegisterAddOnCategory then
    local err
    ok, err = pcall(self.BuildNative, self)
    if not ok then self.nativeError = err end
  end
  if not ok then
    local fine, err = pcall(self.BuildSimple, self)
    if not fine then self.simpleError = err end
  end
end
