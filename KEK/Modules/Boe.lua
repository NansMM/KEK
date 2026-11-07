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
local PRIMARY = { STRENGTH = "STR", AGILITY = "AGI", INTELLECT = "INT", SPIRIT = "SPI" }
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }

-- Comparaison avec l'objet porté : chaque caractéristique compte selon son importance pour le profil
-- du personnage (voir Boe:Weights).
local STAT_KEYS = {
  STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT", STA = "ITEM_MOD_STAMINA_SHORT",
  INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT",
  dps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", armor = "RESISTANCE0_NAME",
}
local STAT_ORDER = { "STR", "AGI", "INT", "SPI", "STA", "dps", "armor" }
local STAT_FALLBACK = {
  STR = L["Force"], AGI = L["Agilité"], STA = L["Endurance"], INT = L["Intelligence"], SPI = L["Esprit"],
  dps = L["dégâts par seconde"], armor = L["Armure"],
}
local MIN_GAIN = 0.5   -- en dessous, l'écart ne vaut pas une notification
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

-- ------------------------------------------------------------------ profils : ce qui compte pour chaque personnage
-- Tank, mêlée, distance, soigneur ou sorts : détecté d'après la spécialisation (ou la branche de talents la
-- plus remplie), ou choisi à la main dans le Coffre. Chaque membre partage le sien avec la bande.
Boe.PROFILES = { "tank", "melee", "ranged", "healer", "caster" }
Boe.PROFILE_NAMES = { tank = L["Tank"], melee = L["Mêlée"], ranged = L["Distance"], healer = L["Soigneur"], caster = L["Sorts"] }
-- Branches de talents dans l'ordre du jeu (guerrier : Armes, Fureur, Protection ; paladin : Sacré, Protection, Vindicte…).
local SPEC_PROFILE = {
  WARRIOR = { "melee", "melee", "tank" }, PALADIN = { "healer", "tank", "melee" }, HUNTER = { "ranged", "ranged", "ranged" },
  ROGUE = { "melee", "melee", "melee" }, PRIEST = { "healer", "healer", "caster" }, SHAMAN = { "caster", "melee", "healer" },
  MAGE = { "caster", "caster", "caster" }, WARLOCK = { "caster", "caster", "caster" }, DRUID = { "caster", "melee", "healer" },
}
local DEFAULT_PROFILE = {
  WARRIOR = "melee", PALADIN = "melee", HUNTER = "ranged", ROGUE = "melee", PRIEST = "caster",
  SHAMAN = "melee", MAGE = "caster", WARLOCK = "caster", DRUID = "caster",
}

-- Poids de chaque caractéristique (estimation simple pour WoW Classic).
-- dps : arme de mêlée ; rdps : arme à distance (arc, fusil, arbalète, arme de jet, baguette).
function Boe:Weights(class, profile)
  if profile == "tank" then return { STA = 1, STR = 0.6, AGI = 0.6, armor = 0.04, dps = 1.5, rdps = 0.3 } end
  if profile == "healer" then return { INT = 1, SPI = 0.9, STA = 0.4, armor = 0.005, rdps = 0.5 } end
  if profile == "caster" then return { INT = 1, SPI = 0.5, STA = 0.6, armor = 0.005, rdps = 1.5 } end
  if profile == "ranged" then return { AGI = 1, INT = 0.3, STA = 0.4, STR = 0.1, armor = 0.01, dps = 0.5, rdps = 3 } end
  local agile = class == "ROGUE" or class == "HUNTER"
  local w = { STR = agile and 0.6 or 1, AGI = agile and 1 or 0.6, STA = 0.4, armor = 0.01, dps = 3, rdps = 0.5 }
  if class == "DRUID" then w.STR, w.AGI = 0.9, 0.9 end
  return w
end

-- Profil d'après la spécialisation : rôle donné par le jeu, sinon branche de talents la plus remplie.
function Boe:DetectedProfile()
  local _, class = UnitClass("player")
  local index, role
  local me = ns.db.members[ns.me]
  local spec = me and me.spec
  if type(spec) == "table" and not spec.s and #spec > 0 then
    local best = 0
    for i, tab in ipairs(spec) do
      if (tab.p or 0) > best then index, best = i, tab.p end
    end
  else
    local SI = C_SpecializationInfo
    local getSpec = (SI and SI.GetSpecialization) or GetSpecialization
    local getInfo = (SI and SI.GetSpecializationInfo) or GetSpecializationInfo
    if getSpec then
      local ok, i = pcall(getSpec)
      if ok and type(i) == "number" and i > 0 then
        index = i
        if getInfo then
          local ok2, _, _, _, _, r = pcall(getInfo, i)
          if ok2 and type(r) == "string" then role = r end
        end
      end
    end
  end
  if role == "TANK" then return "tank", index end
  if role == "HEALER" then return "healer", index end
  local p = index and SPEC_PROFILE[class] and SPEC_PROFILE[class][index]
  if role == "DAMAGER" and (p == "tank" or p == "healer") then p = nil end
  return p or DEFAULT_PROFILE[class] or "melee", index
end

-- Profil de ton personnage : ton choix (enregistré pour ce personnage) ou la détection automatique.
function Boe:MyProfile()
  local choice = ns.char and ns.char.profile
  if choice and self.PROFILE_NAMES[choice] then return choice, false end
  return (self:DetectedProfile()), true
end

function Boe:SetProfile(choice)
  ns.char.profile = self.PROFILE_NAMES[choice] and choice or nil
  self:Invalidate()
  if ns.Profile then ns.Profile:Changed(2) end
end

function Boe:ProfileOf(who)
  if who == ns.me then return (self:MyProfile()) end
  local m = ns.db.members[who]
  if m and self.PROFILE_NAMES[m.profile] then return m.profile end
  return DEFAULT_PROFILE[m and m.class] or "melee"
end

-- ------------------------------------------------------------------ intérêt pour un membre de la bande
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

local function bagSlots(bag)
  local CC = C_Container
  local fn = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  return fn and fn(bag) or 0
end

local function smallestBag()
  local least
  for bag = 1, (NUM_BAG_SLOTS or 4) do
    local n = bagSlots(bag)
    if not least or n < least then least = n end
  end
  return least or 0
end

-- Pièce portée : { link, name, ilvl, stats }, nil si la case est vide, false si le jeu ne la connaît pas encore.
local function describeWorn(link)
  local name, full, _, ilvl = U.GetItemInfo(link)
  if not name then return false end
  full = full or link
  return { link = full, name = name, ilvl = ilvl or 0, stats = stats(full) }
end

local function equipped(slot)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  if not link then return nil end
  return describeWorn(link) or { link = link, name = U.ItemName(link), ilvl = 0, stats = stats(link) }
end

local function score(st, w, ranged)
  local s = 0
  for k, key in pairs(STAT_KEYS) do
    local weight = w[k] or 0
    if k == "dps" then weight = (ranged and w.rdps or w.dps) or 0 end
    s = s + weight * (tonumber(st and st[key]) or 0)
  end
  return s
end

local function sumStats(a, b)
  local out = {}
  for _, st in ipairs({ a or {}, b or {} }) do
    for k, v in pairs(st) do out[k] = (out[k] or 0) + (tonumber(v) or 0) end
  end
  return out
end

-- « +3 Force, +2 Endurance, −1 Agilité » : les écarts qui comptent pour ce profil.
local function statDelta(new, old, w, ranged)
  local parts = {}
  for _, k in ipairs(STAT_ORDER) do
    local key = STAT_KEYS[k]
    local weight = k == "dps" and ((ranged and w.rdps or w.dps) or 0) or (w[k] or 0)
    local d = (tonumber(new and new[key]) or 0) - (tonumber(old and old[key]) or 0)
    if weight > 0 and math.abs(d) >= 0.05 then
      local label = (type(_G[key]) == "string" and _G[key]) or STAT_FALLBACK[k]
      local value = k == "dps" and string.format("%.1f", math.abs(d)) or tostring(math.floor(math.abs(d) + 0.5))
      parts[#parts + 1] = (d > 0 and "+" or "−") .. value .. " " .. label
      if #parts >= 5 then break end
    end
  end
  return table.concat(parts, ", ")
end

-- La classe peut-elle porter cet objet, à ce niveau (ou dans 3 niveaux) ?
local function usable(info, ctx)
  if not SLOTS[info.equipLoc or ""] then return false end
  local sub, class = info.subclassID, ctx.class
  if info.classID == CLASS_ARMOR and sub and sub ~= 0 and sub ~= 5 and info.equipLoc ~= "INVTYPE_CLOAK" then
    -- (les capes sont en tissu mais vont à tout le monde ; bijoux, colliers et anneaux sont « divers »)
    if sub >= 1 and sub <= 4 then
      if sub ~= mainArmor(class, math.max(ctx.level, info.minLevel)) then return false end
    elseif not (ARMOR_EXTRA[class] or {})[sub] then
      return false
    end
  elseif info.classID == CLASS_WEAPON then
    if not (WEAPON[class] or {})[sub] then return false end
  elseif info.classID ~= CLASS_ARMOR then
    return false
  end
  return info.minLevel <= ctx.level + LEVEL_MARGIN
end

local function overlaps(locA, locB)
  for _, a in ipairs(SLOTS[locA or ""] or {}) do
    for _, b in ipairs(SLOTS[locB or ""] or {}) do
      if a == b then return true end
    end
  end
  return false
end

-- Ce qu'il faut savoir d'un membre pour juger : classe, niveau, profil, équipement porté.
-- nil si on ne sait pas ce qu'il porte (membre avec une ancienne version de KEK).
function Boe:Context(who)
  if who == ns.me then
    local _, class = UnitClass("player")
    local profile = self:MyProfile()
    return { who = who, me = true, class = class, level = UnitLevel("player") or 1, profile = profile,
      w = self:Weights(class, profile), equipped = equipped, bag = smallestBag(), bagGear = self:BagGear() }
  end
  local m = ns.db.members[who]
  local gear = ns.db.gear and ns.db.gear[who]
  if not m or not m.class or not gear then return nil end
  local profile = self:ProfileOf(who)
  return {
    who = who, class = m.class, level = m.level or 1, profile = profile, w = self:Weights(m.class, profile), bag = gear.bs,
    equipped = function(slot)
      local s = gear.s and gear.s[slot]
      if not s then return nil end
      return describeWorn(s)
    end,
  }
end

-- Ton personnage, mais avec une autre classe, un autre niveau ou un autre profil (essais, autotest).
function Boe:ContextAs(class, level, profile)
  local ctx = self:Context(ns.me)
  ctx.class, ctx.level = class or ctx.class, level or ctx.level
  ctx.profile = profile or (class and DEFAULT_PROFILE[class]) or ctx.profile
  ctx.w = self:Weights(ctx.class, ctx.profile)
  ctx.bagGear = nil
  return ctx
end

-- Pièces d'équipement que tu gardes dans tes sacs (pas encore enfilées, ou de rechange).
function Boe:BagGear()
  if self.bagGearV == self.version then return self.bagGearList end
  local list = {}
  local CC = C_Container
  if CC and CC.GetContainerItemInfo then
    for bag = 0, (NUM_BAG_SLOTS or 4) do
      for slot = 1, bagSlots(bag) do
        local item = CC.GetContainerItemInfo(bag, slot)
        local it = item and item.hyperlink and self:Info(item.hyperlink)
        if it and SLOTS[it.equipLoc or ""] then list[#list + 1] = { info = it, stats = stats(it.link) } end
      end
    end
  end
  self.bagGearV, self.bagGearList = self.version, list
  return list
end

-- Renvoie la raison et l'intérêt (gain), ou nil ; nil, true si le jeu ne connaît pas encore une pièce portée.
function Boe:EquipReason(info, ctx)
  if not usable(info, ctx) then return nil end
  local w, ranged = ctx.w, RANGED[info.equipLoc] or false
  local st = stats(info.link)
  if st then
    -- des caractéristiques principales, mais aucune utile à ce profil : rien à signaler
    local primary, useful = false, false
    for long, short in pairs(PRIMARY) do
      if (tonumber(st["ITEM_MOD_" .. long .. "_SHORT"]) or 0) > 0 then
        primary = true
        if (w[short] or 0) >= 0.5 then useful = true end
      end
    end
    if primary and not useful then return nil end
  end
  local newScore = st and score(st, w, ranged)
  -- tu as déjà aussi bien dans tes sacs (pas encore enfilé, ou de rechange)
  if ctx.bagGear and newScore then
    for _, g in ipairs(ctx.bagGear) do
      if g.stats and overlaps(g.info.equipLoc, info.equipLoc) and usable(g.info, ctx)
        and score(g.stats, w, RANGED[g.info.equipLoc] or false) >= newScore then
        return nil
      end
    end
  end
  -- compare avec la pièce la plus faible parmi les cases possibles (anneaux, bijoux, armes à une main)
  local list = SLOTS[info.equipLoc]
  if info.equipLoc == "INVTYPE_WEAPON" and not DUAL_WIELD[ctx.class] then list = { 16 } end
  local old, empty = nil, false
  for _, slot in ipairs(list) do
    local cur = ctx.equipped(slot)
    if cur == false then return nil, true end
    if not cur then empty = true; break end
    if info.equipLoc == "INVTYPE_2HWEAPON" then
      -- une arme à deux mains remplace aussi ce qui est tenu en main gauche
      local off = ctx.equipped(17)
      if off == false then return nil, true end
      if off then
        cur.stats = cur.stats and off.stats and sumStats(cur.stats, off.stats) or cur.stats
        cur.name = (cur.name or "?") .. " + " .. (off.name or "?")
      end
    end
    cur.score = cur.stats and score(cur.stats, w, ranged)
    if not old or (cur.score and old.score and cur.score < old.score) or (not (cur.score and old.score) and cur.ilvl < old.ilvl) then
      old = cur
    end
  end
  local parts, gain = {}, 1
  if empty or not old then
    parts[1] = string.format(L["%s : emplacement vide"], self.SLOT_NAMES[info.equipLoc] or "?")
    local delta = st and statDelta(st, nil, w, ranged) or ""
    if delta ~= "" then parts[#parts + 1] = delta end
    gain = (newScore or 0) + 2
  elseif st and old.stats then
    -- caractéristiques connues des deux côtés : on compare leur valeur pour ce profil
    gain = newScore - (old.score or 0)
    if gain < MIN_GAIN then return nil end
    local delta = statDelta(st, old.stats, w, ranged)
    parts[1] = delta ~= "" and string.format(L["%s par rapport à %s"], delta, old.name or "?")
      or string.format(L["meilleur que %s"], old.name or "?")
  else
    -- le jeu ne donne pas les caractéristiques : on se contente du niveau d'objet
    if info.ilvl <= old.ilvl then return nil end
    gain = (info.ilvl - old.ilvl) / 2
    parts[1] = string.format(L["meilleur que l'objet porté (niveau %d contre %d)"], info.ilvl, old.ilvl)
  end
  if info.minLevel > ctx.level then
    local n = info.minLevel - ctx.level
    parts[#parts + 1] = string.format(n == 1 and L["utilisable dans %d niveau"] or L["utilisable dans %d niveaux"], n)
  end
  return table.concat(parts, " · "), gain
end

local function professionOf(who, name)
  local m = ns.db.members[who]
  local want = U.Fold(name or "")
  for _, p in ipairs(m and type(m.profs) == "table" and m.profs or {}) do
    if U.Fold(p.n or "") == want then return p end
  end
  return nil
end

local function knowsRecipe(who, prof, recipeName)
  local data = ns.db.recipes[who]
  local entry = data and data.p and data.p[prof]
  if not entry or type(entry.l) ~= "table" then return false end
  local want = U.Fold(recipeName)
  for name in pairs(entry.l) do
    if U.Fold(name) == want then return true end
  end
  return false
end

function Boe:RecipeReason(info, ctx)
  local prof = professionOf(ctx.who, info.subType)
  if not prof then return nil end
  local recipe = info.name:match("^[^:]+:%s*(.+)$") or info.name
  if knowsRecipe(ctx.who, prof.n, recipe) then return nil end
  local need
  local pattern = patternOf(ITEM_MIN_SKILL or "Requires %s (%d)")
  for _, line in ipairs(tooltipLines(info.link) or {}) do
    need = need or tonumber(line:match(pattern or "%((%d+)%)"))
  end
  if ctx.me then
    if need and need > (prof.r or 0) then
      return string.format(L["recette de %s que tu n'as pas (requiert %d, tu es à %d)"], prof.n, need, prof.r or 0)
    end
    return string.format(L["recette de %s que tu n'as pas"], prof.n)
  end
  if need then return string.format(L["recette de %s pas encore apprise (requiert %d, rang %d)"], prof.n, need, prof.r or 0) end
  return string.format(L["recette de %s pas encore apprise"], prof.n)
end

function Boe:BagReason(info, ctx)
  local least = ctx.bag
  if not least then return nil end
  local pattern = patternOf(CONTAINER_SLOTS or "%d Slot %s")
  local slots
  for _, line in ipairs(tooltipLines(info.link) or {}) do
    slots = slots or tonumber(line:match(pattern or "(%d+)"))
  end
  if not slots or slots <= least then return nil end
  if ctx.me then
    if least == 0 then return string.format(L["sac de %d places, et tu as un emplacement de sac libre"], slots) end
    return string.format(L["sac de %d places (ton plus petit : %d)"], slots, least)
  end
  if least == 0 then return string.format(L["sac de %d places, et un emplacement de sac libre"], slots) end
  return string.format(L["sac de %d places (plus petit sac : %d)"], slots, least)
end

-- Pourquoi cet objet intéresse un membre (ton personnage par défaut), et à quel point : texte, gain ; ou nil.
-- Gardé en cache jusqu'au prochain changement d'équipement, de niveau, de profil ou de recettes.
Boe.cache, Boe.version = {}, 0

function Boe:Invalidate()
  self.version = self.version + 1
  ns:Fire("DATA", "boe")
end

function Boe:Interest(item, who)
  who = who or ns.me
  local m = who ~= ns.me and ns.db.members[who]
  local key = who .. "|" .. (m and ((m.level or 0) .. (m.profile or "")) or "") .. "|" .. (U.ItemString(item) or tostring(item))
  local hit = self.cache[key]
  if hit and hit.v == self.version then return hit.r or nil, hit.g end
  local info = self:Info(item)
  if not info then return nil end                 -- pas encore en cache : on réessaiera
  local ctx = self:Context(who)
  if not ctx then return nil end
  local ok, reason, extra = pcall(function()
    if info.classID == CLASS_RECIPE then return self:RecipeReason(info, ctx), 1 end
    if info.classID == CLASS_CONTAINER then return self:BagReason(info, ctx), 1 end
    return self:EquipReason(info, ctx)
  end)
  if not ok then ns.Report(reason); return nil end
  if reason == nil and extra == true then return nil end   -- pièce portée pas encore connue : on réessaiera
  self.cache[key] = { v = self.version, r = reason or false, g = reason and extra or nil }
  return reason, reason and extra or nil
end

-- Les membres de la bande que cet objet intéresse, du plus intéressé au moins intéressé (sauf « except »).
function Boe:Fans(item, except)
  local out = {}
  for name in pairs(ns.db.members) do
    if name ~= except and (name == ns.me or (ns.db.gear and ns.db.gear[name])) then
      local reason, gain = self:Interest(item, name)
      if reason then out[#out + 1] = { who = name, reason = reason, gain = gain or 0 } end
    end
  end
  table.sort(out, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.who < b.who
  end)
  return out
end

-- ------------------------------------------------------------------ ton équipement, partagé (jeu de données « q »)
local function encodeGear(s)
  local parts = {}
  for slot = 1, 19 do
    if s[slot] then parts[#parts + 1] = slot .. "=" .. s[slot] end
  end
  return table.concat(parts, ";")
end

local function decodeGear(text)
  local s = {}
  if type(text) ~= "string" then return s end
  for slot, str in text:gmatch("(%d+)=(item:[%-%d:]+)") do s[tonumber(slot)] = str end
  return s
end

function Boe:ScanGear()
  ns.db.gear = ns.db.gear or {}
  local s = {}
  for slot = 1, 18 do
    if slot ~= 4 then
      local str = U.ItemString(GetInventoryItemLink and GetInventoryItemLink("player", slot))
      if str then s[slot] = str end
    end
  end
  local enc, bs = encodeGear(s), smallestBag()
  local cur = ns.db.gear[ns.me]
  if cur and cur.e == enc and cur.bs == bs then return end
  ns.db.gear[ns.me] = { s = s, e = enc, bs = bs, t = ns.Now() }
  self:Invalidate()
  ns:Debounce("boe-push-gear", 8, function() ns.Sync:Push("q") end)
end

function Boe:ApplyGear(sender, payload)
  if type(payload) ~= "table" or type(payload.e) ~= "string" then return end
  ns.db.gear = ns.db.gear or {}
  local s = decodeGear(payload.e)
  ns.db.gear[sender] = { s = s, e = payload.e, bs = tonumber(payload.bs), t = ns.Now() }
  -- demande au jeu les objets portés qu'il ne connaît pas encore (pour pouvoir comparer)
  for _, str in pairs(s) do
    if not U.GetItemInfo(str) and C_Item and C_Item.RequestLoadItemDataByID then
      pcall(C_Item.RequestLoadItemDataByID, U.ItemID(str))
    end
  end
  self:Invalidate()
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
  -- à qui le proposer : les membres de la bande qu'il intéresse
  if ns.db.alerts.boe and ns.Toasts then
    local fans = self:Fans(link, ns.me)
    if #fans > 0 then ns.Toasts:Show(self:FansToast(link, info, fans)) end
  end
  return true
end

-- « [Bottes] intéressent Marc et Kevin » : notification pour toi seul, quand tu ramasses un objet LQE.
function Boe:FansToast(link, info, fans)
  local names = {}
  for i, f in ipairs(fans) do
    if i <= 2 then names[#names + 1] = U.MemberName(f.who) end
  end
  local who = table.concat(names, L[" et "])
  if #fans > 2 then who = string.format(L["%s et %d autre(s)"], table.concat(names, ", "), #fans - 2) end
  local item = U.ItemText(link, U.ItemID(link))
  return {
    kind = "boefor", who = ns.me, title = string.format(L["%s intéresse %s"], item, who),
    body = string.format(L["%s : %s"], U.Short(fans[1].who), fans[1].reason),
    label = L["À PROPOSER"], color = { 0.12, 1.00, 0.00 }, glyph = "chest", sound = "boe", duration = 10,
    icon = U.ItemIcon(U.ItemID(link)), quality = info.q, link = link, view = "chest",
  }
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
  for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    ns:RegisterEvent(event, function() ns:Debounce("boe-invalidate", 1, refresh) end)
  end
  ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() ns:Debounce("boe-gear", 1, function() self:ScanGear(); refresh() end) end)
  ns:On("DATA", function(what) if what == "recipes" then ns:Debounce("boe-invalidate", 1, refresh) end end)
  ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() ns:Debounce("boe-items", 1, function() ns:Fire("DATA", "boe") end) end)

  -- sacs : objets à échanger, taille des sacs, pièces de rechange (comparées aux objets proposés)
  ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
    ns:Debounce("boe-bags", 2, function() self:ScanBags(); self:ScanGear(); refresh() end)
  end)
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

  C_Timer.After(3, function() self:ScanBags(); self:ScanGear() end)

  ns.Sync:Dataset("q", {
    prio = 3,
    ownHash = function()
      local g = ns.db.gear and ns.db.gear[ns.me]
      return g and U.Hash((g.e or "") .. "|" .. tostring(g.bs)) or nil
    end,
    knownHash = function(sender) return ns.Sync:StoredHash(sender, "q") end,
    build = function()
      local g = ns.db.gear and ns.db.gear[ns.me] or {}
      return { e = g.e or "", bs = g.bs }
    end,
    apply = function(sender, payload, hash)
      self:ApplyGear(sender, payload)
      ns.Sync:StoreHash(sender, "q", hash)
    end,
  })

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
