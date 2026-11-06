-- KEK — vue « Réglages » : bande, notifications, interface.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local View = { id = "settings", order = 99, bottom = true, label = L["Réglages"], title = L["Réglages"], glyph = "gear" }

function View:Subtitle()
  return string.format(L["KEK %s · tout est enregistré automatiquement"], ns.VERSION)
end

local function section(parent, title, glyph, height)
  local card = UI.Card(parent, { radius = 12, fill = C.card })
  card:SetHeight(height)
  local g = UI.Glyph(card, glyph, 14, C.accent)
  g:SetPoint("TOPLEFT", 16, -16)
  local caps = UI.Caps(card, title, C.muted)
  caps:SetPoint("LEFT", g, "RIGHT", 8, 0)
  return card
end

local function labeledToggle(parent, label, value, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(180, 24)
  f.toggle = UI.Toggle(f, value, onChange)
  f.toggle:SetPoint("LEFT", 0, 0)
  f.label = UI.Text(f, 13, C.text)
  f.label:SetPoint("LEFT", f.toggle, "RIGHT", 10, 0)
  f.label:SetText(label)
  f:EnableMouse(true)
  f:SetScript("OnMouseUp", function() f.toggle:Click() end)
  return f
end

function View:Build(frame)
  self.frame = frame

  -- ---------------------------------------------------------------- bande
  local band = section(frame, L["TA BANDE"], "users", 172)
  band:SetPoint("TOPLEFT", 0, 0)
  band:SetPoint("TOPRIGHT", 0, 0)

  self.statusChip = UI.Chip(band, 22)
  self.statusChip:SetPoint("TOPRIGHT", band, "TOPRIGHT", -16, -12)

  -- ligne 1 : code de la bande (à gauche), pseudo (à droite)
  local codeLabel = UI.Text(band, 12, C.muted)
  codeLabel:SetPoint("TOPLEFT", 16, -46)
  codeLabel:SetText(L["Code secret partagé avec tes amis"])
  local code = UI.Input(band, { placeholder = L["ex. loutres"], max = 24, noClear = true })
  code:SetSize(170, 32)
  code:SetPoint("TOPLEFT", band, "TOPLEFT", 16, -64)
  code:SetText(ns.db.band.code)
  self.codeInput = code
  local apply = function()
    local value = code:GetText():lower():gsub("[^%w]", "")
    code:SetText(value)
    ns.Comm:SetCode(value)
    ns.Window:Refresh()
  end
  code.eb:SetScript("OnEnterPressed", function(eb) eb:ClearFocus(); apply() end)
  local join = UI.Button(band, { text = L["Rejoindre"], style = "primary", h = 32, onClick = apply })
  join:SetPoint("LEFT", code, "RIGHT", 8, 0)

  local nick = UI.Input(band, { placeholder = L["ex. Nans"], max = 20, noClear = true, onChange = function(text, user)
    if not user then return end
    ns.db.nick = text
    ns:Debounce("nick", 1.5, function() ns.Profile:Changed(2) end)
  end })
  nick:SetSize(150, 32)
  nick:SetPoint("TOPRIGHT", band, "TOPRIGHT", -16, -64)
  nick:SetText(ns.db.nick)
  local nickLabel = UI.Text(band, 12, C.muted)
  nickLabel:SetPoint("TOPLEFT", band, "TOPRIGHT", -166, -46)
  nickLabel:SetText(L["Ton pseudo"])

  -- ligne 2 : ajouter un ami par le nom d'un de ses personnages
  local addLabel = UI.Text(band, 12, C.muted)
  addLabel:SetPoint("TOPLEFT", 16, -108)
  addLabel:SetText(L["Ajouter un ami (un de ses persos)"])
  local add = UI.Input(band, { placeholder = U.SURNAMES and L["ex. Philipon Dugard"] or L["ex. Gromgar"], max = 48, noClear = true })
  add:SetSize(170, 32)
  add:SetPoint("TOPLEFT", band, "TOPLEFT", 16, -126)
  self.addInput = add
  local submit = function()
    if ns.Comm:AddPeer(add:GetText()) then add:SetText("") end
  end
  add.eb:SetScript("OnEnterPressed", function(eb) eb:ClearFocus(); submit() end)
  self.addButton = UI.Button(band, { text = L["Ajouter"], icon = "plus", style = "secondary", h = 32, onClick = submit })
  self.addButton:SetPoint("LEFT", add, "RIGHT", 8, 0)

  self.modeHint = UI.Text(band, 11, C.faint)
  self.modeHint:SetPoint("TOPLEFT", self.addButton, "TOPRIGHT", 16, 18)
  self.modeHint:SetPoint("RIGHT", band, "RIGHT", -16, 0)
  self.modeHint:SetJustifyH("LEFT")
  self.modeHint:SetJustifyV("TOP")
  self.modeHint:SetWordWrap(true)

  -- ---------------------------------------------------------------- notifications
  local notif = section(frame, L["NOTIFICATIONS"], "bell", 176)
  notif:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, -12)
  notif:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, -12)
  local a = ns.db.alerts
  local toggles = {
    { "level", L["Niveaux"] }, { "loot", L["Butin"] }, { "death", L["Morts"] },
    { "boss", L["Boss vaincus"] }, { "skill", L["Paliers de métier"] }, { "presence", L["Connexions"] },
    { "need", L["Besoins"] },
  }
  self.toggles = {}
  for i, t in ipairs(toggles) do
    local key = t[1]
    local row = labeledToggle(notif, t[2], a[key], function(v) a[key] = v end)
    self.toggles[key] = row.toggle
    local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
    row:SetPoint("TOPLEFT", notif, "TOPLEFT", 16 + col * 180, -46 - line * 32)
  end
  local sound = labeledToggle(notif, L["Sons"], a.sound, function(v) a.sound = v end)
  self.toggles.sound = sound.toggle
  sound:SetPoint("TOPLEFT", notif, "TOPLEFT", 196, -110)
  local selfToggle = labeledToggle(notif, L["Mes propres exploits"], a.self, function(v) a.self = v end)
  self.toggles.self = selfToggle.toggle
  selfToggle:SetPoint("TOPLEFT", notif, "TOPLEFT", 376, -110)

  local lootLabel = UI.Text(notif, 12, C.muted)
  lootLabel:SetPoint("TOPLEFT", notif, "TOPLEFT", 16, -146)
  lootLabel:SetText(L["Butin à partager :"])
  local loot = UI.Segmented(notif, {
    { value = 3, label = L["Rare et +"] },
    { value = 4, label = L["Épique et +"] },
  }, a.lootQuality, function(v) a.lootQuality = v end, { h = 26 })
  loot:SetPoint("LEFT", lootLabel, "RIGHT", 10, 0)
  self.lootSegmented = loot

  local test = UI.Button(notif, { text = L["Tester"], icon = "star", style = "secondary", h = 28, onClick = function() ns.Toasts:Demo() end })
  test:SetPoint("BOTTOMRIGHT", notif, "BOTTOMRIGHT", -16, 14)
  local move = UI.Button(notif, { text = L["Déplacer"], icon = "pin", style = "secondary", h = 28, onClick = function() ns.Toasts:Unlock() end })
  move:SetPoint("RIGHT", test, "LEFT", -8, 0)
  local resetPos = UI.IconButton(notif, "close", { size = 28, iconSize = 11, tooltip = L["Position par défaut"], onClick = function() ns.Toasts:Reset() end })
  resetPos:SetPoint("RIGHT", move, "LEFT", -4, 0)

  -- ---------------------------------------------------------------- interface
  local iface = section(frame, L["INTERFACE"], "sliders", 92)
  iface:SetPoint("TOPLEFT", notif, "BOTTOMLEFT", 0, -12)
  iface:SetPoint("TOPRIGHT", notif, "BOTTOMRIGHT", 0, -12)
  local scaleLabel = UI.Text(iface, 12, C.muted)
  scaleLabel:SetPoint("TOPLEFT", 16, -50)
  scaleLabel:SetText(L["Taille de la fenêtre"])
  local scaleValue = UI.Text(iface, 12, C.text)
  local slider = UI.Slider(iface, { w = 160, min = 0.8, max = 1.3, step = 0.05, value = ns.db.ui.scale or 1,
    onChange = function(v) scaleValue:SetText(string.format("%d %%", math.floor(v * 100 + 0.5))) end,
    onRelease = function(v) ns.Window:SetScale(v) end })
  slider:SetPoint("LEFT", scaleLabel, "RIGHT", 14, 0)
  scaleValue:SetPoint("LEFT", slider, "RIGHT", 12, 0)
  scaleValue:SetText(string.format("%d %%", math.floor((ns.db.ui.scale or 1) * 100 + 0.5)))
  self.scaleSlider, self.scaleValue = slider, scaleValue

  local mini = labeledToggle(iface, L["Bouton sur la minicarte"], ns.MinimapButton:Wanted(), function(v)
    ns.MinimapButton:SetWanted(v)
  end)
  mini:SetPoint("TOPLEFT", iface, "TOP", 40, -46)
  self.miniToggle = mini.toggle

  local reset = UI.Button(iface, { text = L["Tout réinitialiser"], icon = "trash", style = "danger", h = 28, onClick = function()
    UI.Confirm(L["Effacer toutes les données de KEK (bande, historique, réglages) et recharger l'interface ?"], function() ns:ResetAll() end, L["Effacer"])
  end })
  reset:SetPoint("BOTTOMRIGHT", iface, "BOTTOMRIGHT", -16, 14)
  local autotest = UI.Button(iface, { text = L["Autotest"], icon = "check", style = "secondary", h = 28,
    tooltip = L["Vérifie KEK dans ton jeu et produit un rapport à copier-coller."],
    onClick = function() ns.Autotest:Run() end })
  autotest:SetPoint("RIGHT", reset, "LEFT", -8, 0)
end

-- Les réglages peuvent aussi changer depuis le menu Options du jeu : on resynchronise l'affichage.
function View:SyncControls()
  local a = ns.db.alerts
  for key, toggle in pairs(self.toggles) do
    local v = a[key] and true or false
    if toggle.value ~= v then toggle:SetValue(v) end
  end
  if self.lootSegmented.value ~= a.lootQuality then self.lootSegmented:SetValue(a.lootQuality) end
  local scale = ns.db.ui.scale or 1
  if math.abs((self.scaleSlider.value or 1) - scale) > 0.001 then
    self.scaleSlider:SetValue(scale, true)
    self.scaleValue:SetText(string.format("%d %%", math.floor(scale * 100 + 0.5)))
  end
  local wanted = ns.MinimapButton:Wanted()
  if self.miniToggle.value ~= wanted then self.miniToggle:SetValue(wanted) end
end

function View:Refresh()
  self:SyncControls()
  local text, ok = ns.Comm:StatusText()
  self.statusChip:Set(text, ok and C.good or (ns.Comm.mode == "offline" and C.gold or C.faint), ok and "check" or nil)
  if not self.codeInput:HasFocus() then self.codeInput:SetText(ns.db.band.code) end
  local hasCode = ns.Comm:Code() ~= ""
  self.addButton:SetDisabled(not hasCode)
  self.addInput:SetAlpha(hasCode and 1 or 0.4)
  self.addInput.eb:EnableMouse(hasCode)
  if hasCode then
    self.modeHint:SetText(L["KEK trouve ta bande via ta guilde, ton groupe et ta liste d'amis, puis lui parle par messages invisibles. Un ami n'apparaît pas ? Ajoute un de ses persos."])
  elseif ns.Comm:IsGuildBand() then
    self.modeHint:SetText(L["Sans code, ta bande est ta guilde : ses membres qui ont KEK apparaissent. Entre un code pour jouer avec des amis hors guilde."])
  else
    self.modeHint:SetText(L["Entre le même code que tes amis pour former ta bande."])
  end
end

ns.Window:Register(View)
