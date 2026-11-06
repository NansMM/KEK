-- KEK — fenêtre principale : barre latérale, en-tête, vues, redimensionnement, animations.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local T = UI.T
local C = T.c

local Window = ns:NewModule("Window", 70)
Window.views, Window.byId = {}, {}

local SIDEBAR = 214
local MIN_W, MIN_H, MAX_W, MAX_H = 820, 590, 1500, 1000

-- Les vues s'enregistrent au chargement de leur fichier.
-- def = { id, order, label, glyph, title, Subtitle(), Badge(), Build(frame, actions), Refresh() }
function Window:Register(def)
  self.views[#self.views + 1] = def
  self.byId[def.id] = def
  table.sort(self.views, function(a, b) return a.order < b.order end)
end

function Window:OnLogin()
  ns:On("DATA", function() self:RequestRefresh() end)
  ns:On("COMM_STATUS", function() self:RequestRefresh() end)
  ns:On("PRESENCE", function() self:RequestRefresh() end)
end

-- ------------------------------------------------------------------ construction
function Window:Build()
  local db = ns.db.ui
  local f = CreateFrame("Frame", "KEKWindow", UIParent)
  self.frame = f
  f:SetSize(U.Clamp(db.width or 900, MIN_W, MAX_W), U.Clamp(db.height or 620, MIN_H, MAX_H))
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
    f:SetMaxResize(MAX_W, MAX_H)
  end
  f:SetScale(db.scale or 1)
  if type(db.point) == "table" and db.point[1] then
    f:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  end
  f:Hide()
  tinsert(UISpecialFrames, "KEKWindow")
  f:SetScript("OnHide", function()
    UI.CloseMenu()
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE) or 851)
  end)

  UI.Shadow(f, 34, 0.75, -8)
  f.bg = UI.Round(f, 14, C.shell)

  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.ui.point = { p, rp, x, y }
  end)

  self:BuildSidebar()
  self:BuildContent()

  -- poignée de redimensionnement
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(18, 18)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  grip:SetFrameLevel(f:GetFrameLevel() + 40)
  grip.icon = UI.Glyph(grip, "grip", 14, C.faint)
  grip.icon:SetPoint("CENTER")
  grip:SetScript("OnEnter", function(g) UI.SetColor(g.icon, C.muted) end)
  grip:SetScript("OnLeave", function(g) UI.SetColor(g.icon, C.faint) end)
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    ns.db.ui.width, ns.db.ui.height = math.floor(f:GetWidth()), math.floor(f:GetHeight())
    local p, _, rp, x, y = f:GetPoint()
    ns.db.ui.point = { p, rp, x, y }
  end)
end

function Window:BuildSidebar()
  local f = self.frame
  local side = CreateFrame("Frame", nil, f)
  side:SetPoint("TOPLEFT")
  side:SetPoint("BOTTOMLEFT")
  side:SetWidth(SIDEBAR)
  self.side = side

  -- logo
  local logoBg = side:CreateTexture(nil, "ARTWORK")
  logoBg:SetTexture(UI.Media("circle"))
  logoBg:SetSize(44, 44)
  logoBg:SetPoint("TOPLEFT", side, "TOPLEFT", 20, -20)
  UI.SetColor(logoBg, C.card)
  local glow = side:CreateTexture(nil, "BORDER")
  glow:SetTexture(UI.Media("glow"))
  glow:SetSize(110, 110)
  glow:SetPoint("CENTER", logoBg, "CENTER")
  glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.22)
  local logo = side:CreateTexture(nil, "OVERLAY")
  logo:SetTexture(UI.Media("logo"))
  logo:SetSize(34, 34)
  logo:SetPoint("CENTER", logoBg, "CENTER", 0, 1)

  local title = UI.Title(side, 22, C.text)
  title:SetPoint("TOPLEFT", logoBg, "TOPRIGHT", 12, -3)
  title:SetText("KEK")
  self.bandLabel = UI.Text(side, 11, C.muted)
  self.bandLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  self.bandLabel:SetWidth(SIDEBAR - 90)

  -- navigation
  self.nav = {}
  local y = 92
  for _, def in ipairs(self.views) do
    if not def.bottom then
      self.nav[def.id] = self:NavItem(side, def, y)
      y = y + 38
    end
  end

  -- statut de connexion
  local status = UI.Card(side, { radius = 10, fill = C.surface, edge = { 1, 1, 1, 0.05 } })
  status:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 12, 12)
  status:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -12, 12)
  status:SetHeight(54)
  status.dot = status:CreateTexture(nil, "ARTWORK")
  status.dot:SetTexture(UI.Media("circle"))
  status.dot:SetSize(8, 8)
  status.dot:SetPoint("TOPLEFT", 14, -16)
  status.pulse = status:CreateTexture(nil, "BORDER")
  status.pulse:SetTexture(UI.Media("circle"))
  status.pulse:SetSize(8, 8)
  status.pulse:SetPoint("CENTER", status.dot)
  status.line1 = UI.Text(status, 13, C.text)
  status.line1:SetPoint("LEFT", status.dot, "RIGHT", 8, 0)
  status.line2 = UI.Text(status, 11, C.faint)
  status.line2:SetPoint("TOPLEFT", status.dot, "BOTTOMLEFT", 0, -10)
  status.line2:SetPoint("RIGHT", status, "RIGHT", -12, 0)
  self.status = status
  -- pulsation douce du voyant
  local elapsed = 0
  status:SetScript("OnUpdate", function(s, dt)
    elapsed = (elapsed + dt) % 2.2
    local p = elapsed / 2.2
    s.pulse:SetSize(8 + 14 * p, 8 + 14 * p)
    s.pulse:SetAlpha((1 - p) * 0.5)
  end)

  -- vues du bas (réglages)
  local by = 74
  for _, def in ipairs(self.views) do
    if def.bottom then
      local item = self:NavItem(side, def, 0)
      item:ClearAllPoints()
      item:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 12, by)
      item:SetPoint("RIGHT", side, "RIGHT", -12, 0)
      self.nav[def.id] = item
      by = by + 38
    end
  end
end

function Window:NavItem(side, def, y)
  local item = CreateFrame("Button", nil, side)
  item:SetHeight(36)
  item:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -y)
  item:SetPoint("RIGHT", side, "RIGHT", -12, 0)
  UI.Hoverable(item, 9)
  item.indicator = CreateFrame("Frame", nil, item)
  item.indicator:SetSize(3, 16)
  item.indicator:SetPoint("LEFT", item, "LEFT", 0, 0)
  item.indicator.bg = UI.Round(item.indicator, 1.5, C.accent)
  item.indicator:Hide()
  item.glyph = UI.Glyph(item, def.glyph, 16, C.muted)
  item.glyph:SetPoint("LEFT", 14, 0)
  item.label = UI.Text(item, 13, C.muted)
  item.label:SetPoint("LEFT", 40, 0)
  item.label:SetText(def.label)
  item.badge = UI.Chip(item, 18)
  item.badge:SetPoint("RIGHT", -8, 0)
  item.badge:Hide()
  item:SetScript("OnClick", function()
    U.Click()
    self:Select(def.id)
  end)
  item:HookScript("OnEnter", function(i) if not i.selected then UI.SetTextColor(i.label, C.text); UI.SetColor(i.glyph, C.text) end end)
  item:HookScript("OnLeave", function(i) if not i.selected then UI.SetTextColor(i.label, C.muted); UI.SetColor(i.glyph, C.muted) end end)
  return item
end

function Window:BuildContent()
  local f = self.frame
  local content = UI.Card(f, { radius = 12, fill = C.surface, edge = { 1, 1, 1, 0.05 } })
  content:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR, -10)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
  self.content = content

  local header = CreateFrame("Frame", nil, content)
  header:SetPoint("TOPLEFT", content, "TOPLEFT", 26, -20)
  header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -58, -20)
  header:SetHeight(44)
  self.header = header
  self.title = UI.Title(header, 21, C.text)
  self.title:SetPoint("TOPLEFT", 0, 0)
  self.subtitle = UI.Text(header, 12, C.muted)
  self.subtitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)

  local close = UI.IconButton(content, "close", { size = 30, iconSize = 12, tooltip = L["Fermer (Échap)"], onClick = function() self:Close() end })
  close:SetPoint("TOPRIGHT", content, "TOPRIGHT", -14, -16)

  local body = CreateFrame("Frame", nil, content)
  body:SetPoint("TOPLEFT", content, "TOPLEFT", 26, -82)
  body:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 18)
  self.body = body
end

-- ------------------------------------------------------------------ navigation
function Window:Select(id)
  local def = self.byId[id] or self.views[1]
  if not self.frame then return end
  if self.current == def then
    self:Refresh()
    return
  end
  if self.current then
    self.current.frame:Hide()
    self.current.actions:Hide()
  end
  self.current = def
  ns.db.ui.view = def.id
  if not def.frame then
    def.frame = CreateFrame("Frame", nil, self.body)
    def.actions = CreateFrame("Frame", nil, self.header)
    def.actions:SetPoint("TOPRIGHT", self.header, "TOPRIGHT", 0, 0)
    def.actions:SetSize(520, 30)
    def.frame:SetPoint("TOPLEFT", self.body, "TOPLEFT")
    def.frame:SetPoint("BOTTOMRIGHT", self.body, "BOTTOMRIGHT")
    local ok, err = pcall(def.Build, def, def.frame, def.actions)
    if not ok then ns.Report(err) end
  end
  def.frame:Show()
  def.actions:Show()
  -- entrée en fondu avec léger glissement
  def.frame:SetAlpha(0)
  UI.Tween(def.frame, "enter", 0.24, function(p)
    def.frame:SetAlpha(p)
    def.frame:ClearAllPoints()
    def.frame:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -8 * (1 - p))
    def.frame:SetPoint("BOTTOMRIGHT", self.body, "BOTTOMRIGHT", 0, -8 * (1 - p))
  end)
  self:Refresh()
end

function Window:UpdateNav()
  for id, item in pairs(self.nav) do
    local on = self.current and self.current.id == id
    item:SetSelected(on, C.accentDim)
    item.indicator:SetShown(on)
    UI.SetTextColor(item.label, on and C.text or C.muted)
    UI.SetColor(item.glyph, on and C.accent or C.muted)
    local def = self.byId[id]
    local badge = def.Badge and def:Badge()
    if badge then
      item.badge:Set(tostring(badge), on and C.accent or C.muted)
      item.badge:Show()
    else
      item.badge:Hide()
    end
  end
end

function Window:UpdateHeader()
  local def = self.current
  if not def then return end
  self.title:SetText(def.title or def.label)
  local sub = def.Subtitle and def:Subtitle() or ""
  self.subtitle:SetText(sub or "")
end

function Window:UpdateStatus()
  local text, ok = ns.Comm:StatusText()
  local online = ns.Store:OnlineCount()
  local s = self.status
  if ok then
    UI.SetColor(s.dot, C.good)
    UI.SetColor(s.pulse, C.good)
    s.line1:SetText(online == 0 and L["Personne d'autre en ligne"] or string.format(online == 1 and L["%d ami en ligne"] or L["%d amis en ligne"], online))
  else
    UI.SetColor(s.dot, ns.Comm.mode == "offline" and C.gold or C.faint)
    UI.SetColor(s.pulse, ns.Comm.mode == "offline" and C.gold or C.faint)
    s.line1:SetText(ns.Comm.mode == "offline" and L["Connexion…"] or L["Déconnecté"])
  end
  s.line2:SetText(text .. " · v" .. ns.VERSION)

  local code = ns.Comm:Code()
  if code ~= "" then
    self.bandLabel:SetText(string.format(L["Bande « %s »"], code))
  elseif ns.Comm:IsGuildBand() then
    self.bandLabel:SetText(string.format(L["Guilde %s"], GetGuildInfo("player") or ""))
  else
    self.bandLabel:SetText(L["Aucune bande"])
  end
end

function Window:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  if self.current and self.current.Refresh then
    local ok, err = pcall(self.current.Refresh, self.current)
    if not ok then ns.Report(err) end
  end
  self:UpdateHeader()
  self:UpdateNav()
  self:UpdateStatus()
end

function Window:RequestRefresh()
  if not self.frame or not self.frame:IsShown() then return end
  ns:Debounce("window-refresh", 0.15, function() self:Refresh() end)
end

-- ------------------------------------------------------------------ ouverture
function Window:Open(view)
  if not ns.ready then return end
  if not self.frame then self:Build() end
  local wasShown = self.frame:IsShown()
  self.frame:Show()
  if view then
    self:Select(view)
  elseif not self.current then
    self:Select(ns.db.ui.view)
  end
  if not wasShown then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN) or 850)
    self.frame:SetAlpha(0)
    UI.Tween(self.frame, "open", 0.2, function(p) self.frame:SetAlpha(p) end)
  end
  self:Refresh()
end

function Window:Close()
  if self.frame then self.frame:Hide() end
end

function Window:Toggle()
  if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end

function Window:SetScale(scale)
  ns.db.ui.scale = scale
  if self.frame then self.frame:SetScale(scale) end
end

function Window:IsCurrent(id)
  return self.frame and self.frame:IsShown() and self.current and self.current.id == id
end
