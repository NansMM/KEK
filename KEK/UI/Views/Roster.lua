-- KEK — vue « La bande » : qui est là, où, à quel niveau, avec quelle spé et quels métiers.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local View = { id = "roster", order = 1, label = L["La bande"], title = L["La bande"], glyph = "users" }

local COLS = { level = 0.38, spec = 0.585, profs = 0.775 }

local function memberList()
  local list = {}
  local showOffline = ns.db.ui.showOffline
  for _, m in ipairs(ns.Store:Members()) do
    local online = ns.Store:IsOnline(m.name)
    if online or showOffline then
      list[#list + 1] = { m = m, online = online }
    end
  end
  local sort = ns.db.ui.rosterSort
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    if sort == "name" then return a.m.name < b.m.name end
    if sort == "recent" then return (a.m.seen or 0) > (b.m.seen or 0) end
    local la, lb = (a.m.level or 0) + (a.m.xp or 0), (b.m.level or 0) + (b.m.xp or 0)
    if la ~= lb then return la > lb end
    return a.m.name < b.m.name
  end)
  return list
end

function View:Subtitle()
  local total, online = 0, 0
  for name in pairs(ns.db.members) do
    total = total + 1
    if ns.Store:IsOnline(name) then online = online + 1 end
  end
  return string.format(L["%d en ligne · %d personnage(s) connus"], online, total)
end

function View:Badge()
  local n = ns.Store:OnlineCount()
  return n > 0 and n or nil
end

-- ------------------------------------------------------------------ infobulle d'un membre
function View.MemberTooltip(tt, m)
  local r, g, b = U.ClassColor(m.class)
  tt:AddLine(U.Short(m.name), r, g, b)
  local line = string.format(L["Niveau %d %s %s"], m.level or 0, m.raceName or "", U.ClassLabel(m.class))
  tt:AddLine(line, 0.8, 0.8, 0.8)
  if m.nick then tt:AddLine(string.format(L["Joué par %s"], m.nick), 0.65, 0.66, 0.72) end
  if m.guild then tt:AddLine("<" .. m.guild .. ">", 0.25, 1, 0.25) end
  tt:AddLine(" ")
  if m.zone then tt:AddDoubleLine(L["Zone"], m.sub and (m.zone .. " · " .. m.sub) or m.zone, 0.6, 0.62, 0.68, 1, 1, 1) end
  if (m.level or 0) < ns.MAX_LEVEL and m.xp then
    tt:AddDoubleLine(L["Progression"], U.Percent(m.xp) .. (m.rested and m.rested > 0 and string.format(L[" · repos %s"], U.Percent(m.rested)) or ""), 0.6, 0.62, 0.68, 1, 1, 1)
  end
  local specName, _, points = ns.Profile.SpecSummary(m.spec)
  if specName then
    local dual = m.spec.g and m.spec.g > 1 and string.format(L[" (spé %d/%d)"], m.spec.a or 1, m.spec.g) or ""
    tt:AddDoubleLine(L["Spécialisation"], specName .. " " .. points .. dual, 0.6, 0.62, 0.68, 1, 1, 1)
  end
  if type(m.profs) == "table" then
    for _, p in ipairs(m.profs) do
      tt:AddDoubleLine("|T" .. U.ProfIcon(p.n) .. ":14:14:0:0:64:64:5:59:5:59|t " .. p.n, string.format("%d / %d", p.r or 0, p.m or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    end
  end
  tt:AddLine(" ")
  tt:AddDoubleLine(L["Morts"], tostring(m.deaths or 0), 0.6, 0.62, 0.68, 1, 1, 1)
  if m.played then tt:AddDoubleLine(L["Temps de jeu"], U.Played(m.played), 0.6, 0.62, 0.68, 1, 1, 1) end
  if m.eta and m.eta > 0 then tt:AddDoubleLine(L["Niveau 60 estimé dans"], string.format(L["≈ %s de jeu"], U.Duration(m.eta * 3600)), 0.6, 0.62, 0.68, 1, 1, 1) end
  if not ns.Store:IsOnline(m.name) then tt:AddDoubleLine(L["Vu"], U.Ago(m.seen), 0.6, 0.62, 0.68, 1, 1, 1) end
  if m.ver then tt:AddLine("KEK " .. m.ver, 0.4, 0.42, 0.48) end
end

-- ------------------------------------------------------------------ lignes
local function createRow(list)
  local row = CreateFrame("Button", nil, list)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.Hoverable(row, 10)
  row.avatar = UI.Avatar(row, 40)
  row.avatar:SetPoint("LEFT", 12, 0)
  row.name = UI.Title(row, 14)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 66, -13)
  row.tag = UI.Chip(row, 16)
  row.tag:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
  row.nick = UI.Text(row, 12, C.faint)
  row.pin = UI.Glyph(row, "pin", 11, C.faint)
  row.pin:SetPoint("TOPLEFT", row, "TOPLEFT", 66, -36)
  row.zone = UI.Text(row, 12, C.muted)
  row.zone:SetPoint("LEFT", row.pin, "RIGHT", 4, 0)

  row.level = UI.Chip(row, 20)
  row.xp = UI.Progress(row, 4)
  row.xp:SetWidth(112)
  row.xpText = UI.Text(row, 11, C.faint)
  row.xpText:SetPoint("LEFT", row.xp, "RIGHT", 8, 0)

  row.specIcon = row:CreateTexture(nil, "ARTWORK")
  row.specIcon:SetSize(18, 18)
  if row.CreateMaskTexture then
    local mask = row:CreateMaskTexture()
    mask:SetTexture(UI.Media("circle"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(row.specIcon)
    row.specIcon:AddMaskTexture(mask)
  end
  row.specName = UI.Text(row, 13, C.text)
  row.specName:SetPoint("LEFT", row.specIcon, "RIGHT", 7, 0)
  row.specPts = UI.Text(row, 11, C.faint)

  row.profs = {}
  for i = 1, 3 do
    local icon = UI.ItemIcon(row, 24)
    row.profs[i] = icon
  end

  row.status = UI.Text(row, 12, C.good)
  row.status:SetPoint("TOPRIGHT", row, "TOPRIGHT", -16, -14)
  row.status:SetJustifyH("RIGHT")
  row.deaths = UI.Text(row, 11, C.faint)
  row.deaths:SetPoint("TOPRIGHT", row, "TOPRIGHT", -16, -35)
  row.skull = UI.Glyph(row, "skull", 11, C.faint)
  row.skull:SetPoint("RIGHT", row.deaths, "LEFT", -4, 0)

  UI.Tip(row, function(tt, self) View.MemberTooltip(tt, self.m) end, "ANCHOR_CURSOR")
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" then View:ContextMenu(self.m) end
  end)
  return row
end

local function updateRow(row, item)
  local m, online = item.m, item.online
  row.m = m
  local w = row:GetWidth()
  local r, g, b = U.ClassColor(m.class)
  row.avatar:SetMember(m, online)
  row.name:SetText(U.Short(m.name))
  row.name:SetTextColor(r, g, b, online and 1 or 0.6)
  row.name:SetWidth(math.min(row.name:GetStringWidth() + 2, w * COLS.level - 130))

  if m.name == ns.me then
    row.tag:Set(L["toi"], C.accent)
    row.tag:Show()
  elseif m.dead and online then
    row.tag:Set(L["fantôme"], C.bad)
    row.tag:Show()
  else
    row.tag:Hide()
  end
  row.nick:ClearAllPoints()
  row.nick:SetPoint("LEFT", row.tag:IsShown() and row.tag or row.name, "RIGHT", 8, 0)
  row.nick:SetText(m.nick or "")

  local zone = m.zone or L["Zone inconnue"]
  if m.sub then zone = zone .. " · " .. m.sub end
  row.zone:SetText(zone)
  row.zone:SetWidth(w * COLS.level - 90)
  UI.SetTextColor(row.zone, online and C.muted or C.faint)

  -- niveau et barre d'XP
  local lx = math.floor(w * COLS.level)
  row.level:ClearAllPoints()
  row.level:SetPoint("TOPLEFT", row, "TOPLEFT", lx, -11)
  row.xp:ClearAllPoints()
  row.xp:SetPoint("TOPLEFT", row, "TOPLEFT", lx, -40)
  local level = m.level or 0
  if level >= ns.MAX_LEVEL then
    row.level:Set(tostring(level), C.gold, "crown")
    row.xp:SetColor(C.gold)
    row.xp:SetValue(1)
    row.xpText:SetText(L["max"])
  else
    row.level:Set(string.format(L["niv. %d"], level), { r, g, b, 1 })
    row.xp:SetColor({ r, g, b, 0.9 })
    row.xp:SetValue(m.xp or 0, true)
    row.xpText:SetText(U.Percent(m.xp or 0))
  end

  -- spécialisation
  local sx = math.floor(w * COLS.spec)
  local specName, specIcon, points = ns.Profile.SpecSummary(m.spec)
  row.specIcon:ClearAllPoints()
  row.specIcon:SetPoint("TOPLEFT", row, "TOPLEFT", sx, -12)
  row.specPts:ClearAllPoints()
  row.specPts:SetPoint("TOPLEFT", row, "TOPLEFT", sx, -38)
  if specName then
    row.specIcon:SetTexture(specIcon or U.QUESTION)
    row.specIcon:Show()
    row.specName:SetText(specName)
    row.specName:SetWidth(w * (COLS.profs - COLS.spec) - 36)
    local dual = m.spec.g and m.spec.g > 1 and string.format(L["  ·  spé %d"], m.spec.a or 1) or ""
    row.specPts:SetText(points .. dual)
  else
    row.specIcon:Hide()
    row.specName:SetText("")
    row.specPts:SetText(level < 10 and L["pas encore de talents"] or "—")
  end
  if not specName then
    row.specPts:ClearAllPoints()
    row.specPts:SetPoint("LEFT", row, "TOPLEFT", sx, -30)
  end

  -- métiers principaux
  local px = math.floor(w * COLS.profs)
  local shown = 0
  for _, p in ipairs(type(m.profs) == "table" and m.profs or {}) do
    if not U.PROF_SECONDARY[p.n] and shown < 3 then
      shown = shown + 1
      local icon = row.profs[shown]
      icon:SetItem(U.ProfIcon(p.n), nil, not online)
      icon:ClearAllPoints()
      icon:SetPoint("LEFT", row, "TOPLEFT", px + (shown - 1) * 29, -30)
      icon:Show()
    end
  end
  for i = shown + 1, 3 do row.profs[i]:Hide() end

  -- statut
  if online then
    row.status:SetText(m.dead and L["Fantôme"] or (m.instance and L["En donjon"] or L["En ligne"]))
    UI.SetTextColor(row.status, m.dead and C.bad or C.good)
  else
    row.status:SetText(U.Ago(m.seen))
    UI.SetTextColor(row.status, C.faint)
  end
  row.deaths:SetText(tostring(m.deaths or 0))
  row:SetAlpha(online and 1 or 0.78)
end

-- ------------------------------------------------------------------ menu contextuel
function View:ContextMenu(m)
  if not m then return end
  local short = U.Short(m.name)
  local items = {}
  if m.name ~= ns.me then
    items[#items + 1] = { label = L["Chuchoter"], glyph = "chat", onClick = function()
      U.OpenChat("/w " .. m.name .. " ")
    end }
    items[#items + 1] = { label = L["Inviter dans le groupe"], glyph = "plus", onClick = function()
      local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
      if invite then pcall(invite, m.name) end
    end }
    items[#items + 1] = "-"
    items[#items + 1] = { label = L["Retirer de la liste"], glyph = "trash", color = C.bad, onClick = function()
      UI.Confirm(string.format(L["Retirer %s de la bande ?\nSes données locales seront effacées (il réapparaîtra s'il se reconnecte avec le même code)."], short), function()
        ns.Store:Remove(m.name)
      end, L["Retirer"])
    end }
  else
    items[#items + 1] = { label = L["Voir ma soirée"], glyph = "moon", onClick = function() ns.Window:Select("session") end }
  end
  UI.Menu(nil, items, { cursor = true })
end

-- ------------------------------------------------------------------ accueil (aucune bande)
function View:BuildWelcome(frame)
  local w = UI.Card(frame, { radius = 14, fill = C.card })
  w:SetSize(460, 300)
  w:SetPoint("CENTER", frame, "CENTER", 0, 10)
  local glow = w:CreateTexture(nil, "BORDER")
  glow:SetTexture(UI.Media("glow"))
  glow:SetSize(220, 220)
  glow:SetPoint("CENTER", w, "TOP", 0, -62)
  glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
  local logo = w:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(UI.Media("logo"))
  logo:SetSize(64, 64)
  logo:SetPoint("TOP", 0, -28)
  local title = UI.Title(w, 20)
  title:SetPoint("TOP", logo, "BOTTOM", 0, -12)
  title:SetText(L["Bienvenue dans KEK"])
  local text = UI.Text(w, 13, C.muted)
  text:SetPoint("TOP", title, "BOTTOM", 0, -10)
  text:SetWidth(380)
  text:SetWordWrap(true)
  text:SetJustifyH("CENTER")
  text:SetText(L["Choisis un code secret avec tes amis : tous ceux qui l'entrent forment la même bande. KEK les retrouve via ta guilde, ton groupe et ta liste d'amis."])

  local input = UI.Input(w, { placeholder = L["Code de la bande (ex. loutres)"], max = 24, noClear = true })
  input:SetSize(240, 34)
  input:SetPoint("TOPLEFT", w, "TOPLEFT", 40, -212)
  local join = function()
    local code = input:GetText():lower():gsub("[^%w]", "")
    if code == "" then
      UI.FadeColor(input.edge, C.bad, 0.1)
      local x0 = 40
      UI.Tween(input, "shake", 0.4, function(p)
        input:SetPoint("TOPLEFT", w, "TOPLEFT", x0 + math.sin(p * math.pi * 6) * 6 * (1 - p), -212)
      end)
      return
    end
    ns.Comm:SetCode(code)
    ns.db.ui.onboarded = true
    ns.Window:Refresh()
  end
  input.eb:SetScript("OnEnterPressed", function(eb) eb:ClearFocus(); join() end)
  local btn = UI.Button(w, { text = L["Rejoindre"], style = "primary", h = 34, w = 130, onClick = join })
  btn:SetPoint("LEFT", input, "RIGHT", 10, 0)

  local guild = UI.Button(w, { text = L["Utiliser ma guilde à la place"], style = "ghost", h = 26, icon = "users", onClick = function()
    ns.Comm:SetCode("")
    ns.db.ui.onboarded = true
    ns.Window:Refresh()
  end })
  guild:SetPoint("TOP", w, "TOP", 0, -258)
  w.guild = guild
  return w
end

-- ------------------------------------------------------------------ construction
function View:Build(frame, actions)
  self.headerRow = CreateFrame("Frame", nil, frame)
  self.headerRow:SetPoint("TOPLEFT", 0, 0)
  self.headerRow:SetPoint("TOPRIGHT", 0, 0)
  self.headerRow:SetHeight(18)
  local h = self.headerRow
  h.member = UI.Caps(h, L["MEMBRE"])
  h.member:SetPoint("LEFT", 66, 0)
  h.level = UI.Caps(h, L["NIVEAU"])
  h.spec = UI.Caps(h, L["SPÉCIALISATION"])
  h.profs = UI.Caps(h, L["MÉTIERS"])
  h.status = UI.Caps(h, L["STATUT"])
  h.status:SetPoint("RIGHT", -16, 0)
  h:SetScript("OnSizeChanged", function() self:LayoutHeader() end)

  self.list = UI.List(frame, {
    rowHeight = 62, gap = 4,
    create = createRow, update = updateRow,
    empty = { glyph = "users", title = L["Personne en vue"], text = L["KEK cherche tes amis dans ta guilde, ton groupe et ta liste d'amis. Un ami manque ? Ajoute un de ses persos avec le bouton +."] },
  })
  self.list:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -24)
  self.list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  self.welcome = self:BuildWelcome(frame)

  -- actions : tri + hors ligne
  local offline = UI.Toggle(actions, ns.db.ui.showOffline, function(v)
    ns.db.ui.showOffline = v
    self:Refresh()
  end)
  offline:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
  local offLabel = UI.Text(actions, 12, C.muted)
  offLabel:SetPoint("RIGHT", offline, "LEFT", -8, 0)
  offLabel:SetText(L["Hors ligne"])
  local sort = UI.Segmented(actions, {
    { value = "level", label = L["Niveau"] },
    { value = "name", label = L["Nom"] },
    { value = "recent", label = L["Activité"] },
  }, ns.db.ui.rosterSort, function(v)
    ns.db.ui.rosterSort = v
    self:Refresh()
  end)
  sort:SetPoint("RIGHT", offLabel, "LEFT", -18, 0)
  self.addButton = UI.IconButton(actions, "plus", { size = 28, iconSize = 13, tooltip = L["Ajouter un ami par son nom"],
    onClick = function(b) self:ShowAddPopover(b) end })
  self.addButton:SetPoint("RIGHT", sort, "LEFT", -10, 0)
  self.frame = frame
end

-- ------------------------------------------------------------------ ajout d'un ami par son nom
function View:BuildAddPopover()
  local p = UI.Card(self.frame, { radius = 12, fill = C.cardHi })
  p:SetSize(310, 134)
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:SetFrameLevel(50)
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  p:Hide()
  UI.Shadow(p, 18, 0.55)
  local title = UI.Title(p, 15)
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText(L["Ajouter un ami"])
  local text = UI.Text(p, 11, C.muted)
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  text:SetWidth(278)
  text:SetWordWrap(true)
  text:SetJustifyH("LEFT")
  text:SetText(L["Le nom d'un de ses persos. Il doit avoir KEK et le même code ; ensuite, toute sa bande te trouve aussi."])
  local input = UI.Input(p, { placeholder = U.SURNAMES and L["ex. Philipon Dugard"] or L["ex. Gromgar"], max = 48, noClear = true })
  input:SetSize(186, 32)
  input:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 16)
  local submit = function()
    if ns.Comm:AddPeer(input:GetText()) then
      input:SetText("")
      self:HideAddPopover()
    end
  end
  input.eb:SetScript("OnEnterPressed", function(eb) eb:ClearFocus(); submit() end)
  input.eb:SetScript("OnEscapePressed", function() self:HideAddPopover() end)
  local btn = UI.Button(p, { text = L["Ajouter"], style = "primary", h = 32, onClick = submit })
  btn:SetPoint("LEFT", input, "RIGHT", 8, 0)
  -- un clic à côté referme la fenêtre
  local catcher = CreateFrame("Button", nil, self.frame)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetFrameLevel(40)
  catcher:SetAllPoints(UIParent)
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", function() self:HideAddPopover() end)
  catcher:Hide()
  p.catcher, p.input = catcher, input
  self.frame:HookScript("OnHide", function() self:HideAddPopover() end)
  return p
end

function View:ShowAddPopover(anchor)
  if ns.Comm:Code() == "" then
    ns.Window:Select("settings")
    return
  end
  self.addPopover = self.addPopover or self:BuildAddPopover()
  local p = self.addPopover
  p:ClearAllPoints()
  p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
  p.input:SetText("")
  p.catcher:Show()
  p:SetAlpha(0)
  p:Show()
  UI.Tween(p, "fade", 0.12, function(t) p:SetAlpha(t) end)
  p.input.eb:SetFocus()
end

function View:HideAddPopover()
  local p = self.addPopover
  if not p then return end
  p.input.eb:ClearFocus()
  p:Hide()
  p.catcher:Hide()
end

function View:LayoutHeader()
  local h = self.headerRow
  local w = h:GetWidth() or 0
  if w <= 0 then return end
  h.level:ClearAllPoints()
  h.level:SetPoint("LEFT", h, "LEFT", math.floor(w * COLS.level), 0)
  h.spec:ClearAllPoints()
  h.spec:SetPoint("LEFT", h, "LEFT", math.floor(w * COLS.spec), 0)
  h.profs:ClearAllPoints()
  h.profs:SetPoint("LEFT", h, "LEFT", math.floor(w * COLS.profs), 0)
end

function View:Refresh()
  self:LayoutHeader()
  local needsBand = ns.Comm.mode == "none" and (ns.db.band.code or "") == ""
  self.welcome:SetShown(needsBand)
  self.welcome.guild:SetShown(IsInGuild() and true or false)
  self.addButton:SetShown(ns.Comm:Code() ~= "")
  self.list:SetShown(not needsBand)
  self.headerRow:SetShown(not needsBand)
  if not needsBand then self.list:SetData(memberList(), true) end
end

ns.Window:Register(View)
ns.RosterView = View
