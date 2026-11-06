-- KEK — course au 60 : temps de jeu, courbe de progression, estimation d'arrivée.
local _, ns = ...
local U = ns.U

local Race = ns:NewModule("Race", 43)

local MAX_POINTS = 160
local SAMPLE_MINUTES = 20

-- ------------------------------------------------------------------ temps de jeu (/played silencieux)
-- Les fenêtres de chat ne reçoivent pas la réponse pendant un court instant : rien ne s'affiche,
-- et aucune fonction de Blizzard n'est remplacée (ce qui pourrait « contaminer » l'interface).
function Race:RequestPlayed()
  if self.muted then return end
  local muted = {}
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local frame = _G["ChatFrame" .. i]
    if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
      frame:UnregisterEvent("TIME_PLAYED_MSG")
      muted[#muted + 1] = frame
    end
  end
  self.muted = muted
  RequestTimePlayed()
  C_Timer.After(6, function() self:Unmute() end)
end

function Race:Unmute()
  local muted = self.muted
  if not muted then return end
  self.muted = nil
  for _, frame in ipairs(muted) do frame:RegisterEvent("TIME_PLAYED_MSG") end
end

function Race:Played()
  if not self.base then return nil end
  return self.base + (GetTime() - self.baseAt)
end

-- ------------------------------------------------------------------ progression
-- Retourne le niveau fractionnaire et l'XP cumulée (en unités de la table classique).
function Race:Progress()
  local level = UnitLevel("player")
  if level >= ns.MAX_LEVEL then return ns.MAX_LEVEL, U.CUMXP[ns.MAX_LEVEL] end
  local max = UnitXPMax("player") or 0
  local frac = max > 0 and (UnitXP("player") or 0) / max or 0
  return level + frac, U.CUMXP[level] + frac * (U.XP[level] or 0)
end

function Race:Points(name)
  local p = ns.db.prog[name]
  if not p then
    p = { pts = {} }
    ns.db.prog[name] = p
  end
  return p
end

function Race:Record(force)
  local played = self:Played()
  if not played then return end
  local level, cum = self:Progress()
  local mine = self:Points(ns.me)
  local pts = mine.pts
  local last = pts[#pts]
  local minutes = math.floor(played / 60)
  if not force and last and (minutes - last.p) < SAMPLE_MINUTES and (level - last.l) < 0.5 then return end
  if last and last.p == minutes then table.remove(pts) end
  pts[#pts + 1] = { p = minutes, l = U.Round(level, 2), x = math.floor(cum), t = ns.Now() }
  -- au-delà de la limite, on éclaircit la moitié la plus ancienne
  while #pts > MAX_POINTS do
    for i = 2, math.floor(#pts / 2), 2 do table.remove(pts, i) end
  end
  mine.h = nil
  self:UpdateEta()
end

function Race:UpdateEta()
  local played = self:Played()
  local me = ns.Store:Me()
  if played then me.played = math.floor(played) end
  local level, cum = self:Progress()
  if level >= ns.MAX_LEVEL then
    me.eta, me.etaDate = 0, nil
    return
  end
  local pts = self:Points(ns.me).pts
  local nowP = played and played / 60
  if not nowP or #pts == 0 then me.eta, me.etaDate = nil, nil; return end
  -- rythme récent : XP gagnée sur les ~4 dernières heures de jeu
  local ref
  for i = #pts, 1, -1 do
    ref = pts[i]
    if nowP - ref.p >= 240 then break end
  end
  local span = nowP - ref.p
  if span < 30 or cum <= ref.x then me.eta, me.etaDate = nil, nil; return end
  local perHour = (cum - ref.x) / (span / 60)
  local hours = (U.CUMXP[ns.MAX_LEVEL] - cum) / perHour
  me.eta = U.Round(hours, 1)
  -- date réelle : temps de jeu par jour sur la dernière semaine
  local first
  for i = #pts, 1, -1 do
    if ns.Now() - pts[i].t <= 7 * 86400 then first = pts[i] else break end
  end
  if first and ns.Now() - first.t >= 86400 then
    local hoursPerDay = ((nowP - first.p) / 60) / ((ns.Now() - first.t) / 86400)
    if hoursPerDay > 0.1 then
      me.etaDate = ns.Now() + math.floor(hours / hoursPerDay * 86400)
    end
  else
    me.etaDate = nil
  end
end

-- ------------------------------------------------------------------ partage
function Race:Encode(pts)
  local parts = {}
  for i, pt in ipairs(pts) do parts[i] = pt.p .. ":" .. pt.l end
  return table.concat(parts, ",")
end

function Race:Decode(s)
  local pts = {}
  if type(s) ~= "string" then return pts end
  for p, l in s:gmatch("(%d+):([%d%.]+)") do
    pts[#pts + 1] = { p = tonumber(p), l = tonumber(l) }
  end
  return pts
end

function Race:OwnHash()
  local mine = self:Points(ns.me)
  if not mine.h then mine.h = U.Hash(self:Encode(mine.pts)) end
  return mine.h
end

-- Série affichable pour un membre : liste de { p = minutes, l = niveau }.
function Race:Series(name)
  local p = ns.db.prog[name]
  local pts = p and p.pts or {}
  if name == ns.me then
    local played = self:Played()
    if played then
      local level = self:Progress()
      local out = {}
      for i, pt in ipairs(pts) do out[i] = pt end
      out[#out + 1] = { p = played / 60, l = level }
      return out
    end
  end
  return pts
end

function Race:OnLogin()
  ns:RegisterEvent("TIME_PLAYED_MSG", function(_, total)
    if self.muted then C_Timer.After(0.2, function() self:Unmute() end) end
    self.base, self.baseAt = tonumber(total) or 0, GetTime()
    self:Record(false)
    self:UpdateEta()
    ns:Fire("DATA", "prog")
  end)
  C_Timer.After(7, function() self:RequestPlayed() end)
  ns:RegisterEvent("PLAYER_LEVEL_UP", function()
    C_Timer.After(1.5, function() self:Record(true); ns.Sync:Push("p"); ns:Fire("DATA", "prog") end)
  end)
  ns:RegisterEvent("PLAYER_LOGOUT", function() self:Record(true) end)
  C_Timer.NewTicker(60, function()
    self:Record(false)
    self:UpdateEta()
  end)

  ns.Sync:Dataset("p", {
    prio = 3,
    ownHash = function() return self:OwnHash() end,
    knownHash = function(sender) return ns.Sync:StoredHash(sender, "p") end,
    build = function() return self:Encode(self:Points(ns.me).pts) end,
    apply = function(sender, payload, hash)
      ns.db.prog[sender] = { pts = self:Decode(payload) }
      ns.Sync:StoreHash(sender, "p", hash)
    end,
  })
end
