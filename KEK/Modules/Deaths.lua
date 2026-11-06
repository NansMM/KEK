-- KEK — morts : circonstances, Hall of Shame, titres honorifiques.
--
-- WoW Forever ferme le journal de combat aux addons (s'y abonner fait bloquer l'addon par le jeu).
-- KEK reconstitue donc les circonstances avec ce qui reste permis : chute en cours, jauge de
-- respiration ou d'épuisement, combat en cours, et la créature que l'on combattait (sa cible).
local _, ns = ...
local L, U = ns.L, ns.U

local Deaths = ns:NewModule("Deaths", 41)

local KEEP = 40     -- morts conservées par personnage
local SHARE = 15    -- morts échangées lors d'une synchronisation
local FALL_WINDOW = 2.5

local ENV = {
  FALLING = L["Chute"], DROWNING = L["Noyade"], FATIGUE = L["Épuisement"],
  FIRE = L["Feu"], LAVA = L["Lave"], SLIME = L["Vase"],
}

Deaths.EPITAPHS = {
  L["« Ça passe », paraît-il."],
  L["Parti comme on aimerait tous partir : en tirant un pack de trop."],
  L["Le guérisseur des esprits commence à connaître ce visage."],
  L["Le cimetière, c'est par là. Le chemin est connu."],
  L["Mort au champ d'honneur. Enfin, dans un champ."],
  L["Une minute de silence. Bon, trente secondes."],
  L["Il y avait pourtant une potion dans le sac."],
  L["Les murlocs raconteront cette histoire pendant des générations."],
  L["Un pas en arrière aurait suffi."],
  L["Ce n'était pas l'aggro, c'était le destin."],
  L["La réparation sera salée."],
  L["Courir vers le soigneur, c'était l'idée. L'exécution, moins."],
}

Deaths.mirror = {}

local function list(name)
  local all = ns.db.deaths
  local l = all[name]
  if not l then l = {}; all[name] = l end
  return l
end

-- ------------------------------------------------------------------ capture
-- Nom lisible d'une unité, ou nil si le jeu le garde secret (créatures en donjon).
local function readableName(unit)
  if not UnitExists or not UnitExists(unit) then return nil end
  local name = UnitName(unit)
  if name == nil or U.Secret(name) or name == "" then return nil end
  return name
end

-- La créature que l'on combattait : la cible hostile, ou la cible de la cible.
function Deaths:Opponent()
  for _, unit in ipairs({ "target", "targettarget" }) do
    local hostile = UnitCanAttack and UnitCanAttack("player", unit)
    if hostile and not U.Secret(hostile) and (not UnitIsPlayer or not UnitIsPlayer(unit) or unit == "target") then
      local name = readableName(unit)
      if name and name ~= UnitName("player") then return name end
    end
  end
end

function Deaths:MirrorExpired(timer)
  if not self.mirror[timer] then return false end
  if GetMirrorTimerProgress then
    local ok, left = pcall(GetMirrorTimerProgress, timer)
    if ok and type(left) == "number" and not U.Secret(left) then return left <= 0 end
  end
  return true
end

function Deaths:OnDeath()
  if U.InPvP() then return end   -- les morts en champ de bataille ou en arène ne comptent pas
  local now = GetTime()
  local rec = {
    l = UnitLevel("player"), z = GetRealZoneText(), sz = GetSubZoneText(),
    ins = IsInInstance() and true or nil, ep = math.random(#self.EPITAPHS),
  }
  if rec.sz == "" or rec.sz == rec.z then rec.sz = nil end
  if self.fallAt and now - self.fallAt <= FALL_WINDOW then
    rec.e = "FALLING"
  elseif self:MirrorExpired("BREATH") then
    rec.e = "DROWNING"
  elseif self:MirrorExpired("EXHAUSTION") then
    rec.e = "FATIGUE"
  end
  local inCombat = self.combat or (self.combatEnd and now - self.combatEnd < 3)
  if inCombat then rec.cb = true end
  if not rec.e then rec.by = self:Opponent() end
  self.fallAt = nil
  local me = ns.Store:Me()
  me.deaths = (me.deaths or 0) + 1
  ns.Alerts:Emit("death", rec)
  ns.Sync:Dirty(3)
end

-- Surveille les chutes (vérification légère, dix fois par seconde).
function Deaths:WatchFalls()
  if not IsFalling then return end
  local watcher = CreateFrame("Frame")
  local elapsed = 0
  watcher:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    if IsFalling() then self.fallAt = GetTime() end
  end)
end

-- ------------------------------------------------------------------ stockage
function Deaths:Store(who, e)
  local l = list(who)
  for _, d in ipairs(l) do
    if d.t == e.t then return end
  end
  local copy = U.Copy(e)
  copy.w, copy.k = nil, nil
  l[#l + 1] = copy
  table.sort(l, function(a, b) return (a.t or 0) < (b.t or 0) end)
  while #l > KEEP do table.remove(l, 1) end
end

function Deaths:HashFor(name)
  local l = ns.db.deaths[name]
  if not l or #l == 0 then return "0" end
  local parts = {}
  for i = math.max(1, #l - SHARE + 1), #l do parts[#parts + 1] = tostring(l[i].t) end
  return U.Hash(table.concat(parts, ","))
end

function Deaths:OnLogin()
  self:WatchFalls()
  ns:RegisterEvent("MIRROR_TIMER_START", function(_, timer)
    if type(timer) == "string" and not U.Secret(timer) then self.mirror[timer] = true end
  end)
  ns:RegisterEvent("MIRROR_TIMER_STOP", function(_, timer)
    if type(timer) == "string" and not U.Secret(timer) then
      -- l'arrêt suit parfois la mort de peu : on garde l'info une seconde de plus
      C_Timer.After(1, function() self.mirror[timer] = nil end)
    end
  end)
  ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() self.combat = true end)
  ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() self.combat, self.combatEnd = false, GetTime() end)
  ns:RegisterEvent("PLAYER_DEAD", function() self:OnDeath() end)
  ns:On("EVENT", function(who, e)
    if e.k == "death" then self:Store(who, e) end
  end)

  ns.Sync:Dataset("d", {
    prio = 3,
    ownHash = function() return self:HashFor(ns.me) end,
    knownHash = function(sender) return self:HashFor(sender) end,
    build = function()
      local l, out = list(ns.me), {}
      for i = math.max(1, #l - SHARE + 1), #l do out[#out + 1] = l[i] end
      return out
    end,
    apply = function(sender, payload)
      if type(payload) ~= "table" then return end
      for _, d in ipairs(payload) do
        if type(d) == "table" and d.t then self:Store(sender, d) end
      end
    end,
  })
end

-- ------------------------------------------------------------------ lecture
function Deaths:KillerName(e)
  if e.e then return ENV[e.e] or e.e end
  return e.by
end

function Deaths:Cause(e)
  local killer = self:KillerName(e)
  if not killer then
    if e.cb then return L["Mort au combat"] end
    return L["Cause inconnue"]
  end
  if e.e then
    if e.a and e.a > 0 then return string.format(L["%s · %s dégâts"], killer, U.Num(e.a)) end
    return killer
  end
  local text = string.format(L["Tué par %s"], killer)
  if e.sp then text = text .. " · " .. e.sp end
  if e.a and e.a > 0 then
    text = text .. " · " .. U.Num(e.a)
    if e.o then text = text .. string.format(" (+%s)", U.Num(e.o)) end
  end
  return text
end

function Deaths:Epitaph(e)
  return self.EPITAPHS[e.ep or 1] or self.EPITAPHS[1]
end

function Deaths:Recent(limit)
  local out = {}
  for who, l in pairs(ns.db.deaths) do
    if ns.db.members[who] then
      for _, d in ipairs(l) do out[#out + 1] = { w = who, d = d } end
    end
  end
  table.sort(out, function(a, b) return (a.d.t or 0) > (b.d.t or 0) end)
  if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
  return out
end

function Deaths:Leaderboard()
  local out = {}
  for name, m in pairs(ns.db.members) do
    local count = math.max(m.deaths or 0, #(ns.db.deaths[name] or {}))
    out[#out + 1] = { name = name, m = m, count = count }
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return (a.m.level or 0) < (b.m.level or 0)
  end)
  return out
end

-- Titres honorifiques calculés sur l'historique des morts.
function Deaths:Titles()
  local stats = {}
  local function s(name)
    local t = stats[name]
    if not t then t = { env = {}, killers = {}, zones = {}, dungeon = 0 }; stats[name] = t end
    return t
  end
  for name, l in pairs(ns.db.deaths) do
    if ns.db.members[name] then
      for _, d in ipairs(l) do
        local t = s(name)
        if d.e then t.env[d.e] = (t.env[d.e] or 0) + 1 end
        if d.by and not d.e then t.killers[d.by] = (t.killers[d.by] or 0) + 1 end
        if d.z then t.zones[d.z] = (t.zones[d.z] or 0) + 1 end
        if d.ins then t.dungeon = t.dungeon + 1 end
      end
    end
  end

  local titles = {}
  local function best(fn)
    local winner, value, extra
    for name, t in pairs(stats) do
      local v, x = fn(t)
      if v and v > 0 and (not value or v > value) then winner, value, extra = name, v, x end
    end
    return winner, value, extra
  end
  local function add(title, glyph, desc, winner, value)
    if winner then titles[#titles + 1] = { title = title, glyph = glyph, desc = desc, name = winner, value = value } end
  end

  local board = self:Leaderboard()
  if board[1] and board[1].count > 0 then
    add(L["Paillasson"], "skull", string.format(L["%d morts au compteur"], board[1].count), board[1].name, board[1].count)
  end
  local w, v = best(function(t) return t.env.FALLING end)
  add(L["Kamikaze"], "arrowup", string.format(L["%d chute(s) mortelle(s)"], v or 0), w, v)
  w, v = best(function(t) return t.env.DROWNING end)
  add(L["Poisson rouge"], "clock", string.format(L["%d noyade(s)"], v or 0), w, v)
  w, v = best(function(t) return t.dungeon end)
  add(L["Spéléologue"], "flame", string.format(L["%d mort(s) en donjon"], v or 0), w, v)
  local x
  w, v, x = best(function(t)
    local top, by = 0, nil
    for killer, n in pairs(t.killers) do if n > top then top, by = n, killer end end
    if top >= 2 then return top, by end
  end)
  add(L["Récidiviste"], "sword", string.format(L["tué %d fois par %s"], v or 0, x or "?"), w, v)
  w, v, x = best(function(t)
    local top, at = 0, nil
    for zone, n in pairs(t.zones) do if n > top then top, at = n, zone end end
    if top >= 3 then return top, at end
  end)
  add(L["Habitué"], "star", string.format(L["%d morts à %s"], v or 0, x or "?"), w, v)
  w, v = best(function(t) return U.Count(t.zones) end)
  if v and v >= 3 then add(L["Touriste"], "pin", string.format(L["mort dans %d zones"], v), w, v) end

  -- l'immortel : le plus haut niveau sans aucune mort
  local immortal, lvl
  for _, row in ipairs(board) do
    if row.count == 0 and (row.m.level or 0) >= 10 and (not lvl or row.m.level > lvl) then
      immortal, lvl = row.name, row.m.level
    end
  end
  add(L["Immortel"], "heart", string.format(L["niveau %d, zéro mort"], lvl or 0), immortal, lvl)
  return titles
end
