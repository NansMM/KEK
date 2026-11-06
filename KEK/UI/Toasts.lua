-- KEK — notifications animées : empilement fluide, pause au survol, fusion des boss, carte dorée pour le 60.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local Toasts = ns:NewModule("Toasts", 60)

local WIDTH, GAP, MAX_VISIBLE = 340, 8, 4
local HEIGHT = { normal = 74, compact = 46, big = 94 }

Toasts.active = {}
Toasts.pool = {}

-- ------------------------------------------------------------------ ancre
function Toasts:OnLogin()
  local anchor = CreateFrame("Frame", "KEKToastAnchor", UIParent)
  anchor:SetSize(WIDTH, 24)
  anchor:SetFrameStrata("HIGH")
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  self.anchor = anchor
  self:RestoreAnchor()
end

function Toasts:RestoreAnchor()
  local p = ns.db.ui.toastPoint
  self.anchor:ClearAllPoints()
  if type(p) == "table" and p[1] then
    self.anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    self.anchor:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -215, -235)
  end
end

function Toasts:GrowsUp()
  local _, y = self.anchor:GetCenter()
  return y and y < (UIParent:GetHeight() / 2) or false
end

-- ------------------------------------------------------------------ construction d'une carte
function Toasts:Create()
  local t = CreateFrame("Button", nil, self.anchor)
  t:SetWidth(WIDTH)
  t:SetFrameStrata("HIGH")
  t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.Shadow(t, 18, 0.65, -4)
  t.edge = UI.Round(t, 11, C.edge, "BACKGROUND", 0)
  t.fill = UI.Round(t, 10, C.card, "BACKGROUND", 1, 1)

  -- halo et reflet, rognés aux bords de la carte
  t.clip = CreateFrame("Frame", nil, t)
  t.clip:SetPoint("TOPLEFT", 3, -3)
  t.clip:SetPoint("BOTTOMRIGHT", -3, 3)
  if t.clip.SetClipsChildren then t.clip:SetClipsChildren(true) end
  t.fx = CreateFrame("Frame", nil, t.clip)
  t.fx:SetAllPoints()
  t.glow = t.fx:CreateTexture(nil, "BACKGROUND")
  t.glow:SetTexture(UI.Media("glow"))
  t.glow:SetSize(170, 170)
  t.shine = t.fx:CreateTexture(nil, "ARTWORK")
  t.shine:SetTexture(UI.Media("shine"))
  t.shine:SetBlendMode("ADD")
  t.shine:SetSize(70, 140)
  t.shine:Hide()

  t.content = CreateFrame("Frame", nil, t)
  t.content:SetAllPoints()
  t.content:SetFrameLevel(t.fx:GetFrameLevel() + 2)
  local c = t.content
  t.stripe = CreateFrame("Frame", nil, c)
  t.stripe:SetWidth(3)
  t.stripe:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -16)
  t.stripe:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 16)
  t.stripe.bg = UI.Round(t.stripe, 1.5, C.accent)

  t.avatar = UI.Avatar(c, 42)
  t.item = UI.ItemIcon(c, 42)
  t.badge = UI.Badge(c, 42, "star")

  t.label = UI.Caps(c, "", C.accent)
  t.time = UI.Text(c, 10, C.faint)
  t.time:SetPoint("TOPRIGHT", c, "TOPRIGHT", -14, -13)
  t.title = UI.Title(c, 13)
  t.body = UI.Text(c, 12, C.muted)

  t.timer = c:CreateTexture(nil, "OVERLAY")
  t.timer:SetTexture(UI.WHITE)
  t.timer:SetHeight(2)
  t.timer:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 12, 5)

  t.close = UI.IconButton(c, "close", { size = 20, iconSize = 9, onClick = function() Toasts:Dismiss(t) end })
  t.close:SetPoint("TOPRIGHT", c, "TOPRIGHT", -7, -7)
  t.close:Hide()

  t:SetScript("OnUpdate", function(self, elapsed) Toasts:Tick(self, elapsed) end)
  t:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      Toasts:Dismiss(self)
      return
    end
    if self.spec and self.spec.onClick then
      self.spec.onClick()
    elseif ns.Window then
      ns.Window:Open(self.spec and self.spec.view)
    end
    Toasts:Dismiss(self)
  end)
  t:SetScript("OnEnter", function(self)
    if self.spec and self.spec.link then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      pcall(GameTooltip.SetHyperlink, GameTooltip, self.spec.link)
      GameTooltip:Show()
    end
  end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return t
end

function Toasts:Fill(t, spec)
  local mode = spec.compact and "compact" or (spec.big and "big" or "normal")
  local h = HEIGHT[mode]
  t:SetHeight(h)
  local color = spec.color or C.accent
  local c = t.content

  if spec.big then
    t.edge:SetColor(C.gold[1], C.gold[2], C.gold[3], 0.9)
  else
    t.edge:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
  end
  t.stripe.bg:SetColor(color[1], color[2], color[3], 1)
  t.glow:SetVertexColor(color[1], color[2], color[3], spec.big and 0.55 or 0.30)

  local size = mode == "compact" and 26 or (mode == "big" and 54 or 42)
  local iconX = mode == "compact" and 14 or 16
  t.avatar:Hide(); t.item:Hide(); t.badge:Hide()
  local icon
  if spec.icon then
    icon = t.item
    icon:SetItem(spec.icon, spec.quality)
  elseif spec.member then
    icon = t.avatar
    icon:SetMember(ns.db.members[spec.member], true, false)
  else
    icon = t.badge
    icon:Set(spec.glyph or "star", color)
  end
  icon:SetSize(size, size)
  icon:ClearAllPoints()
  icon:SetPoint("LEFT", c, "LEFT", iconX, 0)
  icon:Show()
  t.glow:ClearAllPoints()
  t.glow:SetPoint("CENTER", c, "LEFT", iconX + size / 2, 0)

  local x = iconX + size + 13
  local width = WIDTH - x - 16
  t.title:SetFont(UI.T.font.title, spec.big and 15 or 13, "")
  t.title:SetText(spec.title or "")
  t.title:SetWidth(width)
  t.title:ClearAllPoints()
  t.body:SetText(spec.body or "")
  t.body:SetWidth(width)
  t.body:ClearAllPoints()
  t.label:ClearAllPoints()
  if mode == "compact" then
    t.label:Hide()
    t.body:Hide()
    t.title:SetPoint("LEFT", c, "LEFT", x, 0)
    t.title:SetWidth(width - 50)
  else
    t.label:Show()
    t.label:SetText(spec.label or "")
    UI.SetTextColor(t.label, spec.big and C.gold or color)
    t.label:SetPoint("TOPLEFT", c, "TOPLEFT", x, mode == "big" and -16 or -13)
    t.title:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -5)
    t.body:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -5)
    t.body:SetShown((spec.body or "") ~= "")
  end
  t.time:SetText(L["à l'instant"])
  t.time:ClearAllPoints()
  t.time:SetPoint(mode == "compact" and "RIGHT" or "TOPRIGHT", c, mode == "compact" and "RIGHT" or "TOPRIGHT", -14, mode == "compact" and 0 or -13)
  t.timer:SetVertexColor(color[1], color[2], color[3], 0.55)
  t.timer:SetWidth(WIDTH - 24)
end

-- ------------------------------------------------------------------ cycle de vie
function Toasts:Show(spec)
  if not self.anchor or type(spec) ~= "table" then return end
  if spec.key then
    for _, t in ipairs(self.active) do
      if not t.leaving and t.spec.key == spec.key then
        if spec.merge then t.spec = spec.merge(t.spec, spec) or t.spec end
        self:Fill(t, t.spec)
        t.remaining = t.duration
        self:Pulse(t)
        return
      end
    end
  end

  local t = table.remove(self.pool) or self:Create()
  t.spec = spec
  t.duration = spec.duration or 7
  t.remaining = t.duration
  t.leaving, t.hovered = false, nil
  self:Fill(t, spec)
  table.insert(self.active, 1, t)

  local visible = 0
  for _, other in ipairs(self.active) do
    if not other.leaving then
      visible = visible + 1
      if visible > MAX_VISIBLE then self:Dismiss(other) end
    end
  end

  t.ox, t.cy = 34, nil
  t:SetAlpha(0)
  t:Show()
  self:Layout(t)
  UI.Tween(t, "enter", 0.42, function(p)
    t.ox = 34 * (1 - p)
    t:SetAlpha(math.min(1, p * 1.4))
    self:Place(t)
  end, nil, UI.Ease.out)
  if spec.big then self:Shine(t) else t.shine:Hide() end
  U.PlayAlert(spec.sound or spec.kind or "presence")
end

function Toasts:Place(t)
  t:ClearAllPoints()
  if self:GrowsUp() then
    t:SetPoint("BOTTOM", self.anchor, "BOTTOM", t.ox or 0, t.cy or 0)
  else
    t:SetPoint("TOP", self.anchor, "TOP", t.ox or 0, t.cy or 0)
  end
end

function Toasts:Layout(newcomer)
  local up = self:GrowsUp()
  local y = 0
  for _, t in ipairs(self.active) do
    if not t.leaving then
      local target = up and y or -y
      if t == newcomer or t.cy == nil then
        t.cy = target
        self:Place(t)
      elseif t.cy ~= target then
        local from = t.cy
        UI.Tween(t, "move", 0.32, function(p)
          t.cy = from + (target - from) * p
          self:Place(t)
        end)
      end
      y = y + t:GetHeight() + GAP
    end
  end
end

function Toasts:Dismiss(t)
  if t.leaving then return end
  t.leaving = true
  local x0 = t.ox or 0
  local a0 = t:GetAlpha()
  UI.StopTween(t, "move")
  UI.Tween(t, "enter", 0.26, function(p)
    t:SetAlpha(a0 * (1 - p))
    t.ox = x0 + 26 * p
    self:Place(t)
  end, function()
    t:Hide()
    t.shine:Hide()
    for i, other in ipairs(self.active) do
      if other == t then table.remove(self.active, i) break end
    end
    self.pool[#self.pool + 1] = t
  end, UI.Ease.inOut)
  self:Layout()
end

function Toasts:Tick(t, elapsed)
  local hovered = t:IsMouseOver()
  if hovered ~= t.hovered then
    t.hovered = hovered
    t.close:SetShown(hovered and not t.leaving)
    t.time:SetShown(not hovered)
  end
  if t.leaving then return end
  if not hovered then t.remaining = t.remaining - elapsed end
  t.timer:SetWidth(math.max(0.1, (WIDTH - 24) * math.max(0, t.remaining) / t.duration))
  if t.remaining <= 0 then self:Dismiss(t) end
end

-- Petit rebond quand une notification existante est mise à jour.
function Toasts:Pulse(t)
  UI.Tween(t, "pulse", 0.35, function(p)
    local k = math.sin(p * math.pi)
    t.glow:SetAlpha(0.3 + 0.5 * k)
  end, function() t.glow:SetAlpha(1) end)
end

-- Reflet qui balaie la carte dorée.
function Toasts:Shine(t)
  t.shine:Show()
  local runs = 0
  local function sweep()
    runs = runs + 1
    UI.Tween(t, "shine", 1.1, function(p)
      t.shine:ClearAllPoints()
      t.shine:SetPoint("CENTER", t.fx, "LEFT", -40 + (WIDTH + 80) * p, 0)
      t.shine:SetAlpha(math.sin(p * math.pi) * 0.55)
    end, function()
      if runs < 3 and t:IsShown() and not t.leaving then C_Timer.After(1.4, sweep) else t.shine:Hide() end
    end, UI.Ease.inOut)
  end
  sweep()
end

-- ------------------------------------------------------------------ déplacement
function Toasts:Unlock()
  if not self.mover then
    local m = UI.Card(self.anchor, { fill = { 1, 0.549, 0.239, 0.16 }, edge = C.accent })
    m:SetAllPoints(self.anchor)
    m:SetFrameStrata("DIALOG")
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    local text = UI.Title(m, 12, C.text)
    text:SetPoint("LEFT", 14, 0)
    text:SetText(L["Notifications — glisse-moi où tu veux"])
    local done = UI.Button(m, { text = L["Terminé"], style = "primary", h = 24, onClick = function() Toasts:Lock() end })
    done:SetPoint("RIGHT", -8, 0)
    m:SetScript("OnDragStart", function() self.anchor:StartMoving() end)
    m:SetScript("OnDragStop", function()
      self.anchor:StopMovingOrSizing()
      local p, _, rp, x, y = self.anchor:GetPoint()
      ns.db.ui.toastPoint = { p, rp, x, y }
      self:Layout()
    end)
    self.mover = m
  end
  self.anchor:SetHeight(48)
  self.mover:Show()
end

function Toasts:Lock()
  if self.mover then self.mover:Hide() end
  self.anchor:SetHeight(24)
end

function Toasts:Reset()
  ns.db.ui.toastPoint = nil
  self:RestoreAnchor()
end

-- ------------------------------------------------------------------ démonstration
function Toasts:Demo()
  local A = ns.Alerts
  local me = ns.me
  local now = ns.Now()
  local samples = {
    A:ToastSpec(me, { k = "level", l = 42, z = GetRealZoneText(), t = now }),
    A:ToastSpec(me, { k = "loot", q = 4, t = now,
      i = "|cffa335ee|Hitem:12784::::::::60:::::|h[" .. L["Faucheuse d'arcanite"] .. "]|h|r" }),
    A:ToastSpec(me, { k = "death", t = now, by = L["Pillard défias"], sp = L["Frappe héroïque"], a = 87, o = 23 }),
    A:ToastSpec(me, { k = "boss", b = "Edwin VanCleef", t = now }),
    A:ToastSpec(me, { k = "level", l = ns.MAX_LEVEL, t = now }),
  }
  samples[2].link = nil
  for i, spec in ipairs(samples) do
    spec.key = nil
    C_Timer.After((i - 1) * 0.45, function() self:Show(spec) end)
  end
end
