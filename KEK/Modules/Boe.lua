-- KEK — objets LQE (« Lié quand équipé ») et sacs que la bande peut s'échanger.
--   · repère ceux que tu gardes (sacs, banque, banque de guilde) et les partage avec la bande (le Coffre) ;
--   · juge, pour ton personnage, si un objet t'intéresse : classe, niveau, meilleur que ce que tu portes,
--     caractéristiques utiles, recette de ton métier que tu n'as pas, sac plus grand ;
--   · prévient la bande quand tu en ramasses un, et prévient un ami quand tu ramasses ce qu'il cherche.
local _, ns = ...
local L, U = ns.L, ns.U

local Boe = ns:NewModule("Boe", 45)

local BIND_ON_EQUIP = 2
local CLASS_CONTAINER, CLASS_WEAPON, CLASS_ARMOR, CLASS_RECIPE = 1, 2, 4, 9
local LEVEL_MARGIN = 3     -- un objet utilisable dans 3 niveaux intéresse déjà
local GOT_WINDOW = 6       -- secondes : on regroupe les objets ramassés d'affilée avant de prévenir

-- ------------------------------------------------------------------ règles de WoW Classic
-- Armures (tissu 1, cuir 2, mailles 3, plaques 4) : on ne propose que le type principal de la classe à ce
-- niveau. Un guerrier peut porter du tissu, mais ça ne l'intéresse jamais. Mailles et plaques s'apprennent au 40.
local function mainArmor(class, level)
  if class == "WARRIOR" or class == "PALADIN" then return level >= 40 and 4 or 3 end
  if class == "HUNTER" or class == "SHAMAN" then return level >= 40 and 3 or 2 end
  if class == "ROGUE" or class == "DRUID" then return 2 end
  return 1
end
-- Boucliers 6, librams 7, idoles 8, totems 9.
local ARMOR_EXTRA = {
  WARRIOR = { [6] = true }, PALADIN = { [6] = true, [7] = true }, SHAMAN = { [6] = true, [9] = true }, DRUID = { [8] = true },
}
-- Armes : haches 0/1, arcs 2, fusils 3, masses 4/5, armes d'hast 6, épées 7/8, bâtons 10, armes de pugilat 13,
-- dagues 15, armes de jet 16, arbalètes 18, baguettes 19.
local WEAPON = {
  WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
  PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
  HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
  ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
  PRIEST = { 4, 10, 15, 19 },
  SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
  MAGE = { 7, 10, 15, 19 },
  WARLOCK = { 7, 10, 15, 19 },
  DRUID = { 4, 5, 10, 13, 15 },
}
for class, list in pairs(WEAPON) do
  local set = {}
  for _, sub in ipairs(list) do set[sub] = true end
  WEAPON[class] = set
end
-- Caractéristiques principales utiles à chaque classe (l'endurance sert à tout le monde).
local USEFUL = {
  WARRIOR = { STRENGTH = true, AGILITY = true },
  PALADIN = { STRENGTH = true, INTELLECT = true, SPIRIT = true },
  HUNTER = { AGILITY = true, INTELLECT = true },
  ROGUE = { AGILITY = true, STRENGTH = true },
  PRIEST = { INTELLECT = true, SPIRIT = true },
  SHAMAN = { INTELLECT = true, STRENGTH = true, AGILITY = true, SPIRIT = true },
  MAGE = { INTELLECT = true, SPIRIT = true },
  WARLOCK = { INTELLECT = true, SPIRIT = true },
  DRUID = { INTELLECT = true, SPIRIT = true, AGILITY = true, STRENGTH = true },
}
local PRIMARY = { "STRENGTH", "AGILITY", "INTELLECT", "SPIRIT" }
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }
-- Emplacement d'équipement -> cases du personnage à comparer.
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
  INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Boe.SLOT_NAMES = {
  INVTYPE_HEAD = L["Tête"], INVTYPE_NECK = L["Cou"], INVTYPE_SHOULDER = L["Épaules"], INVTYPE_CHEST = L["Torse"],
  INVTYPE_ROBE = L["Torse"], INVTYPE_WAIST = L["Taille"], INVTYPE_LEGS = L["Jambes"], INVTYPE_FEET = L["Pieds"],
  INVTYPE_WRIST = L["Poignets"], INVTYPE_HAND = L["Mains"], INVTYPE_FINGER = L["Doigt"], INVTYPE_TRINKET = L["Bijou"],
  INVTYPE_CLOAK = L["Dos"], INVTYPE_WEAPON = L["Une main"], INVTYPE_2HWEAPON = L["Deux mains"],
  INVTYPE_WEAPONMAINHAND = L["Main droite"], INVTYPE_WEAPONOFFHAND = L["Main gauche"], INVTYPE_SHIELD = L["Bouclier"],
  INVTYPE_HOLDABLE = L["Tenu en main gauche"], INVTYPE_RANGED = L["À distance"], INVTYPE_RANGEDRIGHT = L["À distance"],
  INVTYPE_THROWN = L["Jet"], INVTYPE_RELIC = L["Relique"],
}
Boe.PLACES = { b = L["Sac"], k = L["Banque"], g = L["Banque de guilde"] }

-- ------------------------------------------------------------------ lecture des objets
-- « item:1234:…:suffixe » : assez pour retrouver l'objet exact (avec ses caractéristiques « du singe »).
function U.ItemString(link)
  if type(link) ~= "string" then return nil end
  local s = link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)$")
  return s and (s:gsub(":+$", "")) or nil
end

local function stats(link)
  local get = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not get then return nil end
  local ok, t = pcall(get, link)
  return ok and type(t) == "table" and t or nil
end

-- Lignes de l'infobulle (recettes : métier requis ; sacs : nombre de places).
local function tooltipLines(link)
  local TI = C_TooltipInfo
  if not TI or not TI.GetHyperlink then return nil end
  local ok, data = pcall(TI.GetHyperlink, link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local out = {}
  for _, line in ipairs(data.lines) do
    local text = line.leftText
    if type(text) == "string" and not U.Secret(text) then out[#out + 1] = text end
  end
  return out
end

local function patternOf(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("%%%d%$", "%%")
  p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  return (p:gsub("%%s", ".-"):gsub("%%d", "(%%d+)"))
end

-- Tout ce qu'il faut savoir d'un objet, ou nil si le jeu ne le connaît pas encore.
function Boe:Info(item)
  if not item then return nil end
  local name, link, q, ilvl, minLevel, _, subType, _, equipLoc, _, _, classID, subclassID, bindType = U.GetItemInfo(item)
  if not name then return nil end
  return {
    name = name, link = link, q = q or 1, ilvl = ilvl or 0, minLevel = minLevel or 0, subType = subType,
    equipLoc = equipLoc ~= "" and equipLoc or nil, classID = classID, subclassID = subclassID, bindType = bindType,
  }
end

-- Objet que la bande peut s'échanger : LQE, ou sac ordinaire (jamais liés tant qu'ils ne sont pas utilisés).
function Boe:Tradable(info)
  if not info then return false end
  if info.bindType == BIND_ON_EQUIP then return true end
  return info.classID == CLASS_CONTAINER and info.subclassID == 0 and (info.bindType or 0) == 0
end

-- ------------------------------------------------------------------ intérêt pour ton personnage
local function equippedLevel(slot)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  if not link then return 0, nil end
  local _, _, _, ilvl = U.GetItemInfo(link)
  return ilvl or 0, link
end

local function knownRecipe(prof, recipeName)
  local mine = ns.db.recipes[ns.me]
  local entry = mine and mine.p and mine.p[prof]
  if not entry or type(entry.l) ~= "table" then return false end
  local want = U.Fold(recipeName)
  for name in pairs(entry.l) do
    if U.Fold(name) == want then return true end
  end
  return false
end

local function myProfession(name)
  local me = ns.db.members[ns.me]
  local want = U.Fold(name or "")
  for _, p in ipairs(me and type(me.profs) == "table" and me.profs or {}) do
    if U.Fold(p.n or "") == want then return p end
  end
  return nil
end

local function smallestBag()
  local CC = C_Container
  local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  local least
  for bag = 1, (NUM_BAG_SLOTS or 4) do
    local n = numSlots and numSlots(bag) or 0
    if not least or n < least then least = n end
  end
  return least or 0
end

function Boe:EquipReason(info, class, level)
  local slots = SLOTS[info.equipLoc or ""]
  if not slots then return nil end
  local sub = info.subclassID
  if info.classID == CLASS_ARMOR and sub and sub ~= 0 and sub ~= 5 and info.equipLoc ~= "INVTYPE_CLOAK" then
    -- (les capes sont en tissu mais vont à tout le monde ; bijoux, colliers et anneaux sont « divers »)
    if sub >= 1 and sub <= 4 then
      if sub ~= mainArmor(class, math.max(level, info.minLevel)) then return nil end
    elseif not (ARMOR_EXTRA[class] or {})[sub] then
      return nil
    end
  elseif info.classID == CLASS_WEAPON then
    if not (WEAPON[class] or {})[sub] then return nil end
  elseif info.classID ~= CLASS_ARMOR then
    return nil
  end
  if info.minLevel > level + LEVEL_MARGIN then return nil end
  local st = stats(info.link)
  if st then
    local primary, useful = false, false
    for _, key in ipairs(PRIMARY) do
      if (st["ITEM_MOD_" .. key .. "_SHORT"] or 0) > 0 then
        primary = true
        if (USEFUL[class] or {})[key] then useful = true end
      end
    end
    if primary and not useful then return nil end
  end
  -- compare avec la pièce la plus faible parmi les cases possibles
  local list = slots
  if info.equipLoc == "INVTYPE_WEAPON" and not DUAL_WIELD[class] then list = { 16 } end
  local worst, worstLink
  for _, slot in ipairs(list) do
    local ilvl, link = equippedLevel(slot)
    if not worst or ilvl < worst then worst, worstLink = ilvl, link end
  end
  worst = worst or 0
  if worstLink and info.ilvl <= worst then return nil end
  local parts = {}
  if not worstLink then
    parts[1] = string.format(L["%s : emplacement vide"], self.SLOT_NAMES[info.equipLoc] or "?")
  else
    parts[1] = string.format(L["meilleur que ton objet actuel (niveau %d contre %d)"], info.ilvl, worst)
  end
  if info.minLevel > level then
    local n = info.minLevel - level
    parts[#parts + 1] = string.format(n == 1 and L["utilisable dans %d niveau"] or L["utilisable dans %d niveaux"], n)
  end
  return table.concat(parts, " · ")
end

function Boe:RecipeReason(info)
  local prof = myProfession(info.subType)
  if not prof then return nil end
  local recipe = info.name:match("^[^:]+:%s*(.+)$") or info.name
  if knownRecipe(prof.n, recipe) then return nil end
  local need
  local pattern = patternOf(ITEM_MIN_SKILL or "Requires %s (%d)")
  for _, line in ipairs(tooltipLines(info.link) or {}) do
    need = need or tonumber(line:match(pattern or "%((%d+)%)"))
  end
  if need and need > (prof.r or 0) then
    return string.format(L["recette de %s que tu n'as pas (requiert %d, tu es à %d)"], prof.n, need, prof.r or 0)
  end
  return string.format(L["recette de %s que tu n'as pas"], prof.n)
end

function Boe:BagReason(info)
  local pattern = patternOf(CONTAINER_SLOTS or "%d Slot %s")
  local slots
  for _, line in ipairs(tooltipLines(info.link) or {}) do
    slots = slots or tonumber(line:match(pattern or "(%d+)"))
  end
  if not slots then return nil end
  local least = smallestBag()
  if slots <= least then return nil end
  if least == 0 then return string.format(L["sac de %d places, et tu as un emplacement de sac libre"], slots) end
  return string.format(L["sac de %d places (ton plus petit : %d)"], slots, least)
end

-- Pourquoi cet objet intéresse ton personnage actuel (texte), ou nil. Résultat gardé en cache jusqu'au
-- prochain changement de ton équipement, de ton niveau ou de tes recettes.
Boe.cache, Boe.version = {}, 0

function Boe:Invalidate()
  self.version = self.version + 1
  ns:Fire("DATA", "boe")
end

function Boe:Interest(item)
  local key = U.ItemString(item) or tostring(item)
  local hit = self.cache[key]
  if hit and hit.v == self.version then return hit.r or nil end
  local info = self:Info(item)
  if not info then return nil end                 -- pas encore en cache : on réessaiera
  local _, class = UnitClass("player")
  local level = UnitLevel("player") or 1
  local ok, reason = pcall(function()
    if info.classID == CLASS_RECIPE then return self:RecipeReason(info) end
    if info.classID == CLASS_CONTAINER then return self:BagReason(info) end
    return self:EquipReason(info, class, level)
  end)
  if not ok then ns.Report(reason); reason = nil end
  self.cache[key] = { v = self.version, r = reason or false }
  return reason
end

-- ------------------------------------------------------------------ tes objets (sacs, banque, banque de guilde)
local function slotsOf(bag)
  local CC = C_Container
  local fn = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  return fn and fn(bag) or 0
end

local function readBags(bags)
  local out, index = {}, {}
  for _, bag in ipairs(bags) do
    for slot = 1, slotsOf(bag) do
      local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink and not info.isBound and not U.Secret(info.hyperlink) then
        local it = Boe:Info(info.hyperlink)
        if Boe:Tradable(it) then
          local s = U.ItemString(info.hyperlink)
          if s then
            local e = index[s]
            if e then e.n = e.n + (info.stackCount or 1) else
              e = { s = s, n = info.stackCount or 1 }
              index[s] = e
              out[#out + 1] = e
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.s < b.s end)
  return out
end

local function own()
  ns.db.boe = ns.db.boe or {}
  local e = ns.db.boe[ns.me]
  if not e then e = {}; ns.db.boe[ns.me] = e end
  e.own = true
  return e
end

local function sameList(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
  for i = 1, #a do
    if a[i].s ~= b[i].s or a[i].n ~= b[i].n then return false end
  end
  return true
end

function Boe:Changed()
  self.hash = nil
  ns:Fire("DATA", "boe")
  ns:Debounce("boe-push", 10, function() ns.Sync:Push("o") end)
end

function Boe:ScanBags()
  local list = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
  local e, items = own(), readBags(list)
  if sameList(e.b, items) then return end
  e.b, e.bt = items, ns.Now()
  self:Changed()
end

function Boe:ScanBank()
  if not self.bankOpen then return end
  local list = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do list[#list + 1] = bag end
  local e, items = own(), readBags(list)
  e.kt = ns.Now()
  if sameList(e.k, items) then return end
  e.k = items
  self:Changed()
end

-- Banque de guilde (si WoW Forever en a une) : lue quand tu l'ouvres, onglet par onglet.
function Boe:HasGuildBank()
  return GetNumGuildBankTabs ~= nil and GetGuildBankItemLink ~= nil
end

function Boe:GuildName()
  local name = GetGuildInfo and GetGuildInfo("player")
  if U.Secret(name) or type(name) ~= "string" or name == "" then return L["ta guilde"] end
  return name
end

function Boe:ScanGuildBank()
  if not self.guildBankOpen or not self:HasGuildBank() then return end
  ns.db.gbank = ns.db.gbank or {}
  local guild = self:GuildName()
  local g = ns.db.gbank[guild] or { tabs = {} }
  ns.db.gbank[guild] = g
  local perTab = MAX_GUILDBANK_SLOTS_PER_TAB or 98
  local changed = false
  for tab = 1, GetNumGuildBankTabs() or 0 do
    local out, index, seenAny = {}, {}, false
    for slot = 1, perTab do
      local link = GetGuildBankItemLink(tab, slot)
      if link and not U.Secret(link) then
        seenAny = true
        local it = self:Info(link)
        if self:Tradable(it) then
          local s = U.ItemString(link)
          local _, count = GetGuildBankItemInfo(tab, slot)
          if s then
            local e = index[s]
            if e then e.n = e.n + (count or 1) else
              e = { s = s, n = count or 1 }
              index[s] = e
              out[#out + 1] = e
            end
          end
        end
      end
    end
    -- un onglet pas encore chargé par le jeu ne renvoie rien : on garde ce qu'on en savait
    if seenAny or not g.tabs[tab] then
      table.sort(out, function(a, b) return a.s < b.s end)
      if not sameList(g.tabs[tab], out) then changed = true end
      g.tabs[tab] = out
    end
  end
  g.t, g.by = ns.Now(), ns.me
  if changed then self:Changed() end
end

function Boe:QueryGuildBank()
  if not QueryGuildBankTab or not GetNumGuildBankTabs then return end
  for tab = 1, GetNumGuildBankTabs() or 0 do
    local viewable = true
    if GetGuildBankTabInfo then
      local _, _, isViewable = GetGuildBankTabInfo(tab)
      viewable = isViewable ~= false
    end
    if viewable then pcall(QueryGuildBankTab, tab) end
  end
end

-- ------------------------------------------------------------------ partage avec la bande (jeu de données « o »)
local function encodeList(list)
  local parts = {}
  for _, e in ipairs(list or {}) do parts[#parts + 1] = e.s .. "*" .. (e.n or 1) end
  return table.concat(parts, ",")
end

local function decodeList(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for chunk in text:gmatch("[^,]+") do
    local s, n = chunk:match("^(item:[%-%d:]+)%*(%d+)$")
    if s then out[#out + 1] = { s = s, n = tonumber(n) } end
  end
  return out
end

function Boe:Build()
  local chars, guilds = {}, {}
  for char, e in pairs(ns.db.boe or {}) do
    if e.own and ns.Comm:IsOwnCharacter(char) then
      chars[char] = { b = encodeList(e.b), bt = e.bt, k = e.k and encodeList(e.k) or nil, kt = e.kt }
    end
  end
  for guild, g in pairs(ns.db.gbank or {}) do
    local all = {}
    for _, list in pairs(g.tabs or {}) do
      for _, e in ipairs(list) do all[#all + 1] = e end
    end
    guilds[guild] = { l = encodeList(all), t = g.t, by = g.by }
  end
  return { c = chars, g = guilds }
end

function Boe:OwnHash()
  if not self.hash then
    local parts = {}
    local payload = self:Build()
    local keys = {}
    for char in pairs(payload.c) do keys[#keys + 1] = char end
    table.sort(keys)
    for _, char in ipairs(keys) do
      local e = payload.c[char]
      parts[#parts + 1] = char .. "|" .. e.b .. "|" .. (e.k or "-")
    end
    local guilds = {}
    for guild in pairs(payload.g) do guilds[#guilds + 1] = guild end
    table.sort(guilds)
    for _, guild in ipairs(guilds) do parts[#parts + 1] = guild .. "|" .. payload.g[guild].l .. "|" .. tostring(payload.g[guild].t) end
    self.hash = U.Hash(table.concat(parts, "#"))
  end
  return self.hash
end

function Boe:Apply(sender, payload)
  if type(payload) ~= "table" then return end
  ns.db.boe = ns.db.boe or {}
  ns.db.gbank = ns.db.gbank or {}
  for char, e in pairs(type(payload.c) == "table" and payload.c or {}) do
    local name = type(char) == "string" and U.FullName(char)
    if name and type(e) == "table" and not ns.Comm:IsOwnCharacter(name) then
      local cur = ns.db.boe[name] or {}
      ns.db.boe[name] = cur
      cur.own, cur.src = nil, sender
      -- le plus récent l'emporte (un même reroll peut être partagé par lui-même et par son joueur)
      if tonumber(e.bt) and e.bt >= (cur.bt or 0) then cur.b, cur.bt = decodeList(e.b), e.bt end
      if tonumber(e.kt) and e.kt >= (cur.kt or 0) then cur.k, cur.kt = decodeList(e.k), e.kt end
    end
  end
  for guild, g in pairs(type(payload.g) == "table" and payload.g or {}) do
    if type(guild) == "string" and type(g) == "table" and tonumber(g.t) then
      local cur = ns.db.gbank[guild]
      if not cur or (cur.t or 0) < g.t then
        ns.db.gbank[guild] = { t = g.t, by = g.by, tabs = { [1] = decodeList(g.l) }, remote = true }
      end
    end
  end
  ns:Fire("DATA", "boe")
end

-- ------------------------------------------------------------------ le Coffre : tous les objets de la bande
-- { s, n, owner, place ("b" sac, "k" banque, "g" banque de guilde), t, mine }
function Boe:All()
  local out = {}
  for char, e in pairs(ns.db.boe or {}) do
    local member = ns.db.members[char] or ns.Comm:IsOwnCharacter(char)
    if member then
      local mine = ns.Comm:IsOwnCharacter(char)
      for _, place in ipairs({ "b", "k" }) do
        for _, it in ipairs(e[place] or {}) do
          out[#out + 1] = { s = it.s, n = it.n, owner = char, place = place, t = e[place .. "t"], mine = mine }
        end
      end
    end
  end
  for guild, g in pairs(ns.db.gbank or {}) do
    for _, list in pairs(g.tabs or {}) do
      for _, it in ipairs(list) do
        out[#out + 1] = { s = it.s, n = it.n, owner = guild, place = "g", t = g.t, guild = true }
      end
    end
  end
  return out
end

-- Objets des autres qui intéressent ton personnage.
function Boe:ForMe()
  local n = 0
  for _, e in ipairs(self:All()) do
    if e.owner ~= ns.me and self:Interest(e.s) then n = n + 1 end
  end
  return n
end

-- ------------------------------------------------------------------ butin : prévenir la bande
-- Un objet vient d'arriver dans tes sacs (voir Alerts:ScanLoot). Renvoie vrai s'il s'agit d'un LQE annoncé.
-- Un nouvel exemplaire non lié est-il arrivé ? On compare les exemplaires non liés dans tes sacs à la
-- dernière lecture (faite juste avant) : un objet déjà porté, donc lié, n'est pas annoncé.
local function newUnbound(id)
  local CC = C_Container
  if not (CC and CC.GetContainerItemInfo) then return true end
  local now = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, slotsOf(bag) do
      local info = CC.GetContainerItemInfo(bag, slot)
      if info and info.itemID == id and not info.isBound then now = now + (info.stackCount or 1) end
    end
  end
  local before = 0
  for _, e in ipairs(own().b or {}) do
    if U.ItemID(e.s) == id then before = before + (e.n or 1) end
  end
  return now > before
end

function Boe:OnLoot(link, count)
  self:CheckNeeds(link, count)
  local info = self:Info(link)
  if not self:Tradable(info) or not newUnbound(U.ItemID(link)) then return false end
  ns.Alerts:Emit("boe", { i = link, q = info.q, z = GetRealZoneText() })
  return true
end

-- Ce que tu ramasses figure sur la liste de besoins d'un ami : il est prévenu (une fois par série).
Boe.pendingGot = {}

function Boe:CheckNeeds(link, count)
  local id = U.ItemID(link)
  local name = U.ItemName(link)
  local owners = {}
  for owner, data in pairs(ns.db.needs or {}) do
    if owner ~= ns.me and ns.db.members[owner] and type(data.l) == "table" then
      for _, need in ipairs(data.l) do
        if (id and need.i == id) or (not need.i and name and need.s and U.Fold(need.s) == U.Fold(name)) then
          owners[#owners + 1] = owner
          break
        end
      end
    end
  end
  if #owners == 0 then return end
  local key = id or name
  local p = self.pendingGot[key]
  if not p then
    p = { link = link, n = 0, owners = {} }
    self.pendingGot[key] = p
    C_Timer.After(GOT_WINDOW, function()
      self.pendingGot[key] = nil
      local list = {}
      for o in pairs(p.owners) do list[#list + 1] = o end
      table.sort(list)
      ns.Alerts:Emit("got", { i = p.link, c = p.n, o = list })
    end)
  end
  p.n = p.n + (count or 1)
  for _, o in ipairs(owners) do p.owners[o] = true end
end

-- Quantité encore cherchée par toi pour cet objet (besoin moins ce que tu as déjà).
function Boe:StillNeeded(link)
  local id, name = U.ItemID(link), U.ItemName(link)
  local mine = ns.db.needs[ns.me]
  for _, need in ipairs(mine and mine.l or {}) do
    if (id and need.i == id) or (not need.i and name and need.s and U.Fold(need.s) == U.Fold(name)) then
      local have = ns.Craft and ns.Craft:OwnedFor(need) or 0
      return math.max(0, (need.q or 1) - have), need
    end
  end
  return nil
end

-- ------------------------------------------------------------------ démarrage
function Boe:OnLogin()
  ns.db.boe = ns.db.boe or {}
  ns.db.gbank = ns.db.gbank or {}
  local refresh = function() self:Invalidate() end
  for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
    ns:RegisterEvent(event, function() ns:Debounce("boe-invalidate", 1, refresh) end)
  end
  ns:On("DATA", function(what) if what == "recipes" then ns:Debounce("boe-invalidate", 1, refresh) end end)
  ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() ns:Debounce("boe-items", 1, function() ns:Fire("DATA", "boe") end) end)

  ns:RegisterEvent("BAG_UPDATE_DELAYED", function() ns:Debounce("boe-bags", 2, function() self:ScanBags() end) end)
  ns:RegisterEvent("BANKFRAME_OPENED", function() self.bankOpen = true; self:ScanBank() end)
  ns:RegisterEvent("BANKFRAME_CLOSED", function() self.bankOpen = false end)
  for _, event in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED" }) do
    ns:RegisterEvent(event, function() ns:Debounce("boe-bank", 1, function() self:ScanBank() end) end)
  end

  local openGuildBank = function()
    self.guildBankOpen = true
    self:QueryGuildBank()
    ns:Debounce("boe-gbank", 1, function() self:ScanGuildBank() end)
  end
  ns:RegisterEvent("GUILDBANKFRAME_OPENED", openGuildBank)
  ns:RegisterEvent("GUILDBANKFRAME_CLOSED", function() self.guildBankOpen = false end)
  ns:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", function()
    if self.guildBankOpen then ns:Debounce("boe-gbank", 1, function() self:ScanGuildBank() end) end
  end)
  local GUILD_BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
  if GUILD_BANKER then
    ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) if kind == GUILD_BANKER then openGuildBank() end end)
    ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind) if kind == GUILD_BANKER then self.guildBankOpen = false end end)
  end

  C_Timer.After(3, function() self:ScanBags() end)

  ns.Sync:Dataset("o", {
    prio = 3,
    ownHash = function() return self:OwnHash() end,
    knownHash = function(sender) return ns.Sync:StoredHash(sender, "o") end,
    build = function() return self:Build() end,
    apply = function(sender, payload, hash)
      self:Apply(sender, payload)
      ns.Sync:StoreHash(sender, "o", hash)
    end,
  })
end
