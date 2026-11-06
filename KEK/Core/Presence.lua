-- KEK — présence lue dans le jeu : liste d'amis, Battle.net, guilde et groupe.
-- Les messages de KEK ne passent pas en donjon, et l'« au revoir » d'un ami peut se perdre (plantage,
-- coupure, déconnexion depuis un donjon). Le jeu, lui, sait toujours qui est connecté. On s'en sert pour :
--   · passer un membre hors ligne dès que le jeu le dit ;
--   · le garder en ligne en donjon, même si KEK n'entend plus rien ;
--   · tenir son niveau et sa zone à jour quand ses messages ne passent pas.
local _, ns = ...
local U = ns.U

local Presence = ns:NewModule("Presence", 12)

local FRESH = 150   -- secondes : un « connecté » lu dans le jeu reste valable ce temps-là
local GRACE = 20    -- un message de KEK plus récent l'emporte sur une liste du jeu pas encore à jour
local POLL = 30     -- on redemande au jeu la liste d'amis et la guilde

Presence.game = {}    -- [nom] = { on, t, src } : dernier état lu dans le jeu
Presence.heard = {}   -- [nom] = GetTime() du dernier message de KEK reçu de ce membre
Presence.stats = { friend = 0, bnet = 0, guild = 0, group = 0 }

-- Un message de KEK vient d'arriver de ce membre.
function Presence:Heard(name)
  if name then self.heard[name] = GetTime() end
end

-- Le jeu dit que ce membre est connecté (lecture récente).
function Presence:Connected(name)
  local g = self.game[name]
  return g ~= nil and g.on and GetTime() - g.t < FRESH
end

-- Connecté d'après le jeu, mais KEK ne l'entend plus : messages coupés (donjon, champ de bataille).
function Presence:Silent(name)
  if not self:Connected(name) then return false end
  local heard = self.heard[name]
  return not heard or GetTime() - heard > FRESH
end

local function readable(v, kind)
  if v == nil or U.Secret(v) or type(v) ~= kind then return nil end
  if kind == "string" and v == "" then return nil end
  if kind == "number" and v <= 0 then return nil end
  return v
end

-- Ce que le jeu sait des membres de la bande : { [nom] = { on, src, level, zone } }.
function Presence:Collect()
  local out, members = {}, ns.db.members
  local stats = { friend = 0, bnet = 0, guild = 0, group = 0 }
  local function put(raw, second, on, src, level, zone)
    raw = readable(raw, "string")
    if not raw or U.Secret(on) or U.Secret(second) then return end
    local name = U.FullName(raw, readable(second, "string"))
    if not name or not members[name] or ns.Comm:IsOwnCharacter(name) then return end
    stats[src] = stats[src] + 1
    local cur = out[name]
    if cur and cur.on and not on then return end   -- une source qui le voit connecté l'emporte
    out[name] = {
      on = on and true or false, src = src,
      level = readable(level, "number") or (cur and cur.level),
      zone = readable(zone, "string") or (cur and cur.zone),
    }
  end

  -- amis du jeu
  local FL = C_FriendList
  if FL and FL.GetNumFriends and FL.GetFriendInfoByIndex then
    for i = 1, FL.GetNumFriends() or 0 do
      local f = FL.GetFriendInfoByIndex(i)
      if f then put(f.name, nil, f.connected, "friend", f.level, f.area) end
    end
  end

  -- Battle.net : on ne voit que le personnage joué. Un personnage déjà vu sur un compte qui joue
  -- maintenant un autre personnage (ou plus rien) est déconnecté.
  local BN = C_BattleNet
  if BNGetNumFriends and BN and BN.GetFriendNumGameAccounts and BN.GetFriendGameAccountInfo then
    local playing = {}
    pcall(function()
      local myRealm = U.Realm()
      for i = 1, (BNGetNumFriends()) or 0 do
        for j = 1, BN.GetFriendNumGameAccounts(i) or 0 do
          local g = BN.GetFriendGameAccountInfo(i, j)
          if g and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW")
            and (not WOW_PROJECT_ID or not g.wowProjectID or g.wowProjectID == WOW_PROJECT_ID) then
            local character = readable(g.characterName, "string")
            if not character then
              -- écran de chargement : le jeu ne dit pas encore quel personnage est joué
              if g.gameAccountID then playing[g.gameAccountID] = false end
            else
              local realm = (readable(g.realmName, "string") or ""):gsub("[%s%-]", "")
              if realm == "" then realm = myRealm end
              local raw = character .. "-" .. realm
              if g.gameAccountID then playing[g.gameAccountID] = U.FullName(raw) end
              put(raw, nil, true, "bnet", g.characterLevel, g.areaName)
            end
          end
        end
      end
    end)
    for name, id in pairs(ns.Comm.bnIds or {}) do
      local now = playing[id]
      if now ~= false and now ~= name then put(name, nil, false, "bnet") end
    end
  end

  -- guilde
  if IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
    for i = 1, (GetNumGuildMembers()) or 0 do
      local name, _, _, level, _, zone, _, _, online = GetGuildRosterInfo(i)
      put(name, nil, online, "guild", level, zone)
    end
  end

  -- groupe (le jeu indique aussi qui a perdu la connexion)
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  if n > 0 and UnitIsConnected then
    local raid = IsInRaid()
    for i = 1, n do
      local unit = raid and ("raid" .. i) or ("party" .. i)
      if UnitExists(unit) then
        local name, second = UnitName(unit)
        local zone = raid and GetRaidRosterInfo and select(7, GetRaidRosterInfo(i)) or nil
        put(name, second, UnitIsConnected(unit), "group", UnitLevel(unit), zone)
      end
    end
  end

  self.stats = stats
  return out
end

function Presence:Scan()
  if not ns.db then return end
  local now = GetTime()
  local ok, seen = pcall(self.Collect, self)
  if not ok then ns.Report(seen) return end
  local changed = false
  for name, g in pairs(seen) do
    self.game[name] = { on = g.on, t = now, src = g.src }
    local m = ns.db.members[name]
    local heard = self.heard[name]
    if g.on then
      -- revenu après une déconnexion vue par le jeu, alors que ses messages ne passent pas
      if heard and not ns.Store:IsOnline(name) then ns.Store:SetOnline(name, true) end
      -- le niveau ne fait que monter : une liste du jeu en retard ne le fait jamais redescendre
      if g.level and g.level > (m.level or 0) then
        m.level, m.xp = g.level, 0
        changed = true
      end
      -- la zone envoyée par KEK est plus précise (sous-zone) : celle du jeu sert quand KEK se tait
      if g.zone and g.zone ~= m.zone and g.zone ~= m.sub and (not heard or now - heard > FRESH) then
        m.zone, m.sub = g.zone, nil
        changed = true
      end
    elseif ns.Store:IsOnline(name) and not (heard and now - heard < GRACE) then
      ns.Store:SetOnline(name, false)
    end
  end
  if changed then ns:Fire("DATA", "members") end
end

function Presence:RequestScan()
  ns:Debounce("presence-scan", 1, function() self:Scan() end)
end

-- Demande au jeu des listes d'amis et de guilde à jour (il répond par FRIENDLIST_UPDATE, GUILD_ROSTER_UPDATE).
function Presence:Poll()
  if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
  if IsInGuild() then
    local roster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
    if roster then pcall(roster) end
  end
  self:RequestScan()
end

function Presence:OnLogin()
  local scan = function() self:RequestScan() end
  for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
    "BN_FRIEND_ACCOUNT_OFFLINE", "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION",
    "PLAYER_ENTERING_WORLD" }) do
    ns:RegisterEvent(event, scan)   -- un événement absent de ce client est simplement ignoré
  end
  C_Timer.NewTicker(POLL, function() self:Poll() end)
  C_Timer.After(6, function() self:Poll() end)
end
