-- KEK — vue « Coffre » : les objets LQE et les sacs que la bande garde (sacs, banque, banque de guilde),
-- avec ceux qui intéressent ton personnage en tête.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local View = { id = "chest", order = 7, label = L["Coffre"], title = L["Le coffre"], glyph = "chest" }

local FILTERS = {
  { value = "all", label = L["Tout"] },
  { value = "forme", label = L["Pour moi"] },
  { value = "mine", label = L["Mes objets"] },
}

local function filter() return ns.db.ui.chestFilter or "all" end

function View:Subtitle()
  local all = ns.Boe:All()
  if #all == 0 then return L["Les objets LQE de la bande, et qui les garde"] end
  local forMe = ns.Boe:ForMe()
  local text = string.format(#all == 1 and L["%d objet dans la bande"] or L["%d objets dans la bande"], #all)
  if forMe > 0 then text = text .. " · " .. string.format(L["%d pour toi"], forMe) end
  return text
end

function View:Badge()
  local n = ns.Boe:ForMe()
  return n > 0 and n or nil
end

local function ownerLabel(e)
  if e.guild then return string.format(L["Banque de guilde « %s »"], e.owner) end
  if e.owner == ns.me then return L["Toi"] end
  return U.MemberName(e.owner)
end

local function whereText(e)
  local where = e.guild and ownerLabel(e) or (ownerLabel(e) .. " · " .. (ns.Boe.PLACES[e.place] or "?"))
  if e.t and ns.Now() - e.t > 3600 then where = where .. " · " .. string.format(L["vu %s"], U.Ago(e.t)) end
  return where
end

local function describe(info)
  if not info then return L["objet en cours de chargement…"] end
  local parts = {}
  if info.classID == 9 then
    parts[1] = string.format(L["Recette · %s"], info.subType or "?")
  elseif info.classID == 1 then
    parts[1] = L["Sac"]
  else
    if info.equipLoc then parts[#parts + 1] = ns.Boe.SLOT_NAMES[info.equipLoc] or info.equipLoc end
    if info.subType and info.subType ~= "" then parts[#parts + 1] = info.subType end
    if info.ilvl > 0 then parts[#parts + 1] = string.format(L["niveau d'objet %d"], info.ilvl) end
  end
  if info.minLevel > 1 then parts[#parts + 1] = string.format(L["niv. %d requis"], info.minLevel) end
  return table.concat(parts, " · ")
end

local function linkOf(s)
  local _, link = U.GetItemInfo(s)
  return link
end

local function ask(e)
  U.WithItemLink(U.ItemID(e.s), function(base)
    local link = linkOf(e.s) or base or e.s
    U.OpenChat("/w " .. e.owner .. " " .. string.format(L["Salut ! Ton %s m'intéresse, tu veux bien me le passer ?"], link))
  end)
end

local function buildData(query)
  local q = U.Fold(query or "")
  local mode = filter()
  local data = {}
  for _, e in ipairs(ns.Boe:All()) do
    local info = ns.Boe:Info(e.s)
    local reason = e.owner ~= ns.me and ns.Boe:Interest(e.s) or nil
    local name = info and info.name or ""
    local keep = (mode == "all") or (mode == "forme" and reason ~= nil) or (mode == "mine" and e.mine)
    if keep and q ~= "" then keep = U.Fold(name):find(q, 1, true) ~= nil or U.Fold(ownerLabel(e)):find(q, 1, true) ~= nil end
    if keep then data[#data + 1] = { e = e, info = info, reason = reason, name = name } end
  end
  table.sort(data, function(a, b)
    if (a.reason ~= nil) ~= (b.reason ~= nil) then return a.reason ~= nil end
    local qa, qb = a.info and a.info.q or 0, b.info and b.info.q or 0
    if qa ~= qb then return qa > qb end
    if a.name ~= b.name then return a.name < b.name end
    return a.e.owner < b.e.owner
  end)
  return data
end

local function createRow(list)
  local row = CreateFrame("Button", nil, list)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.Hoverable(row, 10)
  row.icon = UI.ItemIcon(row, 40)
  row.icon:SetPoint("LEFT", 10, 0)
  row.name = UI.Title(row, 13)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 62, -10)
  row.count = UI.Title(row, 13, C.muted)
  row.count:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.sub = UI.Text(row, 11, C.faint)
  row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
  row.where = UI.Text(row, 11, C.muted)
  row.where:SetPoint("TOPLEFT", row.sub, "BOTTOMLEFT", 0, -3)
  row.forMe = UI.Chip(row, 22)
  row.ask = UI.Button(row, { text = L["Demander"], icon = "chat", style = "secondary", h = 26, size = 12 })
  row.ask:SetPoint("RIGHT", row, "RIGHT", -12, 0)
  UI.Tip(row, function(tt, self)
    local data = self.data
    if not data then return end
    local link = linkOf(data.e.s)
    if link then pcall(tt.SetHyperlink, tt, link) else tt:AddLine(data.name ~= "" and data.name or data.e.s, 1, 1, 1) end
    tt:AddLine(" ")
    tt:AddLine(whereText(data.e), 1, 0.82, 0.5)
    if data.reason then tt:AddLine(string.format(L["Pour toi : %s"], data.reason), 0.38, 0.86, 0.56, true) end
    tt:AddLine(" ")
    tt:AddLine(L["Clic droit : demander, ajouter à tes besoins · Maj+clic : lien dans le chat"], 0.5, 0.52, 0.58, true)
  end, "ANCHOR_CURSOR")
  row:SetScript("OnClick", function(self, button)
    local data = self.data
    if not data then return end
    local e = data.e
    if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") then
      U.WithItemLink(U.ItemID(e.s), function(base) U.InsertLink(linkOf(e.s) or base) end)
      return
    end
    if button == "RightButton" then
      local menu = {}
      if not e.mine and not e.guild then
        menu[#menu + 1] = { label = string.format(L["Demander à %s"], U.Short(e.owner)), glyph = "chat", onClick = function() ask(e) end }
      end
      if not e.mine then
        menu[#menu + 1] = { label = L["Ajouter à mes besoins"], glyph = "plus", onClick = function()
          ns.Craft:AddNeed(linkOf(e.s) or { id = U.ItemID(e.s), name = data.name ~= "" and data.name or nil }, 1, "")
        end }
      end
      if #menu > 0 then UI.Menu(nil, menu, { cursor = true }) end
    end
  end)
  return row
end

local function updateRow(row, data)
  row.data = data
  local e, info = data.e, data.info
  row.icon:SetItem(U.ItemIcon(U.ItemID(e.s)), info and info.q)
  row.name:SetText(data.name ~= "" and data.name or "…")
  if info then
    local r, g, b = U.QualityColor(info.q)
    row.name:SetTextColor(r, g, b)
  else
    UI.SetTextColor(row.name, C.text)
  end
  row.name:SetWidth(math.min(row.name:GetStringWidth() + 4, row:GetWidth() * 0.45))
  row.count:SetText((e.n or 1) > 1 and ("×" .. e.n) or "")
  row.sub:SetText(describe(info))
  row.sub:SetWidth(row:GetWidth() * 0.55)
  row.where:SetText(whereText(e))
  row.where:SetWidth(row:GetWidth() * 0.55)
  if not e.guild and not e.mine then
    local m = ns.db.members[e.owner]
    local r, g, b = U.ClassColor(m and m.class)
    row.where:SetTextColor(r, g, b, 0.9)
  else
    UI.SetTextColor(row.where, C.muted)
  end

  local canAsk = not e.mine and not e.guild
  row.ask:SetShown(canAsk)
  row.ask:SetScript("OnClick", function() U.Click(); ask(e) end)
  row.forMe:ClearAllPoints()
  row.forMe:SetPoint("RIGHT", canAsk and row.ask or row, canAsk and "LEFT" or "RIGHT", canAsk and -10 or -12, 0)
  if data.reason then
    row.forMe:Set(L["Pour toi"], C.good, "check")
    row.forMe:Show()
  else
    row.forMe:Hide()
  end
end

function View:Build(frame, actions)
  self.frame = frame
  local search = UI.Input(frame, { placeholder = L["Rechercher un objet, un membre…"], icon = "search", max = 60, onChange = function(text)
    self.query = text
    ns:Debounce("chest-search", 0.12, function() self:Refresh() end)
  end })
  search:SetHeight(34)
  search:SetPoint("TOPLEFT", 0, 0)
  search:SetPoint("TOPRIGHT", 0, 0)
  self.search = search

  self.list = UI.List(frame, {
    gap = 4, rowHeight = 62, create = createRow, update = updateRow,
    empty = { glyph = "chest", title = L["Le coffre est vide"], text = L["Les objets « Lié quand équipé » et les sacs que la bande garde (sacs, banque, banque de guilde) apparaîtront ici. Ouvre ta banque une fois pour que KEK la compte."] },
  })
  self.list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -14)
  self.list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  local seg = UI.Segmented(actions, FILTERS, filter(), function(v)
    ns.db.ui.chestFilter = v
    self:Refresh()
  end, { pad = 16 })
  seg:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
end

function View:Refresh()
  local data = buildData(self.query)
  self.list:SetData(data, true)
  if self.list.empty and #data == 0 then
    local mode = filter()
    if mode == "forme" then
      self.list.empty:Set("chest", L["Rien pour toi pour l'instant"], L["KEK te prévient dès qu'un ami ramasse un objet LQE qui t'intéresse : ta classe peut le porter, ton niveau le permet bientôt, il est meilleur que ce que tu portes, ou c'est une recette de ton métier que tu n'as pas."])
    elseif mode == "mine" then
      self.list.empty:Set("chest", L["Aucun objet LQE sur tes personnages"], L["Ouvre ta banque une fois par personnage pour que KEK la compte."])
    else
      self.list.empty:Set("chest", L["Le coffre est vide"], L["Les objets « Lié quand équipé » et les sacs que la bande garde (sacs, banque, banque de guilde) apparaîtront ici. Ouvre ta banque une fois pour que KEK la compte."])
    end
  end
end

ns.Window:Register(View)
