-- KEK — récap de soirée : XP, or, ennemis, quêtes, morts, zones, butin.
-- (WoW Forever ferme le journal de combat aux addons : pas de dégâts ni de soins, et les ennemis
-- sont comptés grâce aux messages « X meurt, vous gagnez N points d'expérience ».)
local _, ns = ...
local L, U = ns.L, ns.U

local Session = ns:NewModule("Session", 42)

local RESUME_WINDOW = 15 * 60   -- un /reload ou une reconnexion rapide prolonge la même soirée
local MIN_ARCHIVE = 5 * 60

-- « %s meurt, vous gagnez %d points d'expérience. » -> « ^.+ meurt, vous gagnez %d+ »
-- (le début suffit : les variantes avec bonus de repos ou de groupe commencent pareil)
local function killPattern()
  local fmt = COMBATLOG_XPGAIN_FIRSTPERSON
  if type(fmt) ~= "string" then return nil end
  fmt = fmt:gsub("%%%d%$", "%%")
  local cut = fmt:find("%d", 1, true)
  if not cut or not fmt:find("%s", 1, true) then return nil end
  local head = fmt:sub(1, cut - 1):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  head = head:gsub("%%s", ".+")
  return "^" .. head .. "%d+"
end

local function newSession()
  return {
    s = ns.Now(), u = ns.Now(), d = 0, xp = 0, lv = 0, g = 0, gi = 0, k = 0, de = 0, q = 0,
    it = 0, z = {}, b = nil, bq = -1, lvs = UnitLevel("player"),
  }
end

function Session:OnLogin()
  local char = ns.char
  local cur = char.session
  if cur and ns.Now() - (cur.u or 0) < RESUME_WINDOW then
    self.cur = cur
  else
    if cur and (cur.d or 0) >= MIN_ARCHIVE then char.last = cur end
    self.cur = newSession()
    char.session = self.cur
  end
  self.cur.z = self.cur.z or {}
  self.guid = UnitGUID("player")
  self.money = GetMoney()
  self.xp, self.xpMax, self.level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  self.tick = GetTime()

  ns:RegisterEvent("PLAYER_XP_UPDATE", function() self:OnXP() end)
  ns:RegisterEvent("PLAYER_LEVEL_UP", function() self.cur.lv = self.cur.lv + 1 end)
  ns:RegisterEvent("PLAYER_MONEY", function() self:OnMoney() end)
  ns:RegisterEvent("PLAYER_DEAD", function()
    if not U.InPvP() then self.cur.de = self.cur.de + 1 end   -- champs de bataille et arènes exclus
  end)
  ns:RegisterEvent("QUEST_TURNED_IN", function() self.cur.q = self.cur.q + 1 end)
  ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() self:OnZone() end)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:OnZone() end)
  self.killPattern = killPattern()
  ns:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, msg)
    if not self.killPattern or type(msg) ~= "string" or U.Secret(msg) then return end
    if msg:find(self.killPattern) then self.cur.k = self.cur.k + 1 end
  end)
  ns:RegisterEvent("PLAYER_LOGOUT", function() self:Update() end)
  ns:On("LOOT_SELF", function(link, count) self:OnLoot(link, count) end)

  C_Timer.NewTicker(20, function() self:Update() end)
  self:Update()
end

function Session:Update()
  local now = GetTime()
  self.cur.d = (self.cur.d or 0) + (now - self.tick)
  self.tick = now
  self.cur.u = ns.Now()
  ns.Store:Me().session = self:Compact(self.cur)
  ns:Fire("DATA", "session")
end

function Session:OnXP()
  local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if level > self.level then
    self.cur.xp = self.cur.xp + math.max(0, self.xpMax - self.xp) + xp
  elseif level == self.level then
    self.cur.xp = self.cur.xp + math.max(0, xp - self.xp)
  end
  self.xp, self.xpMax, self.level = xp, max, level
end

function Session:OnMoney()
  local money = GetMoney()
  local delta = money - (self.money or money)
  self.money = money
  self.cur.g = self.cur.g + delta
  if delta > 0 then self.cur.gi = self.cur.gi + delta end
end

function Session:OnZone()
  local zone = GetRealZoneText()
  if zone and zone ~= "" then self.cur.z[zone] = true end
end

function Session:OnLoot(link, count)
  self.cur.it = self.cur.it + (count or 1)
  local q = U.ItemQuality(link) or 1
  if q > (self.cur.bq or -1) then
    self.cur.b, self.cur.bq = link, q
  end
end

-- Version partagée (réseau / affichage).
function Session:Compact(s)
  if not s then return nil end
  local d = math.floor(s.d or 0)
  return {
    s = s.s, u = s.u, d = d, xp = s.xp, lv = s.lv, g = s.g, gi = s.gi, k = s.k,
    de = s.de, q = s.q, it = s.it, zc = U.Count(s.z), b = s.b, bq = s.bq,
    xph = d >= 600 and math.floor((s.xp or 0) * 3600 / d) or 0,
  }
end

function Session:Current() return self:Compact(self.cur) end
function Session:Last() return self:Compact(ns.char.last) end

-- Membres ayant joué ces dernières heures, pour le podium de la soirée.
function Session:Tonight()
  local out, now = {}, ns.Now()
  for name, m in pairs(ns.db.members) do
    local s = (name == ns.me) and self:Current() or m.session
    if type(s) == "table" and s.u and now - s.u < 16 * 3600 and (s.d or 0) >= 60 then
      out[#out + 1] = { name = name, m = m, s = s }
    end
  end
  return out
end

Session.AWARDS = {
  { key = "xp", title = L["MVP de l'XP"], glyph = "arrowup", fmt = function(s) return U.Compact(s.xp) .. " XP" end },
  { key = "k", title = L["Boucher"], glyph = "sword", fmt = function(s) return string.format(L["%s ennemis"], U.Num(s.k)) end },
  { key = "gi", title = L["Mécène"], glyph = "bag", fmt = function(s) return U.Money(s.gi) end },
  { key = "de", title = L["Chat noir"], glyph = "skull", fmt = function(s) return string.format(L["%d mort(s)"], s.de) end },
  { key = "it", title = L["Pilleur"], glyph = "star", fmt = function(s) return string.format(L["%s objet(s)"], U.Num(s.it)) end },
  { key = "d", title = L["Marathonien"], glyph = "clock", fmt = function(s) return U.Duration(s.d) end },
  { key = "q", title = L["Coursier"], glyph = "check", fmt = function(s) return string.format(L["%d quête(s)"], s.q) end },
  { key = "zc", title = L["Explorateur"], glyph = "pin", fmt = function(s) return string.format(L["%d zone(s)"], s.zc) end },
}

function Session:Awards()
  local tonight = self:Tonight()
  local out = {}
  for _, award in ipairs(self.AWARDS) do
    local winner, value
    for _, row in ipairs(tonight) do
      local v = tonumber(row.s[award.key]) or 0
      if v > 0 and (not value or v > value) then winner, value = row, v end
    end
    if winner then
      out[#out + 1] = { award = award, name = winner.name, m = winner.m, s = winner.s }
    end
  end
  return out, #tonight
end

function Session:ShareText(s)
  s = s or self:Current()
  local parts = {
    U.Duration(s.d),
    string.format("+%s XP", U.Num(s.xp)),
  }
  if (s.lv or 0) > 0 then parts[#parts + 1] = string.format(L["%d niveau(x)"], s.lv) end
  parts[#parts + 1] = string.format(L["%s ennemis"], U.Num(s.k))
  parts[#parts + 1] = string.format(L["%d mort(s)"], s.de)
  parts[#parts + 1] = U.MoneyPlain(s.g)
  local text = L["KEK — ma soirée : "] .. table.concat(parts, ", ")
  if s.b then text = text .. " · " .. L["meilleur butin : "] .. s.b end
  return text
end

function Session:Share()
  local channel = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or (IsInGuild() and "GUILD")
  if not channel then
    ns.Print(L["rejoins un groupe ou une guilde pour partager ton récap."])
    return
  end
  if ns.Comm:Locked() then
    ns.Print(L["le jeu bloque le chat des addons en donjon : partage ton récap une fois sorti."])
    return
  end
  SendChatMessage(self:ShareText(), channel)
end
