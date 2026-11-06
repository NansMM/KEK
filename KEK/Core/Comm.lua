-- KEK — transport des messages entre les membres de la bande.
--
-- WoW Classic interdit aux addons d'écrire sur les canaux personnalisés (le jeu bloque l'addon).
-- KEK passe donc par les seuls chemins autorisés :
--   · la guilde et le groupe, quand des membres de la bande s'y trouvent ;
--   · des chuchotements d'addon, invisibles dans le chat, vers chaque autre membre en ligne.
-- La bande est reconnue grâce à une étiquette tirée du code secret : un message d'une autre bande est ignoré.
-- Pour trouver les membres, KEK sonde la guilde, le groupe, les membres déjà connus et la liste d'amis.
local _, ns = ...
local L, U = ns.L, ns.U

local Comm = ns:NewModule("Comm", 10)

local PREFIX = "KEK"
local CHUNK = 245          -- 255 octets max par message, moins l'en-tête (1 marqueur + 2 id)
local BURST, RATE = 8, 1.0 -- jetons : rafale max et recharge par seconde (limite du jeu : ~1 message/s par préfixe)
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local PING_TTL = 20        -- un « joueur introuvable » reçu dans ce délai est attribué à KEK
local SEEN_TTL = 120       -- mémoire anti-doublon (un même message peut arriver par deux chemins)
local MAX_FRIEND_PINGS = 60
local FRIEND_REPING = 180  -- secondes avant de sonder de nouveau un ami qui n'a pas (encore) répondu
local ACCEPT = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }

Comm.mode = "offline"      -- offline (démarrage) | ready | none (ni code ni guilde)
Comm.queue = { {}, {}, {} } -- 1 urgent, 2 normal, 3 volumineux ou facultatif
Comm.tokens = BURST
Comm.buffers = {}
Comm.seen = {}
Comm.pinged = {}           -- nom replié -> heure du dernier chuchotement
Comm.discovered = {}       -- noms déjà sondés pendant cette session
Comm.manual = {}           -- ajouts manuels en attente de réponse
Comm.friendPings = {}      -- ami -> heure du dernier sondage
Comm.bnIds = {}            -- perso d'un ami Battle.net -> identifiant de compte de jeu
Comm.pingLog = {}          -- perso sondé -> { t, state = sent | ok | notfound | otherband }
Comm.stats = { sent = {}, refused = 0, recv = 0, noBand = 0, otherBand = 0, oldVersion = 0 }
Comm.failures = 0
Comm.msgId = 0

local function idString(n)
  local a, b = math.floor(n / 36) % 36, n % 36
  return B36:sub(a + 1, a + 1) .. B36:sub(b + 1, b + 1)
end

local function key(name)
  return U.Fold(name or "")
end

local SendAddon = function(...)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then return C_ChatInfo.SendAddonMessage(...) end
  return SendAddonMessage(...)
end

-- Codes de retour de SendAddonMessage (interface récente : Enum.SendAddonMessageResult).
local RESULT = (Enum and Enum.SendAddonMessageResult) or {}
local THROTTLED = { [RESULT.AddonMessageThrottle or 3] = true, [RESULT.ChannelThrottle or 8] = true }
local LOCKDOWN = RESULT.AddOnMessageLockdown
local OFFLINE = RESULT.TargetOffline

-- « Aucun joueur nommé "%s" n'est connecté. » -> motif de capture, selon la langue du client.
local notFoundPattern
local function NotFoundPattern()
  if notFoundPattern == nil then
    local s = ERR_CHAT_PLAYER_NOT_FOUND_S
    if type(s) == "string" and s:find("%s", 1, true) then
      s = s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
      notFoundPattern = "^" .. (s:gsub("%%s", "(.+)", 1)) .. "$"
    else
      notFoundPattern = false
    end
  end
  return notFoundPattern
end

function Comm:OnInit()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
  end
  self.msgId = math.random(0, 1295)
  ns:RegisterEvent("CHAT_MSG_ADDON", function(_, ...) self:OnMessage(...) end)
  ns:RegisterEvent("BN_CHAT_MSG_ADDON", function(_, ...) self:OnBNMessage(...) end)
  -- un membre hors ligne sondé par KEK ne doit pas afficher « joueur introuvable » dans le chat
  U.AddMessageFilter("CHAT_MSG_SYSTEM", function(_, _, msg) return Comm:FilterSystem(msg) end)
end

-- WoW Forever interdit aux addons de communiquer depuis un donjon ou un champ de bataille.
-- Pendant ce temps, les messages attendent dans la file et partent à la sortie.
function Comm:Locked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and not U.Secret(locked) then return locked and true or false end
  end
  if not U.RESTRICTED then return false end
  local inInstance, kind = IsInInstance()
  return inInstance and kind ~= "none" and true or false
end

function Comm:OnLogin()
  self.lastPump = GetTime()
  C_Timer.NewTicker(0.2, function() self:Pump() end)
  C_Timer.NewTicker(30, function() self:Clean() end)
  C_Timer.NewTicker(60, function() self:DiscoverFriends() end)
  C_Timer.After(5, function() self:Connect() end)
  ns:RegisterEvent("PLAYER_GUILD_UPDATE", function()
    ns:Debounce("comm-guild", 3, function() self:Connect() end)
  end)
  ns:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    ns:Debounce("comm-group", 2, function() self:OnGroupChanged() end)
  end)
  local friends = function() ns:Debounce("comm-friends", 4, function() self:DiscoverFriends() end) end
  ns:RegisterEvent("FRIENDLIST_UPDATE", friends)
  ns:RegisterEvent("BN_FRIEND_INFO_CHANGED", friends)
  ns:RegisterEvent("PLAYER_LOGOUT", function() self:SendDirect("B", {}) end)
end

-- ------------------------------------------------------------------ identité de la bande
function Comm:Code()
  return ((ns.db.band.code or ""):lower():gsub("[^%w]", ""))
end

-- Étiquette jointe à chaque message : dérivée du code (« c… ») ou « g » pour une bande de guilde.
function Comm:ComputeTag()
  local code = self:Code()
  if code ~= "" then return "c" .. U.Hash("KEK:" .. code):sub(-6) end
  if IsInGuild() then return "g" end
  return nil
end

function Comm:IsGuildBand()
  return self.tag == "g"
end

function Comm:IsReady()
  return self.mode == "ready"
end

-- (Re)calcule la bande : au démarrage, après un changement de code ou de guilde.
function Comm:Connect()
  local tag = self:ComputeTag()
  if tag == self.tag and self.mode ~= "offline" then return end
  if self.mode ~= "offline" and self.tag then ns.Store:ClearPresence() end
  self.tag = tag
  wipe(self.discovered)
  wipe(self.friendPings)
  self.groupKey = nil
  self.mode = tag and "ready" or "none"
  ns:Fire("COMM_STATUS", self.mode)
  if tag then
    ns:Fire("COMM_READY")
    self:Discover()
  end
end

-- Changement de code : on prévient l'ancienne bande et on repart de zéro.
function Comm:SetCode(code)
  if self.tag then self:SendDirect("B", {}) end
  ns.db.band.code = ((code or ""):lower():gsub("[^%w]", ""))
  ns.db.band.mode = nil
  for _, queue in ipairs(self.queue) do wipe(queue) end
  ns.Store:ClearPresence()
  self.tag = nil
  self.mode = "offline"
  self:Connect()
end

function Comm:StatusText()
  if self.mode == "ready" then
    if self:IsGuildBand() then return L["Via la guilde"], true end
    return L["Bande privée"], true
  end
  if self.mode == "none" then return L["Hors ligne — aucun code"], false end
  return L["Démarrage…"], false
end

-- ------------------------------------------------------------------ découverte des membres
function Comm:IsOwnCharacter(name)
  return name == ns.me or (ns.db.inv and ns.db.inv[name] ~= nil)
end

-- Sonde un personnage par un chuchotement d'addon « bonjour ». S'il a KEK et le même code, il répond.
function Comm:Ping(name, prio, force)
  if not self.tag or self:IsGuildBand() or not name then return end
  if self:IsOwnCharacter(name) then return end
  if self.discovered[name] and not force then return end
  self.discovered[name] = true
  local log = self.pingLog[name]
  if not log or log.state ~= "ok" then self.pingLog[name] = { t = GetTime(), state = "sent" } end
  self:SendTo("H", self:Hello(), prio or 1, "WHISPER", name)
end

-- « Bonjour » : r = 1 quand on revient d'un donjon (déjà connecté, pas de notification).
function Comm:Hello()
  return { v = ns.VERSION, r = self.returning and 1 or nil }
end

function Comm:Discover(returning)
  if not self.tag then return end
  self.returning = returning
  self:DoDiscover()
  self.returning = nil
end

function Comm:DoDiscover()
  local hello = self:Hello()
  if IsInGuild() then self:SendTo("H", hello, 1, "GUILD") end
  if self:IsGuildBand() then return end
  local group = self:GroupChannel()
  if group then
    self.groupKey = self:GroupKey()
    self:SendTo("H", hello, 1, group)
  end
  -- membres déjà connus, les plus récents d'abord
  local known = {}
  for name, m in pairs(ns.db.members) do
    if not self:IsOwnCharacter(name) then known[#known + 1] = { name, m.seen or 0 } end
  end
  table.sort(known, function(a, b) return a[2] > b[2] end)
  for _, entry in ipairs(known) do self:Ping(entry[1], 1) end
  self:DiscoverFriends()
end

-- Amis en ligne (liste d'amis du personnage et amis Battle.net sur le même royaume).
function Comm:OnlineFriends()
  local list, seen = {}, {}
  local function add(name)
    local full = U.FullName(name)
    if full and not seen[full] then
      seen[full] = true
      list[#list + 1] = full
    end
  end
  local FL = C_FriendList
  if FL and FL.GetNumFriends and FL.GetFriendInfoByIndex then
    for i = 1, FL.GetNumFriends() or 0 do
      local info = FL.GetFriendInfoByIndex(i)
      if info and info.connected and info.name then add(info.name) end
    end
  elseif GetNumFriends and GetFriendInfo then
    for i = 1, GetNumFriends() or 0 do
      local name, _, _, _, connected = GetFriendInfo(i)
      if connected and name then add(name) end
    end
  end
  local BN = C_BattleNet
  if BNGetNumFriends and BN and BN.GetFriendNumGameAccounts and BN.GetFriendGameAccountInfo then
    pcall(function()
      local myRealm = U.Realm()
      for i = 1, (BNGetNumFriends()) or 0 do
        for j = 1, BN.GetFriendNumGameAccounts(i) or 0 do
          local g = BN.GetFriendGameAccountInfo(i, j)
          if g and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW") and g.characterName and g.characterName ~= ""
            and (not WOW_PROJECT_ID or not g.wowProjectID or g.wowProjectID == WOW_PROJECT_ID) then
            local realm = (g.realmName or ""):gsub("[%s%-]", "")
            if realm == "" then realm = myRealm end
            add(g.characterName .. "-" .. realm)
            if g.gameAccountID then self.bnIds[U.FullName(g.characterName .. "-" .. realm)] = g.gameAccountID end
          end
        end
      end
    end)
  end
  return list
end

-- Les amis en ligne sont sondés à la connexion, puis de nouveau toutes les 3 minutes tant qu'ils
-- ne répondent pas : un ami qui entre le code après toi te trouve donc vite.
function Comm:DiscoverFriends()
  if not self.tag or self:IsGuildBand() then return end
  local now, n = GetTime(), 0
  for _, name in ipairs(self:OnlineFriends()) do
    if not ns.Store:IsOnline(name) and not self:IsOwnCharacter(name) then
      local last = self.friendPings[name]
      if not last and self.discovered[name] then
        self.friendPings[name] = now               -- déjà sondé en tant que membre connu
      elseif not last or now - last > FRIEND_REPING then
        n = n + 1
        if n > MAX_FRIEND_PINGS then break end
        self.friendPings[name] = now
        self:Ping(name, 3, true)
      end
    end
  end
end

-- Ajout manuel : « mon ami joue Gromgar ». KEK le sonde et dit ce qu'il en est.
function Comm:AddPeer(input)
  local name = (input or ""):match("^%s*(.-)%s*$")
  if not name or name == "" then return false end
  name = name:gsub("^%l", string.upper)
  if not self.tag or self:IsGuildBand() then
    ns.Print(L["choisis d'abord un code de bande : sans code, KEK passe par ta guilde."])
    return false
  end
  if U.SURNAMES then
    name = name:gsub("(%s)(%l)", function(sp, c) return sp .. c:upper() end)
    if not name:find("[%s%-]") then
      ns.Print(string.format(L["sur WoW Forever, indique aussi son nom de famille : « %s Nom »."], name))
      return false
    end
  end
  local full = U.FullName(name)
  if self:IsOwnCharacter(full) then return false end
  local k = key(full)
  self.manual[k] = { name = full, t = GetTime() }
  self:Ping(full, 1, true)
  ns.Print(string.format(L["recherche de %s…"], U.Short(full)))
  C_Timer.After(12, function()
    local pending = self.manual[k]
    if pending and pending.name == full then
      self.manual[k] = nil
      ns.Print(string.format(L["pas de réponse de %s : vérifie qu'il a installé KEK et qu'il utilise le code « %s »."], U.Short(full), self:Code()))
    end
  end)
  return true
end

-- ------------------------------------------------------------------ groupe
local HOME, INSTANCE = LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE

function Comm:GroupChannel()
  if HOME and INSTANCE and IsInGroup(INSTANCE) and not IsInGroup(HOME) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

function Comm:GroupNames()
  local list = {}
  local raid = IsInRaid()
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  for i = 1, n do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    local name, realm = UnitName(unit)
    if name and name ~= "" and name ~= UNKNOWNOBJECT then
      list[#list + 1] = U.FullName(name, realm ~= "" and realm or nil)
    end
  end
  return list
end

function Comm:GroupKey()
  local names = self:GroupNames()
  table.sort(names)
  return table.concat(names, ",")
end

function Comm:OnGroupChanged()
  if not self.tag or self:IsGuildBand() then return end
  local dist = self:GroupChannel()
  if not dist then self.groupKey = nil; return end
  local k = self:GroupKey()
  if k == self.groupKey then return end
  self.groupKey = k
  for _, name in ipairs(self:GroupNames()) do
    if name ~= ns.me and not ns.Store:IsOnline(name) then
      self:SendTo("H", { v = ns.VERSION }, 1, dist)
      return
    end
  end
end

-- ------------------------------------------------------------------ envoi
-- Chemins qui atteignent tous les membres en ligne avec le moins de messages possible.
function Comm:Routes()
  if self:IsGuildBand() then return IsInGuild() and { { "GUILD" } } or {} end
  local routes = {}
  local guild = IsInGuild() and GetGuildInfo("player")
  local group = self:GroupChannel()
  local inGroup = {}
  if group then
    for _, name in ipairs(self:GroupNames()) do inGroup[name] = true end
  end
  local useGuild, useGroup, whispers = false, false, {}
  for name in pairs(ns.Store.online) do
    local m = ns.db.members[name]
    if m and name ~= ns.me then
      if group and inGroup[name] then
        useGroup = true
      elseif guild and m.guild == guild then
        useGuild = true
      else
        whispers[#whispers + 1] = name
      end
    end
  end
  table.sort(whispers)
  if useGroup then routes[#routes + 1] = { group } end
  if useGuild then routes[#routes + 1] = { "GUILD" } end
  for _, name in ipairs(whispers) do routes[#routes + 1] = { "WHISPER", name } end
  return routes
end

local function split(payload, id)
  local parts, n = {}, #payload
  if n <= CHUNK then
    parts[1] = "!" .. id .. payload
    return parts
  end
  local pos = 1
  while pos <= n do
    local marker
    if pos == 1 then marker = "[" elseif pos + CHUNK > n then marker = "]" else marker = "=" end
    parts[#parts + 1] = marker .. id .. payload:sub(pos, pos + CHUNK - 1)
    pos = pos + CHUNK
  end
  return parts
end

function Comm:Encode(kind, data, to)
  self.msgId = (self.msgId + 1) % 1296
  local payload = ns.Ser.Encode({ k = kind, d = data, v = ns.PROTO, to = to, b = self.tag })
  return split(payload, idString(self.msgId))
end

-- Envoi par un chemin précis (dist = GUILD, PARTY, RAID, INSTANCE_CHAT ou WHISPER + nom).
function Comm:SendTo(kind, data, prio, dist, name)
  if not self.tag then return end
  local queue = self.queue[prio or 2]
  for _, part in ipairs(self:Encode(kind, data, dist == "WHISPER" and name or nil)) do
    queue[#queue + 1] = { text = part, dist = dist, to = name }
  end
end

-- Envoi à toute la bande, ou à un seul membre (to).
function Comm:Send(kind, data, prio, to)
  if not self:IsReady() then return end
  if to and self:IsGuildBand() then
    -- bande de guilde : tout passe par la guilde, le destinataire est indiqué dans le message
    local queue = self.queue[prio or 2]
    for _, part in ipairs(self:Encode(kind, data, to)) do queue[#queue + 1] = { text = part, dist = "GUILD" } end
    return
  elseif to then
    self:SendTo(kind, data, prio, "WHISPER", to)
    return
  end
  local routes = self:Routes()
  if #routes == 0 then return end
  local parts = self:Encode(kind, data)
  local queue = self.queue[prio or 2]
  for _, route in ipairs(routes) do
    for _, part in ipairs(parts) do
      queue[#queue + 1] = { text = part, dist = route[1], to = route[2] }
    end
  end
end

-- Envoi immédiat d'un petit message (déconnexion, changement de code) sans passer par la file.
function Comm:SendDirect(kind, data)
  if not self:IsReady() or self:Locked() then return end
  local parts = self:Encode(kind, data)
  if #parts ~= 1 then return end
  for i, route in ipairs(self:Routes()) do
    if i > 12 then break end
    self:RawSend({ text = parts[1], dist = route[1], to = route[2] })
  end
end

function Comm:WhisperTarget(full)
  if U.RealmOf(full) == U.Realm() then return U.Short(full) end
  return full
end

-- Retourne ok, réessayer.
function Comm:RawSend(item)
  local dist, target = item.dist, nil
  if dist == "WHISPER" then
    target = self:WhisperTarget(item.to)
    self.pinged[key(item.to)] = GetTime()
    self.pinged[key(target)] = GetTime()
  elseif dist == "GUILD" then
    if not IsInGuild() then return true end           -- chemin disparu : message abandonné
  elseif dist ~= self:GroupChannel() then
    return true
  end
  local ok, res = pcall(SendAddon, PREFIX, item.text, dist, target)
  if not ok then self.stats.refused = self.stats.refused + 1; return false end
  if res == nil or res == true or res == 0 then
    self.stats.sent[dist] = (self.stats.sent[dist] or 0) + 1
    return true
  end
  self.stats.refused = self.stats.refused + 1
  if THROTTLED[res] then return false, true end        -- limite de débit : on réessaie plus tard
  if LOCKDOWN and res == LOCKDOWN then                    -- donjon : on attend la sortie
    self.pausedUntil = GetTime() + 10
    return false, true
  end
  if OFFLINE and res == OFFLINE and item.to then         -- destinataire déconnecté
    self:OnUnreachable(key(item.to))
    return true
  end
  self.lastError = res
  return false
end

function Comm:Pump()
  local now = GetTime()
  self.tokens = math.min(BURST, self.tokens + (now - (self.lastPump or now)) * RATE)
  self.lastPump = now
  if not self:IsReady() then return end
  if self.pausedUntil and now < self.pausedUntil then return end
  if self:Locked() then
    self.wasLocked = true
    self.pausedUntil = now + 2
    return
  elseif self.wasLocked then
    -- sortie de donjon : on se signale de nouveau à la bande (sans notification de connexion)
    self.wasLocked = false
    wipe(self.discovered)
    self:Discover(true)
  end
  while self.tokens >= 1 do
    local q = self.queue
    local queue = (#q[1] > 0 and q[1]) or (#q[2] > 0 and q[2]) or (#q[3] > 0 and q[3])
    if not queue then return end
    local ok, retry = self:RawSend(queue[1])
    if retry then
      self.pausedUntil = now + 1.5
      return
    end
    table.remove(queue, 1)
    self.tokens = self.tokens - 1
    if ok then
      self.failures = 0
    else
      self:OnFailure()
      return
    end
  end
end

function Comm:OnFailure()
  self.failures = self.failures + 1
  self.pausedUntil = GetTime() + 2
  if self.failures == 5 and not self.warned then
    self.warned = true
    ns.Print(string.format(L["le jeu refuse les messages de KEK (code %s). Réessaie plus tard ou signale-le."], tostring(self.lastError)))
  end
end

-- Un membre sondé est hors ligne : on masque le message du jeu et on oublie ce qu'on lui destinait.
function Comm:FilterSystem(msg)
  local pattern = NotFoundPattern()
  if not pattern or type(msg) ~= "string" or U.Secret(msg) then return false end
  local name = msg:match(pattern)
  if not name then return false end
  name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local k = key(U.FullName(name))
  local t = self.pinged[k] or self.pinged[key(name)]
  if not t or GetTime() - t > PING_TTL then return false end
  self:OnUnreachable(k)
  return true
end

function Comm:OnUnreachable(k)
  for _, queue in ipairs(self.queue) do
    for i = #queue, 1, -1 do
      if queue[i].to and key(queue[i].to) == k then table.remove(queue, i) end
    end
  end
  for name in pairs(ns.Store.online) do
    if key(name) == k then ns.Store:SetOnline(name, false) end
  end
  local pending = self.manual[k]
  if pending then
    self.manual[k] = nil
    ns.Print(string.format(L["%s n'est pas connecté : réessaie quand il sera en jeu."], U.Short(pending.name)))
  end
  for name, log in pairs(self.pingLog) do
    if key(name) == k and log.state ~= "ok" then log.state = "notfound" end
  end
  -- autotest : le jeu ne trouve pas le destinataire du test
  for token, p in pairs(self.probes) do
    if p.targetKey == k then
      self.probes[token] = nil
      p.cb(false, string.format(L["le jeu répond « joueur introuvable » pour « %s »"], tostring(p.target)))
    end
  end
end

-- ------------------------------------------------------------------ réception
-- ------------------------------------------------------------------ autotest
-- Message envoyé à soi-même : le jeu le renvoie-t-il, par quel chemin, sous quel nom ?
-- (« ? » n'est jamais utilisé par le protocole : ces messages ne se mélangent pas aux autres.)
Comm.probes = {}

function Comm:NotFoundPattern()
  return NotFoundPattern()
end

-- kind : « s » message à soi-même, « p » ping à un ami (qui répond « r »).
function Comm:Probe(dist, target, callback, kind)
  local token = tostring(math.random(100000, 999999))
  local p = { cb = callback, t = GetTime(), target = target }
  self.probes[token] = p
  if dist == "WHISPER" and target then
    p.targetKey = key(U.FullName(target))
    self.pinged[p.targetKey] = GetTime()
    self.pinged[key(target)] = GetTime()
  end
  local ok, res = pcall(SendAddon, PREFIX, "?" .. (kind or "s") .. token, dist, target)
  if not ok or not (res == nil or res == true or res == 0) then
    self.probes[token] = nil
    callback(false, ok and string.format(L["refusé par le jeu (code %s)"], tostring(res)) or (L["erreur : "] .. tostring(res)))
    return
  end
  C_Timer.After(5, function()
    local p = self.probes[token]
    if not p then return end
    self.probes[token] = nil
    p.cb(false, kind == "p" and L["pas de réponse dans les 5 secondes"] or L["envoyé, mais pas reçu en retour dans les 5 secondes"])
  end)
end

-- Battle.net : un ami connecté à WoW peut recevoir des données d'addon par son compte Battle.net.
local function SendBN(id, text)
  local fn = BNSendGameData or (C_BattleNet and C_BattleNet.SendGameData)
  if not fn then return false, "absent" end
  return pcall(fn, id, PREFIX, text)
end

function Comm:HasBN()
  return (BNSendGameData or (C_BattleNet and C_BattleNet.SendGameData)) ~= nil
end

function Comm:ProbeBN(id, callback)
  local token = tostring(math.random(100000, 999999))
  self.probes[token] = { cb = callback, t = GetTime(), bn = true }
  local ok, err = SendBN(id, "?p" .. token)
  if not ok then
    self.probes[token] = nil
    callback(false, L["erreur : "] .. tostring(err))
    return
  end
  C_Timer.After(5, function()
    local p = self.probes[token]
    if not p then return end
    self.probes[token] = nil
    p.cb(false, L["pas de réponse dans les 5 secondes"])
  end)
end

function Comm:OnBNMessage(prefix, text, _, senderID)
  if U.Secret(prefix) or U.Secret(text) or prefix ~= PREFIX or type(text) ~= "string" then return end
  self.stats.bnRecv = (self.stats.bnRecv or 0) + 1
  if text:sub(1, 1) ~= "?" then return end
  local kind, token = text:sub(2, 2), text:sub(3)
  if kind == "p" and senderID and not self:Locked() then
    SendBN(senderID, "?r" .. token)
  elseif kind == "r" then
    local p = self.probes[token]
    if not p then return end
    self.probes[token] = nil
    p.cb(true, string.format(L["aller-retour en %.1f s (Battle.net)"], GetTime() - p.t))
  end
end

Comm.pongs = {}

function Comm:OnProbe(kind, token, dist, sender)
  if kind == "p" then
    -- un ami teste la liaison : on répond aussitôt (au plus une fois toutes les 2 secondes)
    local who = U.FullName(sender)
    if not who or who == ns.me or self:Locked() then return end
    if self.pongs[who] and GetTime() - self.pongs[who] < 2 then return end
    self.pongs[who] = GetTime()
    pcall(SendAddon, PREFIX, "?r" .. token, "WHISPER", self:WhisperTarget(who))
    return
  end
  local p = self.probes[token]
  if not p then return end
  self.probes[token] = nil
  local elapsed = GetTime() - p.t
  if kind == "r" then
    p.cb(true, string.format(L["aller-retour en %.1f s (chuchotements)"], elapsed))
  else
    p.cb(true, string.format(L["reçu via %s en %.1f s, expéditeur « %s »"], tostring(dist), elapsed, tostring(sender)))
  end
end

function Comm:OnMessage(prefix, text, dist, sender)
  if U.Secret(prefix) or U.Secret(text) or U.Secret(sender) then return end   -- illisible en donjon
  if prefix == PREFIX and type(text) == "string" and text:sub(1, 1) == "?" then
    local kind = text:sub(2, 2)
    if kind:match("%d") then                     -- autotest de la version 1.5.0
      self:OnProbe("s", text:sub(2), dist, sender)
    else
      self:OnProbe(kind, text:sub(3), dist, sender)
    end
    return
  end
  if prefix ~= PREFIX or type(text) ~= "string" then return end
  local raw = sender
  sender = U.FullName(sender)
  if not sender or sender == ns.me then return end
  local st = self.stats
  st.recv = st.recv + 1
  st.from, st.fromDist, st.rawFrom = sender, dist, raw
  if not self.tag then st.noBand = st.noBand + 1; return end
  if not ACCEPT[dist] or #text < 4 then return end

  local marker, id = text:sub(1, 1), text:sub(2, 3)
  local payload
  if marker == "!" then
    payload = text:sub(4)
  else
    local bkey = sender .. ":" .. dist .. ":" .. id
    local part = text:sub(4)
    if marker == "[" then
      self.buffers[bkey] = { part, t = GetTime() }
      return
    end
    local buffer = self.buffers[bkey]
    if not buffer then return end
    buffer[#buffer + 1] = part
    buffer.t = GetTime()
    if marker == "=" then return end
    self.buffers[bkey] = nil
    if marker ~= "]" then return end
    payload = table.concat(buffer)
  end

  local seenKey = sender .. ":" .. id
  local seenAt = self.seen[seenKey]
  if seenAt and GetTime() - seenAt < SEEN_TTL then return end

  local msg = ns.Ser.Decode(payload)
  if type(msg) ~= "table" or type(msg.k) ~= "string" then return end
  if msg.b ~= self.tag then                                   -- autre bande
    st.otherBand = st.otherBand + 1
    local log = self.pingLog[sender]
    if log and log.state ~= "ok" then log.state = "otherband" end
    if (dist == "WHISPER") then self.pingLog[sender] = self.pingLog[sender] or { t = GetTime(), state = "otherband" } end
    return
  end
  if msg.b == "g" and dist ~= "GUILD" then return end
  if (tonumber(msg.v) or 0) < ns.PROTO then
    st.oldVersion = st.oldVersion + 1
    st.oldFrom, st.oldV = sender, msg.v
    return
  end
  if msg.to and key(msg.to) ~= key(ns.me) then return end
  self.seen[seenKey] = GetTime()

  local pending = self.manual[key(sender)]
  if pending then
    self.manual[key(sender)] = nil
    ns.Print(string.format(L["%s fait partie de ta bande !"], U.Short(sender)))
  end
  self.discovered[sender] = true
  if self.pingLog[sender] then self.pingLog[sender].state = "ok" end
  msg.fresh = not ns.Store:IsOnline(sender)   -- premier message reçu de ce membre depuis son arrivée
  if msg.k == "B" then
    -- l'identifiant de messages repart de zéro après un /reload : on oublie les anciens
    for k in pairs(self.seen) do
      if k:sub(1, #sender + 1) == sender .. ":" then self.seen[k] = nil end
    end
  else
    ns.Store:SetOnline(sender, true)
  end
  ns:Fire("MSG_" .. msg.k, sender, msg.d, msg, dist)
end

function Comm:Clean()
  local now = GetTime()
  for k, buffer in pairs(self.buffers) do
    if now - (buffer.t or 0) > 60 then self.buffers[k] = nil end
  end
  for k, t in pairs(self.seen) do
    if now - t > SEEN_TTL then self.seen[k] = nil end
  end
  for k, t in pairs(self.pinged) do
    if now - t > PING_TTL * 3 then self.pinged[k] = nil end
  end
end
