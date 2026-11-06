-- KEK — vue « Hall of Shame » : podium des morts, titres honorifiques, dernières morts détaillées.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local View = { id = "deaths", order = 3, label = L["Hall of Shame"], title = L["Hall of Shame"], glyph = "skull" }

local MEDALS = {
  { 1.00, 0.80, 0.35, 1 },   -- or
  { 0.78, 0.80, 0.86, 1 },   -- argent
  { 0.85, 0.55, 0.33, 1 },   -- bronze
}
local TOP_H = 214

function View:Subtitle()
  local total = 0
  for _, row in ipairs(ns.Deaths:Leaderboard()) do total = total + row.count end
  if total == 0 then return L["Aucune mort au compteur. Pour l'instant."] end
  return string.format(total == 1 and L["%d mort au total dans la bande"] or L["%d morts au total dans la bande"], total)
end

function View:Badge()
  local recent = ns.Deaths:Recent(50)
  local n = 0
  for _, r in ipairs(recent) do
    if ns.Now() - (r.d.t or 0) < 86400 then n = n + 1 end
  end
  return n > 0 and n or nil
end

-- ------------------------------------------------------------------ podium
local function createPodiumCard(parent)
  local card = UI.Card(parent, { radius = 12, fill = C.card })
  card.glow = card:CreateTexture(nil, "BORDER")
  card.glow:SetTexture(UI.Media("glow"))
  card.glow:SetSize(180, 180)
  card.glow:SetPoint("CENTER", card, "TOP", 0, -30)
  card.medal = card:CreateTexture(nil, "ARTWORK")
  card.medal:SetTexture(UI.Media("circle"))
  card.medal:SetSize(22, 22)
  card.medal:SetPoint("TOPLEFT", 10, -10)
  card.rank = UI.Title(card, 12, C.ink)
  card.rank:SetPoint("CENTER", card.medal)
  card.avatar = UI.Avatar(card, 48)
  card.avatar:SetPoint("TOP", 0, -18)
  card.name = UI.Title(card, 14)
  card.name:SetPoint("TOP", card.avatar, "BOTTOM", 0, -9)
  card.count = UI.Title(card, 30, C.text)
  card.count:SetPoint("TOP", card.name, "BOTTOM", 0, -6)
  card.unit = UI.Text(card, 11, C.faint)
  card.unit:SetPoint("TOP", card.count, "BOTTOM", 0, -3)
  card.title = UI.Chip(card, 20)
  card.title:SetPoint("BOTTOM", card, "BOTTOM", 0, 12)
  UI.Tip(card, function(tt, self)
    if self.m then ns.RosterView.MemberTooltip(tt, self.m) end
  end)
  return card
end

-- ------------------------------------------------------------------ titres
local function createTitleRow(list)
  local row = CreateFrame("Frame", nil, list)
  row:EnableMouse(true)
  row.badge = UI.Badge(row, 28, "star")
  row.badge:SetPoint("LEFT", 2, 0)
  row.title = UI.Title(row, 12, C.gold)
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 38, -4)
  row.name = UI.Text(row, 12, C.text)
  row.name:SetPoint("LEFT", row.title, "RIGHT", 6, 0)
  row.desc = UI.Text(row, 11, C.faint)
  row.desc:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
  return row
end

local function updateTitleRow(row, t)
  row.badge:Set(t.glyph, C.gold)
  row.title:SetText(t.title)
  row.name:SetText(U.MemberName(t.name))
  row.desc:SetText(t.desc)
  row.desc:SetWidth(row:GetWidth() - 44)
end

-- ------------------------------------------------------------------ dernières morts
local function createDeathRow(list)
  local row = CreateFrame("Button", nil, list)
  UI.Hoverable(row, 10)
  row.badge = UI.Badge(row, 36, "skull")
  row.badge:SetPoint("LEFT", 10, 0)
  row.avatar = UI.Avatar(row, 18)
  row.avatar:SetPoint("BOTTOMRIGHT", row.badge, "BOTTOMRIGHT", 5, -4)
  row.avatar:SetFrameLevel(row:GetFrameLevel() + 4)
  row.title = UI.Text(row, 13, C.text)
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 60, -11)
  row.cause = UI.Text(row, 12, C.muted)
  row.cause:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
  row.time = UI.Text(row, 11, C.faint)
  row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -12)
  row.zone = UI.Text(row, 11, C.faint)
  row.zone:SetPoint("TOPRIGHT", row.time, "BOTTOMRIGHT", 0, -6)
  row.zone:SetJustifyH("RIGHT")
  UI.Tip(row, function(tt, self)
    local d = self.d
    if not d then return end
    tt:AddLine(string.format(L["Mort de %s"], U.MemberName(self.w)), 1, 1, 1)
    tt:AddLine("« " .. ns.Deaths:Epitaph(d) .. " »", 1, 0.82, 0.5, true)
    tt:AddLine(" ")
    if d.z then tt:AddDoubleLine(L["Lieu"], d.sz and (d.z .. " · " .. d.sz) or d.z, 0.6, 0.62, 0.68, 1, 1, 1) end
    tt:AddDoubleLine(L["Niveau"], tostring(d.l or "?"), 0.6, 0.62, 0.68, 1, 1, 1)
    if type(d.h) == "table" and #d.h > 0 then
      tt:AddLine(" ")
      tt:AddLine(L["Derniers coups reçus"], 0.96, 0.38, 0.38)
      for _, hit in ipairs(d.h) do
        local who = hit.e and (ns.Deaths:KillerName(hit) or "?") or (hit.s or "?")
        tt:AddDoubleLine(who .. (hit.sp and (" · " .. hit.sp) or ""), U.Num(hit.a or 0), 0.85, 0.85, 0.85, 1, 0.5, 0.5)
      end
    end
    tt:AddLine(" ")
    tt:AddLine(U.DayLabel(d.t) .. " · " .. U.Clock(d.t), 0.5, 0.52, 0.58)
  end, "ANCHOR_CURSOR")
  return row
end

local function updateDeathRow(row, item)
  local d, w = item.d, item.w
  row.d, row.w = d, w
  row.badge:Set("skull", C.bad)
  row.avatar:SetMember(ns.db.members[w], true, false)
  local where = d.ins and L[" en donjon"] or ""
  row.title:SetText(string.format(L["%s · niveau %s%s"], U.MemberName(w), tostring(d.l or "?"), where))
  row.cause:SetText(ns.Deaths:Cause(d))
  row.cause:SetWidth(row:GetWidth() - 220)
  row.time:SetText(U.Ago(d.t))
  row.zone:SetText(d.z or "")
  row.zone:SetWidth(150)
end

-- ------------------------------------------------------------------ construction
function View:Build(frame)
  self.frame = frame
  self.top = CreateFrame("Frame", nil, frame)
  self.top:SetPoint("TOPLEFT", 0, 0)
  self.top:SetPoint("TOPRIGHT", 0, 0)
  self.top:SetHeight(TOP_H)

  self.podium = CreateFrame("Frame", nil, self.top)
  self.podium:SetPoint("TOPLEFT", 0, 0)
  self.podium:SetPoint("BOTTOMRIGHT", self.top, "BOTTOMRIGHT", -296, 0)
  self.cards = {}
  for i = 1, 3 do self.cards[i] = createPodiumCard(self.podium) end
  self.podium:SetScript("OnSizeChanged", function() self:LayoutPodium() end)

  local titles = UI.Card(self.top, { radius = 12, fill = C.card })
  titles:SetPoint("TOPRIGHT", 0, 0)
  titles:SetPoint("BOTTOMRIGHT", 0, 0)
  titles:SetWidth(282)
  local caps = UI.Caps(titles, L["TITRES HONORIFIQUES"])
  caps:SetPoint("TOPLEFT", 14, -14)
  self.titles = UI.List(titles, {
    rowHeight = 40, gap = 2, create = createTitleRow, update = updateTitleRow,
    empty = { glyph = "trophy", title = L["Aucun titre"], text = L["Les titres tombent avec les premières morts."] },
  })
  self.titles:SetPoint("TOPLEFT", titles, "TOPLEFT", 10, -34)
  self.titles:SetPoint("BOTTOMRIGHT", titles, "BOTTOMRIGHT", -6, 8)
  self.titles.empty:SetScale(0.85)

  local recentCaps = UI.Caps(frame, L["DERNIÈRES MORTS"])
  recentCaps:SetPoint("TOPLEFT", self.top, "BOTTOMLEFT", 4, -18)
  self.recent = UI.List(frame, {
    rowHeight = 58, gap = 4, create = createDeathRow, update = updateDeathRow,
    empty = { glyph = "heart", title = L["Personne n'est encore mort"], text = L["Profitez-en, ça ne durera pas."] },
  })
  self.recent:SetPoint("TOPLEFT", self.top, "BOTTOMLEFT", 0, -36)
  self.recent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  self.podiumEmpty = UI.Empty(self.podium, "skull", L["Podium vide"], L["Le premier à mourir aura l'honneur d'inaugurer le Hall of Shame."])
end

function View:LayoutPodium()
  local w = self.podium:GetWidth() or 0
  if w <= 0 then return end
  local gap = 10
  local cw = math.floor((w - gap * 2) / 3)
  -- ordre visuel : 2e, 1er, 3e ; le premier est plus haut
  local slots = { { i = 2, x = 0, h = TOP_H - 22 }, { i = 1, x = cw + gap, h = TOP_H }, { i = 3, x = (cw + gap) * 2, h = TOP_H - 34 } }
  for _, slot in ipairs(slots) do
    local card = self.cards[slot.i]
    card:ClearAllPoints()
    card:SetPoint("BOTTOMLEFT", self.podium, "BOTTOMLEFT", slot.x, 0)
    card:SetSize(cw, slot.h)
  end
end

function View:Refresh()
  local board = ns.Deaths:Leaderboard()
  local anyDeath = board[1] and board[1].count > 0
  self.podiumEmpty:SetShown(not anyDeath)
  local titles = ns.Deaths:Titles()
  local titleOf = {}
  for _, t in ipairs(titles) do titleOf[t.name] = titleOf[t.name] or t.title end
  for i = 1, 3 do
    local card, row = self.cards[i], board[i]
    if anyDeath and row then
      card:Show()
      card.m = row.m
      local medal = MEDALS[i]
      UI.SetColor(card.medal, medal)
      card.rank:SetText(tostring(i))
      card.glow:SetVertexColor(medal[1], medal[2], medal[3], i == 1 and 0.22 or 0.1)
      card.avatar:SetMember(row.m, ns.Store:IsOnline(row.name))
      local r, g, b = U.ClassColor(row.m.class)
      card.name:SetText(U.Short(row.name))
      card.name:SetTextColor(r, g, b)
      card.count:SetText(tostring(row.count))
      card.unit:SetText(row.count == 1 and L["mort"] or L["morts"])
      local title = titleOf[row.name]
      if title then
        card.title:Set(title, C.gold, "trophy")
        card.title:Show()
      else
        card.title:Hide()
      end
    else
      card:Hide()
    end
  end
  self:LayoutPodium()
  self.titles:SetData(titles, true)
  self.recent:SetData(ns.Deaths:Recent(80), true)
end

ns.Window:Register(View)
