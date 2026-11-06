-- KEK — utilitaires : noms, couleurs, formats, objets, métiers.
local _, ns = ...
local L = ns.L

local U = {}
ns.U = U

local floor, abs, max, min = math.floor, math.abs, math.max, math.min
local format, tostring, tonumber, type = string.format, tostring, tonumber, type

-- ------------------------------------------------------------------ compatibilité WoW Forever (interface 12.x)
-- Les fonctions dépréciées de l'ancienne interface ont disparu : on prend la version C_* quand elle existe.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
U.GetItemInfo = GetItemInfo

-- En donjon, le jeu remplace certaines données par des « valeurs secrètes » qu'un addon ne peut pas lire
-- (messages du chat, noms des créatures…). Toute manipulation provoquerait une erreur : on les écarte.
function U.Secret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Vrai sur un client de l'ère « Midnight » (WoW Forever), où ces restrictions s'appliquent.
U.RESTRICTED = issecretvalue ~= nil

-- Champ de bataille ou arène : les morts n'y comptent pas.
function U.InPvP()
  local inInstance, kind = IsInInstance()
  if U.Secret(kind) then return false end
  return inInstance and (kind == "pvp" or kind == "arena") or false
end

function U.OpenChat(text)
  local fn = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
  if fn then pcall(fn, text) end
end

function U.InsertLink(link)
  local fn = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
  if fn then
    local ok, res = pcall(fn, link)
    return ok and res
  end
end

function U.AddMessageFilter(event, fn)
  local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
  if add then pcall(add, event, fn) end
end

-- ------------------------------------------------------------------ noms
function U.Realm()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if not realm or realm == "" then
    realm = (GetRealmName and GetRealmName() or ""):gsub("[%s%-]", "")
  end
  return realm
end

-- Séparateurs possibles entre le nom et le royaume : WoW Forever envoie par exemple « Nokie Jenkins »
-- au lieu de « Nokie-Jenkins ». Un nom de personnage ne contient jamais d'espace ni de tiret.
local NAME_SEPARATORS = {
  "-", " ",
  "\194\160",                                         -- espace insécable
  "\226\128\144", "\226\128\145", "\226\128\146",     -- tirets typographiques
  "\226\128\147", "\226\128\148", "\226\136\146",
}

-- WoW Forever : les personnages ont un prénom et un nom de famille (« Nokie Jenkins »), et le jeu les
-- identifie par ces deux mots, sans royaume (les royaumes internes « CAMWOWEU5Realm6PvP » d'un même
-- méga-royaume ne servent pas à les désigner). UnitName("player") renvoie alors prénom, nom.
U.SURNAMES = false

function U.DetectNames(first, second)
  if type(second) == "string" and second ~= "" and not U.Secret(second)
    and second:gsub("[%s%-]", "") ~= U.Realm() then
    U.SURNAMES = true
  end
end

-- Un « royaume » collé au nom (« -CAMWOWEU5Realm6PvP », ou le nôtre) plutôt qu'un nom de famille.
local function looksLikeRealm(token)
  return token == U.Realm() or token:find("%d") ~= nil
end

local function splitName(name)
  local cut, len
  for _, sep in ipairs(NAME_SEPARATORS) do
    local i = name:find(sep, 1, true)
    if i and i > 1 and (not cut or i < cut) then cut, len = i, #sep end
  end
  if not cut then return name, nil end
  local rest = name:sub(cut + len)
  rest = rest:match("^([^%-]+)") or rest            -- s'arrête au tiret suivant
  rest = rest:gsub("^[%s]+", ""):gsub("[%s]+$", ""):gsub("\194\160", "")
  return name:sub(1, cut - 1), rest
end

-- Identité canonique d'un joueur, quel que soit le format reçu du jeu :
-- « Prénom Nom » sur WoW Forever, « Nom-Royaume » ailleurs.
function U.FullName(name, realm)
  if type(name) ~= "string" or name == "" then return nil end
  if U.SURNAMES then
    local first, rest = splitName(name)
    if not rest then
      if type(realm) == "string" and realm ~= "" and not looksLikeRealm(realm) then return first .. " " .. realm end
      return first
    end
    if rest == "" or looksLikeRealm(rest) then return first end
    return first .. " " .. rest
  end
  local cut, len
  for _, sep in ipairs(NAME_SEPARATORS) do
    local i = name:find(sep, 1, true)
    if i and i > 1 and (not cut or i < cut) then cut, len = i, #sep end
  end
  if not cut then return name .. "-" .. (realm or U.Realm()) end
  local short = name:sub(1, cut - 1)
  -- le royaume s'arrête au tiret suivant (anciens noms mal formés : « Nokie Jenkins-Jenkins »)
  local rest = name:sub(cut + len)
  rest = rest:match("^([^%-]+)") or rest
  rest = rest:gsub("[%s%-]", ""):gsub("\194\160", "")
  if rest == "" then rest = realm or U.Realm() end
  return short .. "-" .. rest
end

function U.Short(full)
  if type(full) ~= "string" then return "?" end
  return full:match("^(.-)%-") or full
end

function U.RealmOf(full)
  return type(full) == "string" and full:match("%-(.+)$") or nil
end

-- ------------------------------------------------------------------ couleurs
local CLASS_FALLBACK = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
  ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 }, SHAMAN = { 0.00, 0.44, 0.87 },
  MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1.00, 0.49, 0.04 },
  DEATHKNIGHT = { 0.77, 0.12, 0.23 }, MONK = { 0.00, 1.00, 0.60 }, DEMONHUNTER = { 0.64, 0.19, 0.79 },
}

function U.ClassColor(class)
  local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
  if c then return c.r, c.g, c.b end
  local f = class and CLASS_FALLBACK[class]
  if f then return f[1], f[2], f[3] end
  return 0.72, 0.74, 0.80
end

function U.Hex(r, g, b)
  return format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

function U.Color(text, r, g, b)
  return "|c" .. U.Hex(r, g, b) .. tostring(text) .. "|r"
end

function U.ClassName(full, class)
  local r, g, b = U.ClassColor(class)
  return U.Color(U.Short(full), r, g, b)
end

function U.MemberName(full)
  local m = ns.db and ns.db.members[full]
  return U.ClassName(full, m and m.class)
end

local QUALITY_FALLBACK = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.90, 0.80, 0.50 }, [7] = { 0, 0.8, 1 },
}
local QUALITY_BY_HEX = {
  ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6, ff00ccff = 7,
}

function U.QualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  c = QUALITY_FALLBACK[q] or QUALITY_FALLBACK[1]
  return c[1], c[2], c[3]
end

-- ------------------------------------------------------------------ formats
function U.Round(x, decimals)
  local m = 10 ^ (decimals or 0)
  return floor(x * m + 0.5) / m
end

function U.Clamp(x, a, b)
  if x < a then return a elseif x > b then return b end
  return x
end

function U.Num(n)
  n = floor((n or 0) + 0.5)
  local s = tostring(abs(n))
  s = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
  return (n < 0 and "-" or "") .. s
end

function U.Compact(n)
  n = n or 0
  local a = abs(n)
  local s
  if a >= 1e6 then s = format("%.1f M", n / 1e6)
  elseif a >= 1e4 then s = format("%.1f k", n / 1e3)
  else return U.Num(n) end
  return (s:gsub("%.0 ", " "):gsub("%.", ","))
end

function U.Percent(x)
  return format("%d %%", floor((x or 0) * 100 + 0.5))
end

function U.Duration(sec)
  sec = max(0, floor(sec or 0))
  local h, m = floor(sec / 3600), floor((sec % 3600) / 60)
  if h >= 1 then
    if m > 0 then return format("%d h %02d", h, m) end
    return format("%d h", h)
  end
  if m >= 1 then return format("%d min", m) end
  return format("%d s", sec)
end

function U.Played(sec)
  sec = max(0, floor(sec or 0))
  local d = floor(sec / 86400)
  if d >= 2 then return format("%d j %d h", d, floor((sec % 86400) / 3600)) end
  return U.Duration(sec)
end

function U.Ago(ts)
  if not ts then return L["jamais"] end
  local d = ns.Now() - ts
  if d < 45 then return L["à l'instant"] end
  if d < 3600 then return format(L["il y a %d min"], max(1, floor(d / 60 + 0.5))) end
  if d < 86400 then return format(L["il y a %d h"], max(1, floor(d / 3600 + 0.5))) end
  local days = floor(d / 86400 + 0.5)
  if days <= 1 then return L["hier"] end
  return format(L["il y a %d j"], days)
end

local DAYS = { "dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi" }
local MONTHS = { "janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc." }

local function dayIndex(ts)
  local t = date("*t", ts)
  return t.year * 400 + t.yday, t
end

function U.DayLabel(ts)
  local today = dayIndex(ns.Now())
  local idx, t = dayIndex(ts)
  if idx == today then return L["Aujourd'hui"] end
  if idx == today - 1 then return L["Hier"] end
  local day = DAYS[t.wday] or ""
  return format("%s%s %d %s", day:sub(1, 1):upper(), day:sub(2), t.day, MONTHS[t.month] or "")
end

function U.ShortDate(ts)
  local t = date("*t", ts)
  return format("%d %s", t.day, MONTHS[t.month] or "")
end

function U.Clock(ts)
  return date("%H:%M", ts)
end

local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function U.Money(copper, signed, short)
  copper = floor(copper or 0)
  local sign = ""
  if copper < 0 then sign = "-" elseif signed and copper > 0 then sign = "+" end
  copper = abs(copper)
  local g, s, c = floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
  local out
  if g > 0 and short then
    out = format("%s" .. COIN, U.Num(g), "Gold")
  elseif g > 0 then
    out = format("%s" .. COIN .. " %d" .. COIN, U.Num(g), "Gold", s, "Silver")
  elseif s > 0 then
    out = format("%d" .. COIN .. " %d" .. COIN, s, "Silver", c, "Copper")
  else
    out = format("%d" .. COIN, c, "Copper")
  end
  return sign .. out
end

-- Version « texte seul » pour le chat (les icônes n'y passent pas).
function U.MoneyPlain(copper)
  copper = floor(copper or 0)
  local sign = copper < 0 and "-" or "+"
  copper = abs(copper)
  local g, s = floor(copper / 10000), floor((copper % 10000) / 100)
  if g > 0 then return format("%s%d po %d pa", sign, g, s) end
  return format("%s%d pa %d pc", sign, s, copper % 100)
end

-- Recherche insensible à la casse et aux accents.
local ACCENTS = {
  ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a",
  ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e",
  ["î"] = "i", ["ï"] = "i", ["Î"] = "i", ["ô"] = "o", ["ö"] = "o", ["Ô"] = "o",
  ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Û"] = "u", ["ç"] = "c", ["Ç"] = "c", ["œ"] = "oe",
}
function U.Fold(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("[\195\197][\128-\191]", ACCENTS)
  return s:lower()
end

local UPPER = {
  ["à"] = "À", ["â"] = "Â", ["ä"] = "Ä", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë",
  ["î"] = "Î", ["ï"] = "Ï", ["ô"] = "Ô", ["ö"] = "Ö", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["ç"] = "Ç",
}
function U.Upper(s)
  if type(s) ~= "string" then return "" end
  return (s:upper():gsub("\195[\160-\191]", UPPER))
end

function U.Hash(s)
  -- reste sous 2^31 pour que %x ne déborde pas (long 32 bits sous Windows)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483647
  end
  return format("%08x", h)
end

function U.Copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = U.Copy(v) end
  return out
end

function U.Count(t)
  local n = 0
  if t then for _ in pairs(t) do n = n + 1 end end
  return n
end

-- ------------------------------------------------------------------ objets
U.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

function U.ItemID(link)
  if type(link) == "number" then return link end
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

function U.ItemIcon(id)
  id = U.ItemID(id)
  if not id then return U.QUESTION end
  local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
  if not icon and GetItemInfo then icon = select(10, GetItemInfo(id)) end
  return icon or U.QUESTION
end

function U.ItemQuality(link)
  if not link then return nil end
  local q = GetItemInfo and select(3, GetItemInfo(link))
  if q then return q end
  if type(link) == "string" then
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    if hex then return QUALITY_BY_HEX[hex:lower()] end
  end
  return nil
end

function U.ItemName(link)
  if type(link) == "string" then
    local name = link:match("|h%[(.-)%]|h")
    if name then return name end
  end
  local name = GetItemInfo and GetItemInfo(link)
  return name
end

-- Lien affichable même quand l'objet n'est pas encore en cache.
function U.ItemText(link, id, fallbackName)
  if type(link) == "string" and link:find("|H", 1, true) then return link end
  if id and GetItemInfo then
    local _, cached = GetItemInfo(id)
    if cached then return cached end
  end
  return fallbackName or ("#" .. tostring(id or "?"))
end

-- ------------------------------------------------------------------ classes et métiers
local CLASS_TCOORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 }, DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
}
U.CLASS_TEXTURE = "Interface\\WorldStateFrame\\Icons-Classes"

function U.ClassCoords(class)
  local c = (CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]) or (class and CLASS_TCOORDS[class])
  if not c then return nil end
  -- recadrage léger pour masquer la bordure de l'atlas
  local dx, dy = (c[2] - c[1]) * 0.08, (c[4] - c[3]) * 0.08
  return c[1] + dx, c[2] - dx, c[3] + dy, c[4] - dy
end

function U.ClassLabel(class)
  return (class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or "?"
end

local PROF = {
  { "Trade_Alchemy", "Alchimie", "Alchemy" },
  { "Trade_BlackSmithing", "Forge", "Blacksmithing" },
  { "Trade_Engraving", "Enchantement", "Enchanting" },
  { "Trade_Engineering", "Ingénierie", "Engineering" },
  { "Spell_Nature_NatureTouchGrow", "Herboristerie", "Herbalism" },
  { "Trade_LeatherWorking", "Travail du cuir", "Leatherworking" },
  { "Trade_Mining", "Minage", "Mining" },
  { "INV_Misc_Pelt_Wolf_01", "Dépeçage", "Skinning" },
  { "Trade_Tailoring", "Couture", "Tailoring" },
  { "INV_Misc_Gem_01", "Joaillerie", "Jewelcrafting" },
  { "INV_Misc_Food_15", "Cuisine", "Cooking", secondary = true },
  { "Spell_Holy_SealOfSacrifice", "Secourisme", "First Aid", secondary = true },
  { "Trade_Fishing", "Pêche", "Fishing", secondary = true },
}
U.PROF_ICON, U.PROF_SECONDARY = {}, {}
for _, p in ipairs(PROF) do
  for i = 2, #p do
    U.PROF_ICON[p[i]] = "Interface\\Icons\\" .. p[1]
    if p.secondary then U.PROF_SECONDARY[p[i]] = true end
  end
end

function U.ProfIcon(name)
  return U.PROF_ICON[name] or "Interface\\Icons\\INV_Misc_Note_01"
end

-- ------------------------------------------------------------------ sons
U.SOUNDS = {
  level = 888,      -- fanfare de niveau
  loot = 8959,      -- alerte de raid
  death = 8960,     -- appel aux armes
  boss = 8959,
  need = 878,       -- un ami a besoin de quelque chose
  skill = 878,      -- quête terminée
  presence = 3081,  -- chuchotement
  max = 888,
}

function U.PlayAlert(kind)
  if not (ns.db and ns.db.alerts.sound) then return end
  local custom = "Interface\\AddOns\\" .. ns.ADDON .. "\\Sounds\\" .. kind .. ".ogg"
  local ok, willPlay = pcall(PlaySoundFile, custom, "Master")
  if ok and willPlay then return end
  local id = U.SOUNDS[kind]
  if id then pcall(PlaySound, id, "Master") end
end

function U.Click()
  pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856)
end

-- ------------------------------------------------------------------ table d'XP classique (niveau L -> L+1)
U.XP = {
  400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
  8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
  25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
  50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
  95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
  153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}
U.CUMXP = { [1] = 0 }
for level = 2, 60 do U.CUMXP[level] = U.CUMXP[level - 1] + U.XP[level - 1] end
