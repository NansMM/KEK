-- KEK — protocole : bonjour, état, au revoir, et synchronisation des jeux de données par empreinte.
--   H  bonjour (je viens d'arriver)        S  état du personnage (aussi battement de cœur)
--   B  au revoir                           Q  demande d'un jeu de données (adressée)
--   X  jeu de données {w, h, p}            E  événement (voir Alerts)
local _, ns = ...

local Sync = ns:NewModule("Sync", 20)

local HEARTBEAT = 120
Sync.datasets = {}
Sync.requested = {}
Sync.lastPush = {}

-- def = { prio, build() -> payload, ownHash() -> hash, knownHash(sender) -> hash, apply(sender, payload, hash) }
function Sync:Dataset(key, def)
  def.key = key
  self.datasets[key] = def
end

function Sync:OwnHashes()
  local hs = {}
  for key, def in pairs(self.datasets) do
    local ok, h = pcall(def.ownHash)
    if ok and h then hs[key] = h end
  end
  return hs
end

-- Membres connus, à transmettre à un nouvel arrivant pour qu'il trouve toute la bande d'un coup.
function Sync:Peers()
  local list = {}
  local horizon = ns.Now() - 60 * 86400
  for name, m in pairs(ns.db.members) do
    if name ~= ns.me and (m.seen or 0) > horizon then list[#list + 1] = { name, m.seen or 0 } end
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local names = {}
  for i = 1, math.min(#list, 40) do names[i] = list[i][1] end
  -- mes autres personnages font aussi partie de la bande
  for char in pairs(ns.db.inv or {}) do
    if char ~= ns.me and #names < 50 then names[#names + 1] = char end
  end
  return names
end

-- Envoie mon état à toute la bande, ou à un seul membre (to) avec la liste des membres connus.
function Sync:SendState(to)
  if not ns.Comm:IsReady() then return end
  local state = ns.Profile:BuildState()
  state.hs = self:OwnHashes()
  if to then
    state.pe = self:Peers()
    ns.Comm:Send("S", state, 2, to)
    return
  end
  ns.Comm:Send("S", state, 2)
  self.lastState = GetTime()
end

-- Planifie un envoi d'état (regroupe les changements rapprochés).
function Sync:Dirty(delay)
  ns:Debounce("sync-state", delay or 4, function() self:SendState() end)
end

-- Un membre vient d'apparaître : il reçoit mon état (une seule fois par période de 30 s).
function Sync:Greet(name)
  local last = self.greeted[name]
  if last and GetTime() - last < 30 then return end
  self.greeted[name] = GetTime()
  C_Timer.After(0.5 + math.random() * 1.5, function()
    if ns.Store:IsOnline(name) then self:SendState(name) end
  end)
end

-- Envoie un jeu de données à toute la bande (après une modification locale) ou à celui qui l'a demandé.
function Sync:Push(key, to)
  local def = self.datasets[key]
  if not def or not ns.Comm:IsReady() then return end
  local hash = def.ownHash()
  local tag = key .. ":" .. (to or "*")
  local last = self.lastPush[tag]
  if last and last.h == hash and GetTime() - last.t < 15 then return end
  self.lastPush[tag] = { h = hash, t = GetTime() }
  ns.Comm:Send("X", { w = key, h = hash, p = def.build() }, def.prio or 3, to)
end

function Sync:Request(sender, key)
  local tag = sender .. ":" .. key
  local last = self.requested[tag]
  if last and GetTime() - last < 45 then return end
  self.requested[tag] = GetTime()
  ns.Comm:Send("Q", { w = key }, 2, sender)
end

Sync.greeted = {}

function Sync:OnLogin()
  -- à la connexion, KEK sonde la bande (voir Comm:Discover) ; ceux qui répondent reçoivent mon état
  ns:On("COMM_READY", function()
    wipe(self.greeted)
    self:Dirty(1.5)
  end)

  ns:On("PRESENCE", function(name, online)
    if online then self:Greet(name) else self.greeted[name] = nil end
  end)

  ns:On("MSG_H", function(sender)
    ns.Store:SetOnline(sender, true)
    self:Greet(sender)
  end)

  ns:On("MSG_S", function(sender, state)
    if type(state) ~= "table" then return end
    ns.Profile:ApplyState(sender, state)
    ns.Store:SetOnline(sender, true)
    if type(state.hs) == "table" then
      for key, def in pairs(self.datasets) do
        local remote = state.hs[key]
        if remote and remote ~= def.knownHash(sender) then
          self:Request(sender, key)
        end
      end
    end
    -- membres que je ne connais pas encore : je les sonde
    if type(state.pe) == "table" then
      for _, raw in ipairs(state.pe) do
        local name = type(raw) == "string" and ns.U.FullName(raw)
        if name and name ~= ns.me and not ns.db.members[name] then
          ns.Comm:Ping(name, 3)
        end
      end
    end
  end)

  ns:On("MSG_B", function(sender)
    ns.Store:SetOnline(sender, false)
  end)

  ns:On("MSG_Q", function(sender, data)
    if type(data) == "table" and data.w then self:Push(data.w, sender) end
  end)

  ns:On("MSG_X", function(sender, data)
    if type(data) ~= "table" then return end
    local def = self.datasets[data.w]
    if not def or data.p == nil then return end
    ns.Store:Touch(sender)
    def.apply(sender, data.p, data.h)
    ns:Fire("DATA", data.w)
  end)

  C_Timer.NewTicker(HEARTBEAT, function()
    if ns.Comm:IsReady() then self:SendState() end
  end)
end

-- Aide : empreinte mémorisée pour un jeu de données reçu (remplacement complet).
function Sync:StoredHash(sender, key)
  local h = ns.db.hashes[sender]
  return h and h[key]
end

function Sync:StoreHash(sender, key, hash)
  local h = ns.db.hashes[sender]
  if not h then h = {}; ns.db.hashes[sender] = h end
  h[key] = hash
end
