-- KEK — membres de la bande et présence en ligne.
local _, ns = ...

local Store = ns:NewModule("Store", 5)
local OFFLINE_AFTER = 330   -- secondes sans nouvelles avant de considérer un membre hors ligne

Store.online = {}

function Store:Get(name, create)
  if not name then return nil end
  local m = ns.db.members[name]
  if not m and create then
    m = { name = name, first = ns.Now(), seen = ns.Now() }
    ns.db.members[name] = m
  end
  return m
end

function Store:Me()
  local m = self:Get(ns.me, true)
  m.seen = ns.Now()
  return m
end

function Store:Touch(name)
  local m = self:Get(name, true)
  m.seen = ns.Now()
  return m
end

function Store:IsOnline(name)
  if name == ns.me then return true end
  return self.online[name] == true
end

function Store:SetOnline(name, on)
  if name == ns.me then return end
  local was = self.online[name] == true
  if on then
    self:Touch(name)
    self.online[name] = true
  else
    self.online[name] = nil
  end
  if was ~= (on and true or false) then
    ns:Fire("PRESENCE", name, on and true or false)
    ns:Fire("DATA", "members")
  end
end

function Store:OnlineCount()
  local n = 0
  for name in pairs(self.online) do
    if ns.db.members[name] then n = n + 1 end
  end
  return n
end

function Store:Members()
  local list = {}
  for name, m in pairs(ns.db.members) do
    m.name = name
    list[#list + 1] = m
  end
  return list
end

function Store:Remove(name)
  if name == ns.me then return end
  local db = ns.db
  db.members[name] = nil
  db.prog[name] = nil
  db.recipes[name] = nil
  db.needs[name] = nil
  db.deaths[name] = nil
  db.hashes[name] = nil
  db.have[name] = nil
  for _, perItem in pairs(db.have) do
    for _, holders in pairs(perItem) do holders[name] = nil end
  end
  self.online[name] = nil
  ns:Fire("DATA", "members")
end

function Store:ClearPresence()
  wipe(self.online)
  ns:Fire("DATA", "members")
end

-- Réparation : les versions ≤ 1.5.2 enregistraient parfois un nom mal formé (« Nokie Jenkins-Jenkins »),
-- ce qui faisait apparaître un même personnage deux fois. On ramène chaque nom à sa forme canonique ;
-- si la bonne fiche existe déjà, la copie fautive est simplement supprimée.
local function renameKeys(tbl, onMerge)
  if type(tbl) ~= "table" then return 0 end
  local moves = {}
  for name in pairs(tbl) do
    if type(name) == "string" then
      local fixed = ns.U.FullName(name)
      if fixed and fixed ~= name then moves[#moves + 1] = { name, fixed } end
    end
  end
  for _, mv in ipairs(moves) do
    local old, fixed = mv[1], mv[2]
    if tbl[fixed] == nil then
      tbl[fixed] = tbl[old]
    elseif onMerge then
      onMerge(tbl[fixed], tbl[old])
    end
    tbl[old] = nil
  end
  return #moves
end

function Store:RepairNames()
  local db = ns.db
  local fixed = renameKeys(db.members)
  for name, m in pairs(db.members) do m.name = name end
  for _, key in ipairs({ "prog", "recipes", "needs", "deaths", "hashes", "inv" }) do
    fixed = fixed + renameKeys(db[key])
  end
  if type(db.have) == "table" then
    fixed = fixed + renameKeys(db.have)
    for _, perItem in pairs(db.have) do
      if type(perItem) == "table" then
        for _, holders in pairs(perItem) do fixed = fixed + renameKeys(holders) end
      end
    end
  end
  for _, e in ipairs(db.feed or {}) do
    local w = type(e.w) == "string" and ns.U.FullName(e.w)
    if w and w ~= e.w then e.w = w; fixed = fixed + 1 end
  end
  -- le fil a pu recevoir deux fois le même événement (l'original et son écho mal nommé)
  if fixed > 0 and type(db.feed) == "table" then
    local seen, kept = {}, {}
    for _, e in ipairs(db.feed) do
      local id = tostring(e.w) .. ":" .. tostring(e.k) .. ":" .. tostring(e.t)
      if not seen[id] then
        seen[id] = true
        kept[#kept + 1] = e
      end
    end
    wipe(db.feed)
    for i, e in ipairs(kept) do db.feed[i] = e end
  end
  return fixed
end

function Store:OnLogin()
  local ok, fixed = pcall(self.RepairNames, self)
  if ok and fixed > 0 then self.repaired = fixed end
  local me = self:Me()
  me.first = me.first or ns.Now()
  C_Timer.NewTicker(30, function()
    local now = ns.Now()
    for name in pairs(self.online) do
      local m = ns.db.members[name]
      -- sans nouvelles de KEK… sauf si le jeu le voit encore connecté (donjon : messages coupés)
      if not m or (now - (m.seen or 0) > OFFLINE_AFTER and not (ns.Presence and ns.Presence:Connected(name))) then
        self:SetOnline(name, false)
      end
    end
  end)
end
