-- KEK — vue « Fil » : chronologie des exploits de la bande, groupée par jour.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local View = { id = "feed", order = 2, label = L["Fil"], title = L["Le fil"], glyph = "feed" }

local FILTERS = {
  { value = "all", label = L["Tout"] },
  { value = "level", label = L["Niveaux"] },
  { value = "loot", label = L["Butin"] },
  { value = "death", label = L["Morts"] },
  { value = "boss", label = L["Boss"] },
  { value = "skill", label = L["Métiers"] },
}

function View:Subtitle()
  local today, n = U.DayLabel(ns.Now()), 0
  for _, e in ipairs(ns.db.feed) do
    if U.DayLabel(e.t) == today then n = n + 1 else break end
  end
  if n == 0 then return L["Rien de neuf aujourd'hui… pour l'instant"] end
  return string.format(n == 1 and L["%d événement aujourd'hui"] or L["%d événements aujourd'hui"], n)
end

local function buildData()
  local filter = ns.db.ui.feedFilter
  local data, lastDay = {}, nil
  for _, e in ipairs(ns.db.feed) do
    if filter == "all" or e.k == filter then
      local day = U.DayLabel(e.t)
      if day ~= lastDay then
        data[#data + 1] = { header = day }
        lastDay = day
      end
      data[#data + 1] = { e = e }
    end
  end
  return data
end

local function createRow(list, kind)
  local row = CreateFrame("Button", nil, list)
  if kind == "header" then
    row.label = UI.Caps(row, "")
    row.label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 8)
    row.line = UI.Line(row)
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
    row.line:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    return row
  end
  UI.Hoverable(row, 10)
  row.badge = UI.Badge(row, 36, "star")
  row.badge:SetPoint("LEFT", 10, 0)
  row.item = UI.ItemIcon(row, 36)
  row.item:SetPoint("LEFT", 10, 0)
  row.avatar = UI.Avatar(row, 18)
  row.avatar:SetPoint("BOTTOMRIGHT", row.badge, "BOTTOMRIGHT", 5, -4)
  row.avatar:SetFrameLevel(row:GetFrameLevel() + 4)
  row.title = UI.Text(row, 13, C.text)
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 60, -11)
  row.detail = UI.Text(row, 12, C.muted)
  row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
  row.time = UI.Text(row, 11, C.faint)
  row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -12)
  row.time:SetJustifyH("RIGHT")
  UI.Tip(row, function(tt, self)
    local e = self.e
    if not e then return end
    if e.k == "loot" and e.i then
      pcall(tt.SetHyperlink, tt, e.i)
      return
    end
    local title, detail = ns.Alerts:Describe(e.w, e)
    tt:AddLine(title, 1, 1, 1)
    if detail and detail ~= "" then tt:AddLine(detail, 0.75, 0.76, 0.8, true) end
    if e.k == "death" then
      tt:AddLine(" ")
      tt:AddLine("« " .. ns.Deaths:Epitaph(e) .. " »", 1, 0.82, 0.5, true)
    end
    tt:AddLine(" ")
    tt:AddLine(U.DayLabel(e.t) .. " · " .. U.Clock(e.t), 0.5, 0.52, 0.58)
  end, "ANCHOR_CURSOR")
  row:SetScript("OnClick", function(self)
    local e = self.e
    if e and e.k == "loot" and e.i and IsModifiedClick and IsModifiedClick("CHATLINK") then
      U.InsertLink(e.i)
    end
  end)
  return row
end

local function updateRow(row, item)
  if item.header then
    row.label:SetText(U.Upper(item.header))
    return
  end
  local e = item.e
  row.e = e
  local kind = ns.Alerts.KINDS[e.k] or ns.Alerts.KINDS.level
  local title, detail = ns.Alerts:Describe(e.w, e)
  row.title:SetText(title)
  row.title:SetWidth(row:GetWidth() - 160)
  row.detail:SetText(detail or "")
  row.detail:SetWidth(row:GetWidth() - 90)
  row.time:SetText(U.Ago(e.t))

  local icon, _, quality = ns.Alerts:Icon(e)
  if icon then
    row.badge:Hide()
    row.item:Show()
    row.item:SetItem(icon, quality)
  else
    row.item:Hide()
    row.badge:Show()
    local color = kind.color
    if e.k == "level" and e.l == ns.MAX_LEVEL then color = C.gold end
    row.badge:Set(e.k == "level" and e.l == ns.MAX_LEVEL and "crown" or kind.glyph, color)
  end
  local m = ns.db.members[e.w]
  row.avatar:SetMember(m, true, false)
  row.avatar:SetShown(m ~= nil)
  row.avatar:ClearAllPoints()
  row.avatar:SetPoint("BOTTOMRIGHT", icon and row.item or row.badge, "BOTTOMRIGHT", 5, -4)
end

function View:Build(frame, actions)
  self.list = UI.List(frame, {
    gap = 4,
    kind = function(item) return item.header and "header" or "row" end,
    height = function(_, kind) return kind == "header" and 32 or 56 end,
    create = createRow, update = updateRow,
    empty = { glyph = "feed", title = L["Rien pour l'instant"], text = L["Les exploits de la bande apparaîtront ici : niveaux, butins épiques, morts, boss vaincus…"] },
  })
  self.list:SetAllPoints(frame)
  local seg = UI.Segmented(actions, FILTERS, ns.db.ui.feedFilter, function(v)
    ns.db.ui.feedFilter = v
    self.list:SetData(buildData())
  end, { pad = 16 })
  seg:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
end

function View:Refresh()
  self.list:SetData(buildData(), true)
end

ns.Window:Register(View)
