-- KEK — vue « Soirée » : ton récap en direct et le palmarès de la bande ce soir.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local View = { id = "session", order = 4, label = L["Soirée"], title = L["Ta soirée"], glyph = "moon" }

local TILES = {
  { key = "xp", label = L["XP GAGNÉE"], glyph = "arrowup", color = C.gold,
    value = function(s) return U.Compact(s.xp or 0) end,
    sub = function(s) return (s.lv or 0) > 0 and string.format(L["+%d niveau(x)"], s.lv) or L["aucun niveau"] end },
  { key = "g", label = L["OR"], glyph = "bag", color = C.gold,
    value = function(s) return U.Money(s.g or 0, true, true) end,
    sub = function(s) return string.format(L["%s encaissés"], U.Money(s.gi or 0, false, true)) end },
  { key = "k", label = L["ENNEMIS ACHEVÉS"], glyph = "sword", color = C.accent,
    value = function(s) return U.Num(s.k or 0) end,
    sub = function(s) return (s.d or 0) > 0 and string.format(L["%.1f / minute"], (s.k or 0) / math.max(1, (s.d or 0) / 60)) or "" end },
  { key = "q", label = L["QUÊTES"], glyph = "check", color = C.good,
    value = function(s) return U.Num(s.q or 0) end,
    sub = function(s) return (s.d or 0) >= 600 and string.format(L["%.1f / heure"], (s.q or 0) * 3600 / s.d) or L["rendues au PNJ"] end },
  { key = "de", label = L["MORTS"], glyph = "skull", color = C.bad,
    value = function(s) return U.Num(s.de or 0) end,
    sub = function(s) return (s.de or 0) == 0 and L["impeccable"] or L["ça arrive"] end },
  { key = "xph", label = L["RYTHME"], glyph = "hourglass", color = C.accent,
    value = function(s) return (s.xph or 0) > 0 and U.Compact(s.xph) or "—" end,
    sub = function(s) return (s.xph or 0) > 0 and L["XP par heure de jeu"] or L["après 10 minutes de jeu"] end },
  { key = "zc", label = L["ZONES"], glyph = "pin", color = C.good,
    value = function(s) return U.Num(s.zc or 0) end,
    sub = function(s) return (s.zc or 0) >= 3 and L["l'âme d'un explorateur"] or L["zones visitées"] end },
  { key = "it", label = L["OBJETS RAMASSÉS"], glyph = "star", color = C.info,
    value = function(s) return U.Num(s.it or 0) end,
    sub = function() return L["butin, quêtes, artisanat"] end },
}

function View:Current()
  if ns.db.ui.sessionTab == "last" then return ns.Session:Last() end
  return ns.Session:Current()
end

function View:Subtitle()
  local s = self:Current()
  if not s then return L["Aucune soirée archivée pour ce personnage"] end
  if ns.db.ui.sessionTab == "last" then
    return string.format(L["Soirée du %s, de %s à %s"], U.ShortDate(s.s), U.Clock(s.s), U.Clock(s.u))
  end
  return string.format(L["En cours depuis %s · %s"], U.Clock(s.s), U.Duration(s.d))
end

local function createTile(parent, def)
  local t = UI.Card(parent, { radius = 10, fill = C.cardHi, edge = { 1, 1, 1, 0.04 } })
  t.glyph = UI.Glyph(t, def.glyph, 12, def.color)
  t.glyph:SetPoint("TOPLEFT", 12, -12)
  t.label = UI.Caps(t, def.label)
  t.label:SetPoint("LEFT", t.glyph, "RIGHT", 6, 0)
  t.value = UI.Title(t, 18, C.text)
  t.value:SetPoint("TOPLEFT", 12, -30)
  t.sub = UI.Text(t, 11, C.faint)
  t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
  t.def = def
  return t
end

local function createAward(parent)
  local a = UI.Card(parent, { radius = 10, fill = C.card })
  a.badge = UI.Badge(a, 34, "star")
  a.badge:SetPoint("LEFT", 12, 0)
  a.title = UI.Title(a, 12, C.gold)
  a.title:SetPoint("TOPLEFT", a, "TOPLEFT", 56, -12)
  a.name = UI.Text(a, 13, C.text)
  a.name:SetPoint("TOPLEFT", a.title, "BOTTOMLEFT", 0, -4)
  a.value = UI.Text(a, 11, C.muted)
  a.value:SetPoint("TOPLEFT", a.name, "BOTTOMLEFT", 0, -3)
  UI.Tip(a, function(tt, self) if self.m then ns.RosterView.MemberTooltip(tt, self.m) end end)
  return a
end

function View:Build(frame, actions)
  self.frame = frame

  -- carte principale
  local hero = UI.Card(frame, { radius = 14, fill = C.card })
  hero:SetPoint("TOPLEFT", 0, 0)
  hero:SetPoint("TOPRIGHT", 0, 0)
  hero:SetHeight(164)
  self.hero = hero
  local glow = hero:CreateTexture(nil, "BORDER")
  glow:SetTexture(UI.Media("glow"))
  glow:SetSize(260, 260)
  glow:SetPoint("CENTER", hero, "TOPLEFT", 60, -40)
  glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.16)
  local moon = UI.Glyph(hero, "moon", 16, C.accent)
  moon:SetPoint("TOPLEFT", 18, -18)
  local durCaps = UI.Caps(hero, L["DURÉE"])
  durCaps:SetPoint("LEFT", moon, "RIGHT", 6, 0)
  self.duration = UI.Title(hero, 32, C.text)
  self.duration:SetPoint("TOPLEFT", 18, -44)
  self.since = UI.Text(hero, 12, C.muted)
  self.since:SetPoint("TOPLEFT", self.duration, "BOTTOMLEFT", 0, -6)
  self.best = UI.ItemIcon(hero, 26)
  self.best:SetPoint("BOTTOMLEFT", 18, 16)
  self.bestText = UI.Text(hero, 12, C.text)
  self.bestText:SetPoint("LEFT", self.best, "RIGHT", 8, 0)
  self.bestText:SetWidth(170)
  self.bestHit = CreateFrame("Frame", nil, hero)
  self.bestHit:SetPoint("TOPLEFT", self.best, "TOPLEFT")
  self.bestHit:SetSize(200, 26)
  self.bestHit:EnableMouse(true)
  UI.Tip(self.bestHit, function(tt)
    local s = self:Current()
    if s and s.b then pcall(tt.SetHyperlink, tt, s.b) else tt:AddLine(L["Pas encore de butin notable"]) end
  end)

  self.grid = CreateFrame("Frame", nil, hero)
  self.grid:SetPoint("TOPLEFT", hero, "TOPLEFT", 226, -12)
  self.grid:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -12, 12)
  self.tiles = {}
  for i, def in ipairs(TILES) do self.tiles[i] = createTile(self.grid, def) end
  self.grid:SetScript("OnSizeChanged", function() self:LayoutTiles() end)

  -- palmarès de la bande
  local caps = UI.Caps(frame, L["LA BANDE CE SOIR"])
  caps:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 4, -20)
  self.caps = caps
  self.tonight = UI.Text(frame, 11, C.faint)
  self.tonight:SetPoint("LEFT", caps, "RIGHT", 8, 0)
  self.awardsFrame = CreateFrame("Frame", nil, frame)
  self.awardsFrame:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -38)
  self.awardsFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  self.awards = {}
  for i = 1, 8 do self.awards[i] = createAward(self.awardsFrame) end
  self.awardsFrame:SetScript("OnSizeChanged", function() self:LayoutAwards() end)
  self.awardsEmpty = UI.Empty(self.awardsFrame, "moon", L["Soirée calme"], L["Quand tes amis jouent ce soir, leurs exploits et leurs titres de la soirée s'affichent ici."])

  self.lastEmpty = UI.Empty(frame, "moon", L["Pas encore de soirée archivée"], L["Une soirée de plus de 5 minutes est archivée à ta prochaine connexion."])

  -- actions
  local share = UI.Button(actions, { text = L["Partager"], icon = "chat", style = "secondary", h = 28, tooltip = L["Envoie ton récap dans le chat de groupe ou de guilde"], onClick = function()
    ns.Session:Share()
  end })
  share:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
  self.share = share
  local tabs = UI.Segmented(actions, {
    { value = "current", label = L["Ce soir"] },
    { value = "last", label = L["Dernière soirée"] },
  }, ns.db.ui.sessionTab, function(v)
    ns.db.ui.sessionTab = v
    ns.Window:Refresh()
  end)
  tabs:SetPoint("RIGHT", share, "LEFT", -10, 0)
end

function View:LayoutTiles()
  local w, h = self.grid:GetWidth() or 0, self.grid:GetHeight() or 0
  if w <= 0 then return end
  local gap = 8
  local tw, th = math.floor((w - gap * 3) / 4), math.floor((h - gap) / 2)
  for i, tile in ipairs(self.tiles) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", self.grid, "TOPLEFT", col * (tw + gap), -row * (th + gap))
    tile:SetSize(tw, th)
    tile.value:SetWidth(tw - 20)
    tile.sub:SetWidth(tw - 20)
  end
end

function View:LayoutAwards()
  local w = self.awardsFrame:GetWidth() or 0
  if w <= 0 then return end
  local gap, perRow = 8, 4
  local aw, ah = math.floor((w - gap * (perRow - 1)) / perRow), 70
  for i, a in ipairs(self.awards) do
    local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", self.awardsFrame, "TOPLEFT", col * (aw + gap), -row * (ah + gap))
    a:SetSize(aw, ah)
    a.name:SetWidth(aw - 66)
    a.value:SetWidth(aw - 66)
  end
end

function View:Refresh()
  local isLast = ns.db.ui.sessionTab == "last"
  local s = self:Current()
  self.share:SetShown(not isLast)
  self.lastEmpty:SetShown(s == nil)
  self.hero:SetShown(s ~= nil)
  if s then
    self.duration:SetText(U.Duration(s.d))
    if isLast then
      self.since:SetText(string.format(L["le %s, de %s à %s"], U.ShortDate(s.s), U.Clock(s.s), U.Clock(s.u)))
    else
      self.since:SetText(string.format(L["depuis %s"], U.Clock(s.s)))
    end
    if s.b then
      self.best:SetItem(U.ItemIcon(s.b), s.bq)
      self.bestText:SetText(U.ItemText(s.b, U.ItemID(s.b)))
      UI.SetTextColor(self.bestText, C.text)
    else
      self.best:SetItem(U.QUESTION, nil, true)
      self.bestText:SetText(L["Meilleur butin : rien encore"])
      UI.SetTextColor(self.bestText, C.faint)
    end
    for _, tile in ipairs(self.tiles) do
      tile.value:SetText(tile.def.value(s))
      tile.sub:SetText(tile.def.sub(s) or "")
    end
    self:LayoutTiles()
  end

  -- palmarès (uniquement pour la soirée en cours)
  local awards, count = ns.Session:Awards()
  local showAwards = not isLast and count > 1
  self.caps:SetShown(not isLast)
  self.tonight:SetText(not isLast and string.format(count == 1 and L["%d joueur ce soir"] or L["%d joueurs ce soir"], count) or "")
  self.awardsEmpty:SetShown(not isLast and not showAwards)
  for i, a in ipairs(self.awards) do
    local row = showAwards and awards[i]
    if row then
      a:Show()
      a.m = row.m
      a.badge:Set(row.award.glyph, C.gold)
      a.title:SetText(row.award.title)
      a.name:SetText(U.MemberName(row.name))
      a.value:SetText(row.award.fmt(row.s))
    else
      a:Hide()
    end
  end
  self:LayoutAwards()
end

ns.Window:Register(View)
