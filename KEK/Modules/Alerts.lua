-- KEK — événements partagés (niveau, butin, mort, boss, métier, connexion), fil d'actualité et notifications.
local _, ns = ...
local L, U = ns.L, ns.U

local Alerts = ns:NewModule("Alerts", 40)

local FEED_MAX = 400
local SKILL_STEPS = { [75] = L["Apprenti"], [150] = L["Compagnon"], [225] = L["Expert"], [300] = L["Artisan"] }

Alerts.KINDS = {
  level = { label = L["NIVEAU"], glyph = "arrowup", color = { 1.00, 0.80, 0.35 } },
  loot = { label = L["BUTIN"], glyph = "star", color = { 0.64, 0.21, 0.93 } },
  death = { label = L["MORT"], glyph = "skull", color = { 0.96, 0.38, 0.38 } },
  boss = { label = L["BOSS"], glyph = "crown", color = { 1.00, 0.55, 0.24 } },
  skill = { label = L["MÉTIER"], glyph = "hammer", color = { 0.40, 0.68, 1.00 } },
  presence = { label = L["CONNEXION"], glyph = "users", color = { 0.38, 0.86, 0.56 } },
  need = { label = L["BESOIN"], glyph = "bag", color = { 0.98, 0.76, 0.33 } },
  boe = { label = L["LQE"], glyph = "star", color = { 0.12, 1.00, 0.00 } },
  got = { label = L["TROUVÉ"], glyph = "bag", color = { 0.98, 0.76, 0.33 } },
}

-- Événements personnels : notification seulement, pas de ligne dans le fil.
local NO_FEED = { presence = true, got = true }

Alerts.seen = {}
Alerts.pendingOffline = {}

-- ------------------------------------------------------------------ motifs du chat (localisés)
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("%%%d%$", "%%")                       -- %1$s -> %s
  p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")         -- échappe les caractères magiques
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end

function Alerts:BuildPatterns()
  self.skillPattern = toPattern(SKILL_RANK_UP or "Your skill in %s has increased to %d.")
end

-- ------------------------------------------------------------------ butin (par les sacs)
-- En donjon, le jeu cache les messages du chat aux addons : on compare plutôt le contenu des sacs
-- et de l'équipement. Les échanges (banque, courrier, marchand, hôtel des ventes) sont ignorés.
local BUSY_EVENTS = {
  BANKFRAME_OPENED = "BANKFRAME_CLOSED", MAIL_SHOW = "MAIL_CLOSED", MERCHANT_SHOW = "MERCHANT_CLOSED",
  TRADE_SHOW = "TRADE_CLOSED", AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED", GUILDBANKFRAME_OPENED = "GUILDBANKFRAME_CLOSED",
}

function Alerts:Holdings()
  local t = {}
  local function add(id, count, link, q)
    if not id then return end
    local e = t[id]
    if not e then e = { n = 0 }; t[id] = e end
    e.n = e.n + (count or 1)
    e.link = e.link or link
    e.q = e.q or q
  end
  local CC = C_Container
  local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (numSlots and numSlots(bag)) or 0 do
      if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if info then add(info.itemID, info.stackCount, info.hyperlink, info.quality) end
      elseif GetContainerItemInfo then
        local _, count, _, q, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
        add(id, count, link, q)
      end
    end
  end
  if GetInventoryItemID then
    for slot = 0, 23 do
      local id = GetInventoryItemID("player", slot)
      if id then add(id, 1, GetInventoryItemLink and GetInventoryItemLink("player", slot)) end
    end
  end
  return t
end

function Alerts:IsBusy()
  for _ in pairs(self.busy) do return true end
  return false
end

function Alerts:ScanLoot()
  local now = self:Holdings()
  local before = self.holdings
  self.holdings = now
  if not before or self:IsBusy() or GetTime() < (self.quietUntil or 0) then return end
  for id, e in pairs(now) do
    local gained = e.n - (before[id] and before[id].n or 0)
    if gained > 0 then
      local link = e.link or select(2, U.GetItemInfo(id))
      if link and not U.Secret(link) then
        ns:Fire("LOOT_SELF", link, gained)
        -- objet LQE ou sac : annoncé à part (la bande juge s'il l'intéresse) ; sinon butin rare et +
        local announced = ns.Boe and ns.Boe:OnLoot(link, gained)
        local q = e.q or U.ItemQuality(link)
        if not announced and q and not U.Secret(q) and q >= 3 then
          self:Emit("loot", { i = link, q = q, c = gained > 1 and gained or nil, z = GetRealZoneText() })
        end
      end
    end
  end
end

function Alerts:WatchLoot()
  self.busy = {}
  for open, close in pairs(BUSY_EVENTS) do
    ns:RegisterEvent(open, function() self.busy[open] = true end)
    ns:RegisterEvent(close, function()
      self.busy[open] = nil
      self.quietUntil = GetTime() + 1.5
    end)
  end
  -- interface récente : toutes ces fenêtres passent par un seul couple d'événements
  ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) self.busy["pim" .. tostring(kind)] = true end)
  ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
    self.busy["pim" .. tostring(kind)] = nil
    self.quietUntil = GetTime() + 1.5
  end)
  ns:RegisterEvent("BAG_UPDATE_DELAYED", function() self:ScanLoot() end)
  ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() ns:Debounce("loot-equip", 0.5, function() self:ScanLoot() end) end)
  C_Timer.After(2, function() self.holdings = self:Holdings() end)
end

-- ------------------------------------------------------------------ émission
function Alerts:Emit(kind, data)
  data = data or {}
  data.k = kind
  data.t = ns.Now()
  self:Receive(ns.me, data, true)
  ns.Comm:Send("E", data, 1)
end

function Alerts:OnLogin()
  self:BuildPatterns()

  ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
    self:Emit("level", { l = tonumber(level) or UnitLevel("player") + 1, z = GetRealZoneText() })
  end)

  self:WatchLoot()

  ns:RegisterEvent("ENCOUNTER_END", function(_, _, name, _, _, success)
    if U.Secret(success) or success ~= 1 then return end
    if U.Secret(name) or type(name) ~= "string" or name == "" then
      name = GetInstanceInfo and GetInstanceInfo() or nil      -- nom du boss caché : celui du donjon
      if U.Secret(name) then name = nil end
    end
    self:Emit("boss", { b = name or L["un boss"], z = GetRealZoneText() })
  end)

  ns:RegisterEvent("CHAT_MSG_SKILL", function(_, msg)
    if not self.skillPattern or type(msg) ~= "string" or U.Secret(msg) then return end
    local skill, rank = msg:match(self.skillPattern)
    rank = tonumber(rank)
    if skill and rank and SKILL_STEPS[rank] then
      self:Emit("skill", { s = skill, r = rank })
    end
  end)

  ns:On("MSG_E", function(sender, data) self:Receive(sender, data, false) end)

  -- connexions : « H » = arrivée, « B » = départ. Un /reload envoie B puis H : on l'ignore.
  ns:On("MSG_H", function(sender, data, msg)
    if self.pendingOffline[sender] then
      self.pendingOffline[sender] = nil
      return
    end
    if not self.warm then return end
    if type(data) == "table" and data.r then return end   -- retour de donjon, pas une connexion
    if msg and msg.fresh == false then return end   -- simple sondage d'un membre déjà là
    self:Receive(sender, { k = "presence", on = true, t = ns.Now() }, false)
  end)
  ns:On("MSG_B", function(sender)
    local token = {}
    self.pendingOffline[sender] = token
    C_Timer.After(25, function()
      if self.pendingOffline[sender] ~= token then return end
      self.pendingOffline[sender] = nil
      self:Receive(sender, { k = "presence", on = false, t = ns.Now() }, false)
    end)
  end)
  ns:On("COMM_READY", function()
    C_Timer.After(20, function() self.warm = true end)
  end)
end

-- ------------------------------------------------------------------ réception
function Alerts:Receive(who, data, isSelf)
  if type(data) ~= "table" or not self.KINDS[data.k] then return end
  local key = who .. ":" .. data.k .. ":" .. tostring(data.t or 0) .. ":" .. tostring(U.ItemID(data.i) or "")
  if self.seen[key] then return end
  self.seen[key] = true

  local entry = U.Copy(data)
  entry.w = who
  entry.t = entry.t or ns.Now()
  if not NO_FEED[data.k] then
    local feed = ns.db.feed
    table.insert(feed, 1, entry)
    for i = #feed, FEED_MAX + 1, -1 do feed[i] = nil end
  end
  ns:Fire("EVENT", who, entry)
  ns:Fire("DATA", "feed")

  if not ns.Toasts then return end
  if entry.k == "boe" and not isSelf and ns.Boe and not ns.Boe:Info(entry.i) then
    -- objet pas encore connu de ton jeu : on attend ses caractéristiques avant de juger s'il t'intéresse
    U.WithItemLink(U.ItemID(entry.i), function()
      if self:ShouldToast(entry, isSelf) then ns.Toasts:Show(self:ToastSpec(who, entry)) end
    end)
    return
  end
  if self:ShouldToast(entry, isSelf) then
    ns.Toasts:Show(self:ToastSpec(who, entry))
  end
end

-- L'objet LQE intéresse-t-il ton personnage ? (texte de la raison, ou nil)
function Alerts:BoeReason(who, e)
  if who == ns.me or not ns.Boe then return nil end
  return ns.Boe:Interest(e.i)
end

function Alerts:ShouldToast(e, isSelf)
  local a = ns.db.alerts
  if not a[e.k] and e.k ~= "boe" and e.k ~= "got" then return false end
  if e.k == "loot" and (e.q or 0) < (a.lootQuality or 4) then return false end
  if e.k == "got" then
    if isSelf or not a.need or type(e.o) ~= "table" then return false end
    for _, o in ipairs(e.o) do if o == ns.me then return true end end
    return false
  end
  if e.k == "boe" then
    local rare = a.loot and (e.q or 0) >= (a.lootQuality or 4)
    if isSelf then return a.self and rare end
    return (a.boe and self:BoeReason(who, e) ~= nil) or rare
  end
  if isSelf then
    if e.k == "level" and e.l == ns.MAX_LEVEL then return true end
    return a.self
  end
  return true
end

-- Texte d'un événement, partagé par les notifications et le fil.
function Alerts:Describe(who, e)
  local name = U.MemberName(who)
  local kind = self.KINDS[e.k]
  if e.k == "level" then
    if e.l == ns.MAX_LEVEL then
      return string.format(L["%s atteint le niveau %d !"], name, e.l), L["La course est terminée pour ce personnage."]
    end
    return string.format(L["%s passe niveau %d"], name, e.l or 0), e.z
  elseif e.k == "loot" then
    local item = U.ItemText(e.i, U.ItemID(e.i))
    if e.c and e.c > 1 then item = item .. " ×" .. e.c end
    return string.format(L["%s a obtenu"], name), item
  elseif e.k == "boe" then
    local item = U.ItemText(e.i, U.ItemID(e.i))
    local reason = self:BoeReason(who, e)
    if reason then return string.format(L["%s a ramassé %s"], name, item), string.format(L["Pour toi : %s"], reason) end
    return string.format(L["%s a ramassé %s"], name, item), L["Lié quand équipé : on peut se l'échanger"]
  elseif e.k == "got" then
    local item = U.ItemText(e.i, U.ItemID(e.i))
    if (e.c or 1) > 1 then item = item .. " ×" .. e.c end
    local left = ns.Boe and ns.Boe:StillNeeded(e.i)
    local body = left and left > 0 and string.format(L["tu en cherches encore %d"], left) or L["c'est sur ta liste de besoins"]
    return string.format(L["%s vient de ramasser %s"], name, item), body
  elseif e.k == "need" and type(e.m) == "table" then
    -- liste de composants pour une recette
    local what = e.r and (e.r .. ((e.c or 1) > 1 and (" ×" .. e.c) or "")) or nil
    local title = what and string.format(L["%s a besoin des composants de %s"], name, what)
      or string.format(L["%s a besoin de %d objets"], name, #e.m)
    local parts = {}
    for i, it in ipairs(e.m) do
      if i <= 4 then parts[#parts + 1] = string.format("%s ×%d", tostring(it.s or "?"), it.q or 1) end
    end
    if #e.m > 4 then parts[#parts + 1] = string.format(L["et %d autre(s)"], #e.m - 4) end
    local body = table.concat(parts, ", ")
    if who ~= ns.me and ns.Craft then
      local have = {}
      for _, it in ipairs(e.m) do
        local n = ns.Craft:OwnedFor({ i = it.i, s = it.s })
        if n > 0 then have[#have + 1] = string.format("%s (%d)", tostring(it.s or "?"), n) end
      end
      if #have > 0 then body = body .. " · " .. string.format(L["tu as : %s"], table.concat(have, ", ")) end
    end
    return title, body
  elseif e.k == "need" then
    local item = (type(e.lk) == "string" and e.lk:find("|H", 1, true) and e.lk) or e.s or "?"
    if (e.q or 1) > 1 then item = item .. " ×" .. e.q end
    local parts = {}
    if e.n then parts[#parts + 1] = "« " .. e.n .. " »" end
    if who ~= ns.me and ns.Craft then
      local have = ns.Craft:OwnedFor({ i = e.i, s = e.s })
      if have > 0 then parts[#parts + 1] = string.format(L["tu en as %d"], have) end
    end
    return string.format(L["%s a besoin de %s"], name, item), #parts > 0 and table.concat(parts, " · ") or nil
  elseif e.k == "death" then
    local title = string.format(L["%s est mort"], name)
    return title, ns.Deaths and ns.Deaths:Cause(e) or ""
  elseif e.k == "boss" then
    return string.format(L["%s a vaincu %s"], name, e.b or "?"), e.z
  elseif e.k == "skill" then
    return string.format(L["%s : %s %d"], name, e.s or "?", e.r or 0), SKILL_STEPS[e.r] and string.format(L["Rang %s atteint"], SKILL_STEPS[e.r]) or nil
  elseif e.k == "presence" then
    return string.format(e.on and L["%s vient de se connecter"] or L["%s s'est déconnecté"], name), nil
  end
  return name, kind and kind.label
end

function Alerts:Icon(e)
  if e.k == "loot" or e.k == "boe" then return U.ItemIcon(e.i), "item", e.q end
  if e.k == "got" then return U.ItemIcon(e.i), "item", U.ItemQuality(e.i) end
  if e.k == "need" and e.i then return U.ItemIcon(e.i), "item", U.ItemQuality(e.lk or e.i) end
  if e.k == "skill" then return U.ProfIcon(e.s), "item" end
  return nil
end

function Alerts:ToastSpec(who, e)
  local kind = self.KINDS[e.k]
  local title, body = self:Describe(who, e)
  local spec = {
    kind = e.k, who = who, title = title, body = body, label = kind.label, color = kind.color,
    glyph = kind.glyph, sound = e.k, duration = 7,
  }
  local icon, iconKind, quality = self:Icon(e)
  if icon then
    spec.icon, spec.quality = icon, quality
    if e.k == "loot" then
      spec.link = e.i
      local r, g, b = U.QualityColor(e.q or 4)
      spec.color = { r, g, b }
      spec.label = (e.q or 0) >= 5 and L["BUTIN LÉGENDAIRE"] or (e.q == 4 and L["BUTIN ÉPIQUE"]) or L["BUTIN RARE"]
    end
  else
    spec.member = who
  end
  if e.k == "level" and e.l == ns.MAX_LEVEL then
    spec.big, spec.duration, spec.sound = true, 12, "max"
    spec.label = L["NIVEAU MAXIMUM"]
  elseif e.k == "death" then
    spec.duration = 9
    spec.view = "deaths"
  elseif e.k == "presence" then
    spec.compact, spec.duration = true, 4
    if not e.on then spec.color = { 0.55, 0.57, 0.63 } end
  elseif e.k == "boe" then
    spec.link = e.i
    if self:BoeReason(who, e) then
      spec.label, spec.color, spec.duration, spec.sound = L["LQE POUR TOI"], { 0.12, 1.00, 0.00 }, 10, "boe"
    else
      local r, g, b = U.QualityColor(e.q or 2)
      spec.color, spec.sound = { r, g, b }, "loot"
      spec.label = (e.q or 0) >= 5 and L["BUTIN LÉGENDAIRE"] or (e.q == 4 and L["BUTIN ÉPIQUE"]) or L["BUTIN RARE"]
    end
    spec.view = "chest"
  elseif e.k == "got" then
    spec.link, spec.duration, spec.sound = e.i, 9, "need"
    spec.onClick = function()
      ns.db.ui.craftTab = "needs"
      ns.Window:Open("craft")
    end
  elseif e.k == "need" then
    spec.duration = 9
    spec.onClick = function()
      ns.db.ui.craftTab = "needs"
      ns.Window:Open("craft")
    end
  elseif e.k == "boss" then
    -- plusieurs membres du groupe tuent le même boss : une seule notification qui liste tout le monde
    spec.key = "boss:" .. (e.b or "")
    spec.names = { who }
    spec.merge = function(old, new)
      for _, n in ipairs(new.names) do
        local dup = false
        for _, o in ipairs(old.names) do if o == n then dup = true end end
        if not dup then old.names[#old.names + 1] = n end
      end
      local names = {}
      for i, n in ipairs(old.names) do names[i] = U.MemberName(n) end
      old.title = string.format(L["%s ont vaincu %s"], table.concat(names, ", "), e.b or "?")
      return old
    end
  end
  if e.k == "loot" or e.k == "level" or e.k == "skill" then spec.view = "feed" end
  return spec
end
