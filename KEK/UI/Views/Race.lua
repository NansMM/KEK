-- KEK — vue « Course au 60 » : pistes de course, estimation d'arrivée et courbe niveau / temps de jeu.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local View = { id = "race", order = 5, label = L["Course au 60"], title = L["Course au 60"], glyph = "flag" }

local LANE_H, LANES_MAX = 44, 5
local NAME_W, ETA_W = 132, 142

local function racers()
  local list = {}
  for name, m in pairs(ns.db.members) do
    local level = (m.level or 0) + ((m.level or 0) < ns.MAX_LEVEL and (m.xp or 0) or 0)
    if name == ns.me then level = ns.Race:Progress() end
    if level > 0 then list[#list + 1] = { name = name, m = m, level = level } end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
  end)
  return list
end

function View:Subtitle()
  local list = racers()
  if #list == 0 then return "" end
  local leader = list[1]
  if leader.level >= ns.MAX_LEVEL then
    return string.format(L["%s a franchi la ligne d'arrivée"], U.Short(leader.name))
  end
  return string.format(L["%s mène la course, niveau %s"], U.Short(leader.name), string.format("%.1f", leader.level):gsub("%.", ","))
end

-- ------------------------------------------------------------------ pistes
local function createLane(list)
  local row = CreateFrame("Frame", nil, list)
  row:EnableMouse(true)
  row.name = UI.Title(row, 13)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -7)
  row.name:SetWidth(NAME_W - 10)
  row.sub = UI.Text(row, 11, C.faint)
  row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)

  row.track = CreateFrame("Frame", nil, row)
  row.track:SetHeight(8)
  row.track:SetPoint("LEFT", row, "LEFT", NAME_W, 0)
  row.track:SetPoint("RIGHT", row, "RIGHT", -ETA_W, 0)
  row.track.bg = UI.Round(row.track, 4, { 1, 1, 1, 0.05 })
  row.fill = CreateFrame("Frame", nil, row.track)
  row.fill:SetPoint("TOPLEFT")
  row.fill:SetPoint("BOTTOMLEFT")
  row.fill.bg = UI.Round(row.fill, 4, C.accent)
  row.trail = row.track:CreateTexture(nil, "ARTWORK")
  row.trail:SetTexture(UI.Media("grad-h"))
  row.trail:SetTexCoord(1, 0, 0, 1)
  row.trail:SetHeight(20)
  row.ticks = {}
  for i = 1, 5 do
    local t = UI.Line(row.track, { 1, 1, 1, 0.10 }, "BORDER")
    t:SetSize(1, 14)
    row.ticks[i] = t
  end
  -- ligne d'arrivée en damier
  row.finish = {}
  for i = 0, 7 do
    local sq = row:CreateTexture(nil, "ARTWORK")
    sq:SetTexture(UI.WHITE)
    sq:SetSize(4, 4)
    local col, line = i % 2, math.floor(i / 2)
    sq:SetPoint("LEFT", row.track, "RIGHT", 6 + col * 4, 6 - line * 4)
    if (col + line) % 2 == 0 then sq:SetVertexColor(0.9, 0.9, 0.9, 0.85) else sq:SetVertexColor(0.15, 0.15, 0.18, 0.85) end
    row.finish[#row.finish + 1] = sq
  end

  row.runner = UI.Avatar(row, 28)
  row.runner:SetFrameLevel(row:GetFrameLevel() + 5)
  row.crown = UI.Glyph(row.runner, "crown", 14, C.gold, "OVERLAY", 3)
  row.crown:SetPoint("BOTTOM", row.runner, "TOP", 0, -3)

  row.eta = UI.Text(row, 13, C.text)
  row.eta:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -7)
  row.eta:SetJustifyH("RIGHT")
  row.etaSub = UI.Text(row, 11, C.faint)
  row.etaSub:SetPoint("TOPRIGHT", row.eta, "BOTTOMRIGHT", 0, -4)
  row.etaSub:SetJustifyH("RIGHT")

  UI.Tip(row, function(tt, self) if self.m then ns.RosterView.MemberTooltip(tt, self.m) end end, "ANCHOR_CURSOR")
  return row
end

local function updateLane(row, item, index)
  local m = item.m
  row.m = m
  local online = ns.Store:IsOnline(item.name)
  local r, g, b = U.ClassColor(m.class)
  row.name:SetText(U.Short(item.name))
  row.name:SetTextColor(r, g, b)
  row.sub:SetText(string.format(L["niveau %s"], (string.format("%.1f", item.level):gsub("%.", ","))))

  local w = (row:GetWidth() or 0) - NAME_W - ETA_W
  local frac = U.Clamp((item.level - 1) / (ns.MAX_LEVEL - 1), 0, 1)
  for i, t in ipairs(row.ticks) do
    t:ClearAllPoints()
    t:SetPoint("CENTER", row.track, "LEFT", w * (i * 10 - 1) / (ns.MAX_LEVEL - 1), 0)
  end
  local x = math.max(8, w * frac)
  row.fill:SetWidth(x)
  row.fill.bg:SetColor(r, g, b, 0.55)
  row.trail:ClearAllPoints()
  row.trail:SetPoint("RIGHT", row.track, "LEFT", x, 0)
  row.trail:SetWidth(math.min(90, x))
  row.trail:SetVertexColor(r, g, b, 0.22)
  row.runner:ClearAllPoints()
  row.runner:SetPoint("CENTER", row.track, "LEFT", x, 0)
  row.runner:SetMember(m, online, false)
  row.crown:SetShown(index == 1)

  if item.level >= ns.MAX_LEVEL then
    row.eta:SetText(L["Arrivé !"])
    UI.SetTextColor(row.eta, C.gold)
    row.etaSub:SetText(m.played and string.format(L["en %s de jeu"], U.Played(m.played)) or "")
  elseif m.eta and m.eta > 0 then
    row.eta:SetText(string.format(L["≈ %s de jeu"], U.Duration(m.eta * 3600)))
    UI.SetTextColor(row.eta, C.text)
    row.etaSub:SetText(m.etaDate and string.format(L["vers le %s"], U.ShortDate(m.etaDate)) or L["date à confirmer"])
  else
    row.eta:SetText(L["rythme inconnu"])
    UI.SetTextColor(row.eta, C.faint)
    row.etaSub:SetText(L["encore 30 min de jeu"])
  end
end

-- ------------------------------------------------------------------ graphique
local function niceStep(maxHours)
  for _, step in ipairs({ 1, 2, 5, 10, 20, 25, 50, 100, 200, 500 }) do
    if maxHours / step <= 6 then return step end
  end
  return 1000
end

function View:BuildChart(frame)
  local card = UI.Card(frame, { radius = 12, fill = C.card })
  self.chart = card
  local caps = UI.Caps(card, L["NIVEAU SELON LE TEMPS DE JEU"])
  caps:SetPoint("TOPLEFT", 16, -14)

  local plot = CreateFrame("Frame", nil, card)
  plot:SetPoint("TOPLEFT", card, "TOPLEFT", 44, -38)
  plot:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -70, 30)
  plot:EnableMouse(true)
  self.plot = plot
  self.grid, self.yLabels, self.xLabels, self.xTicks = {}, {}, {}, {}
  for i = 1, 6 do
    local line = UI.Line(plot, { 1, 1, 1, 0.05 }, "BACKGROUND")
    line:SetHeight(1)
    self.grid[i] = line
    local label = UI.Text(card, 10, C.faint)
    label:SetJustifyH("RIGHT")
    self.yLabels[i] = label
  end
  self.lines, self.dots, self.tags = {}, {}, {}
  self.cross = UI.Line(plot, { 1, 1, 1, 0.18 }, "OVERLAY")
  self.cross:SetWidth(1)
  self.cross:Hide()
  self.empty = UI.Empty(card, "flag", L["La courbe se dessine en jouant"], L["Chaque membre ajoute un point toutes les 20 minutes de jeu et à chaque niveau."])

  plot:SetScript("OnSizeChanged", function() self:DrawChart() end)
  plot:SetScript("OnLeave", function()
    self.cross:Hide()
    GameTooltip:Hide()
    plot.lastX = nil
  end)
  plot:SetScript("OnUpdate", function(p)
    if not p:IsMouseOver() or not self.series or #self.series == 0 then return end
    local scale = p:GetEffectiveScale()
    local cx = GetCursorPosition() / scale - (p:GetLeft() or 0)
    if p.lastX and math.abs(cx - p.lastX) < 1 then return end
    p.lastX = cx
    local w = p:GetWidth()
    local hours = U.Clamp(cx / w, 0, 1) * self.maxHours
    self.cross:ClearAllPoints()
    self.cross:SetPoint("TOP", p, "TOPLEFT", cx, 0)
    self.cross:SetPoint("BOTTOM", p, "BOTTOMLEFT", cx, 0)
    self.cross:Show()
    GameTooltip:SetOwner(p, "ANCHOR_CURSOR")
    GameTooltip:AddLine(string.format(L["Après %s de jeu"], U.Duration(hours * 3600)), 1, 1, 1)
    local rows = {}
    for _, s in ipairs(self.series) do
      local pts, level = s.pts, nil
      for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if hours * 60 >= a.p and hours * 60 <= b.p then
          local t = (b.p > a.p) and (hours * 60 - a.p) / (b.p - a.p) or 0
          level = a.l + (b.l - a.l) * t
          break
        end
      end
      if level then rows[#rows + 1] = { s = s, level = level } end
    end
    table.sort(rows, function(a, b) return a.level > b.level end)
    for _, row in ipairs(rows) do
      local r, g, b = U.ClassColor(row.s.m.class)
      GameTooltip:AddDoubleLine(U.Short(row.s.name), (string.format("%.1f", row.level):gsub("%.", ",")), r, g, b, 1, 1, 1)
    end
    if #rows == 0 then GameTooltip:AddLine(L["Personne n'avait encore joué autant"], 0.6, 0.62, 0.68) end
    GameTooltip:Show()
  end)
end

function View:DrawChart()
  local plot = self.plot
  local w, h = plot:GetWidth() or 0, plot:GetHeight() or 0
  for _, l in ipairs(self.lines) do l:Hide() end
  for _, d in ipairs(self.dots) do d:Hide() end
  for _, t in ipairs(self.tags) do t:Hide() end
  for _, t in ipairs(self.xLabels) do t:Hide() end
  for _, t in ipairs(self.xTicks) do t:Hide() end
  if w <= 0 or h <= 0 then return end

  local series = self.series or {}
  self.empty:SetShown(#series == 0)
  local maxHours = 1
  for _, s in ipairs(series) do
    local last = s.pts[#s.pts]
    if last then maxHours = math.max(maxHours, last.p / 60) end
  end
  maxHours = maxHours * 1.04
  self.maxHours = maxHours

  -- grille horizontale (niveaux)
  for i = 1, 6 do
    local level = i * 10
    local y = (level - 1) / (ns.MAX_LEVEL - 1) * h
    local line = self.grid[i]
    line:ClearAllPoints()
    line:SetPoint("LEFT", plot, "BOTTOMLEFT", 0, y)
    line:SetPoint("RIGHT", plot, "BOTTOMRIGHT", 0, y)
    local label = self.yLabels[i]
    label:ClearAllPoints()
    label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -8, y)
    label:SetText(tostring(level))
  end
  -- graduations horizontales (heures)
  local step = niceStep(maxHours)
  local n = 0
  for hour = step, maxHours, step do
    n = n + 1
    local x = hour / maxHours * w
    local label = self.xLabels[n]
    if not label then
      label = UI.Text(self.chart, 10, C.faint)
      self.xLabels[n] = label
      self.xTicks[n] = UI.Line(plot, { 1, 1, 1, 0.08 }, "BACKGROUND")
    end
    label:ClearAllPoints()
    label:SetPoint("TOP", plot, "BOTTOMLEFT", x, -8)
    label:SetText(hour .. " h")
    label:Show()
    local tick = self.xTicks[n]
    tick:ClearAllPoints()
    tick:SetPoint("BOTTOM", plot, "BOTTOMLEFT", x, 0)
    tick:SetSize(1, 5)
    tick:Show()
  end

  local useLines = plot.CreateLine ~= nil
  local li, di = 0, 0
  local function point(pt)
    return pt.p / 60 / maxHours * w, U.Clamp((pt.l - 1) / (ns.MAX_LEVEL - 1), 0, 1) * h
  end
  for si, s in ipairs(series) do
    local r, g, b = U.ClassColor(s.m.class)
    local pts = s.pts
    local stride = math.max(1, math.floor(#pts / 90))
    local prevX, prevY
    for i = 1, #pts, stride do
      local x, y = point(pts[i])
      if i + stride > #pts and i ~= #pts then x, y = point(pts[#pts]) end
      if prevX then
        if useLines then
          li = li + 1
          local line = self.lines[li]
          if not line then
            line = plot:CreateLine(nil, "ARTWORK")
            line:SetThickness(2)
            self.lines[li] = line
          end
          line:SetColorTexture(r, g, b, 0.9)
          line:SetStartPoint("BOTTOMLEFT", plot, prevX, prevY)
          line:SetEndPoint("BOTTOMLEFT", plot, x, y)
          line:Show()
        else
          di = di + 1
          local dot = self.dots[di] or plot:CreateTexture(nil, "ARTWORK")
          self.dots[di] = dot
          dot:SetTexture(UI.Media("circle"))
          dot:SetSize(4, 4)
          dot:SetVertexColor(r, g, b, 0.9)
          dot:ClearAllPoints()
          dot:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
          dot:Show()
        end
      end
      prevX, prevY = x, y
    end
    -- point final et étiquette
    if prevX then
      di = di + 1
      local dot = self.dots[di] or plot:CreateTexture(nil, "OVERLAY")
      self.dots[di] = dot
      dot:SetTexture(UI.Media("circle"))
      dot:SetSize(8, 8)
      dot:SetVertexColor(r, g, b, 1)
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", plot, "BOTTOMLEFT", prevX, prevY)
      dot:Show()
      local tag = self.tags[si]
      if not tag then
        tag = UI.Text(self.chart, 10, C.text)
        self.tags[si] = tag
      end
      tag:SetText(U.Short(s.name))
      tag:SetTextColor(r, g, b)
      tag:ClearAllPoints()
      tag:SetPoint("LEFT", plot, "BOTTOMLEFT", prevX + 7, prevY)
      tag:Show()
    end
  end
end

-- ------------------------------------------------------------------ construction
function View:Build(frame)
  self.frame = frame
  self.lanes = UI.List(frame, {
    rowHeight = LANE_H - 4, gap = 4, create = createLane, update = updateLane,
    empty = { glyph = "flag", title = L["Aucun coureur"], text = L["La course démarre dès que la bande est connectée."] },
  })
  self.lanes:SetPoint("TOPLEFT", 0, 0)
  self.lanes:SetPoint("TOPRIGHT", 0, 0)
  self.lanes:SetHeight(LANE_H * 3)
  self.lanes.empty:SetScale(0.8)
  self:BuildChart(frame)
  self.chart:SetPoint("TOPLEFT", self.lanes, "BOTTOMLEFT", 0, -14)
  self.chart:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
end

function View:Refresh()
  local list = racers()
  self.lanes:SetHeight(LANE_H * U.Clamp(#list, 1, LANES_MAX))
  self.lanes:SetData(list, true)
  local series = {}
  for _, r in ipairs(list) do
    local pts = ns.Race:Series(r.name)
    if #pts >= 1 then
      -- une courbe commence au niveau 1, temps de jeu 0
      local full = { { p = 0, l = 1 } }
      for _, pt in ipairs(pts) do full[#full + 1] = pt end
      series[#series + 1] = { name = r.name, m = r.m, pts = full }
    end
  end
  self.series = series
  self:DrawChart()
end

ns.Window:Register(View)
