-- KEK — portrait du personnage : classe, niveau, zone, spécialisation, métiers.
local _, ns = ...
local U = ns.U

local Profile = ns:NewModule("Profile", 30)

-- clé courte (réseau) -> champ du membre
local FIELDS = {
  c = "class", r = "race", rn = "raceName", sx = "sex", l = "level", x = "xp", rx = "rested",
  z = "zone", sz = "sub", g = "guild", n = "nick", sp = "spec", pr = "profs", dc = "deaths",
  pl = "played", eta = "eta", etd = "etaDate", ss = "session", ver = "ver", dead = "dead",
  ins = "instance",
}

-- Interface récente : une spécialisation choisie, sans arbres à points.
local function readModernSpec()
  local SI = C_SpecializationInfo
  local getSpec = (SI and SI.GetSpecialization) or GetSpecialization
  local getInfo = (SI and SI.GetSpecializationInfo) or GetSpecializationInfo
  if not getSpec or not getInfo then return nil end
  local ok, index = pcall(getSpec)
  if not ok or type(index) ~= "number" or index == 0 then return nil end
  local ok2, _, name, _, icon = pcall(getInfo, index)
  if not ok2 or type(name) ~= "string" or name == "" then return nil end
  return { { n = name, i = icon, p = 0 }, s = true, a = 1, g = 1 }
end

function Profile:ReadSpec()
  if not GetNumTalentTabs then return readModernSpec() end
  local group = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  local tabs = {}
  for i = 1, (GetNumTalentTabs() or 0) do
    local r = { pcall(GetTalentTabInfo, i, false, false, group) }
    if r[1] then
      local name, icon, points
      if type(r[2]) == "string" then
        name, icon, points = r[2], r[3], r[4]          -- nom, icône, points, fichier
      else
        name, icon, points = r[3], r[5], r[6]          -- id, nom, description, icône, points
      end
      if type(name) == "string" then
        tabs[#tabs + 1] = { n = name, i = icon, p = tonumber(points) or 0 }
      end
    end
  end
  if #tabs == 0 then return readModernSpec() end
  tabs.a = group
  tabs.g = (GetNumTalentGroups and GetNumTalentGroups()) or 1
  return tabs
end

-- Spécialisation dominante : nom, icône, « 31 · 0 · 20 ».
function Profile.SpecSummary(spec)
  if type(spec) ~= "table" or #spec == 0 then return nil end
  if spec.s then return spec[1].n, spec[1].i, "", 1 end     -- spécialisation sans points
  local best, total, parts = nil, 0, {}
  for i, tab in ipairs(spec) do
    total = total + (tab.p or 0)
    parts[i] = tostring(tab.p or 0)
    if not best or (tab.p or 0) > (best.p or 0) then best = tab end
  end
  if total == 0 then return nil end
  return best.n, best.i, table.concat(parts, " · "), total
end

-- Interface récente : métiers par GetProfessions (plus de lignes de compétence).
local function readModernProfs()
  if not GetProfessions or not GetProfessionInfo then return nil end
  local ok, p1, p2, arch, fish, cook = pcall(GetProfessions)
  if not ok then return nil end
  local list = {}
  for _, index in pairs({ p1, p2, arch, fish, cook }) do
    local okInfo, name, _, rank, maxRank = pcall(GetProfessionInfo, index)
    if okInfo and type(name) == "string" and name ~= "" then
      list[#list + 1] = { n = name, r = tonumber(rank) or 0, m = tonumber(maxRank) or 0 }
    end
  end
  return list
end

local function sortProfs(list)
  table.sort(list, function(a, b)
    local sa, sb = U.PROF_SECONDARY[a.n] and 1 or 0, U.PROF_SECONDARY[b.n] and 1 or 0
    if sa ~= sb then return sa < sb end
    return a.r > b.r
  end)
  return list
end

function Profile:ReadProfs()
  if not GetNumSkillLines then
    local modern = readModernProfs()
    return modern and sortProfs(modern)
  end
  local list = {}
  local tradeHeader = (TRADE_SKILLS or "Professions"):gsub(":", "")
  local secondaryHeader = (SECONDARY_SKILLS or "Secondary Skills"):gsub(":", "")
  local header
  for i = 1, (GetNumSkillLines() or 0) do
    local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
    if isHeader then
      header = name and name:gsub(":", "")
    elseif name and (U.PROF_ICON[name] or header == tradeHeader or header == secondaryHeader) then
      list[#list + 1] = { n = name, r = rank or 0, m = maxRank or 0 }
    end
  end
  if #list == 0 then
    local modern = readModernProfs()
    if modern and #modern > 0 then list = modern end
  end
  return sortProfs(list)
end

function Profile:Snapshot()
  local m = ns.Store:Me()
  local _, class = UnitClass("player")
  local raceName, race = UnitRace("player")
  m.class, m.race, m.raceName = class, race, raceName
  m.sex = UnitSex("player")
  m.level = UnitLevel("player")
  local max = UnitXPMax("player") or 0
  if m.level >= ns.MAX_LEVEL or max <= 0 then
    m.xp, m.rested = 0, 0
  else
    m.xp = U.Round((UnitXP("player") or 0) / max, 3)
    m.rested = U.Round(math.min(1.5, (GetXPExhaustion() or 0) / max), 2)
  end
  m.zone = GetRealZoneText() or GetZoneText()
  local sub = GetSubZoneText()
  m.sub = (sub and sub ~= "" and sub ~= m.zone) and sub or nil
  m.guild = GetGuildInfo("player")
  m.spec = self:ReadSpec()
  m.profs = self:ReadProfs() or m.profs
  m.nick = (ns.db.nick ~= "" and ns.db.nick) or nil
  m.ver = ns.VERSION
  m.dead = UnitIsDeadOrGhost("player") and true or nil
  m.instance = IsInInstance() and true or nil
  return m
end

function Profile:BuildState()
  local m = self:Snapshot()
  local state = {}
  for short, field in pairs(FIELDS) do
    state[short] = m[field]
  end
  return state
end

function Profile:ApplyState(sender, state)
  local m = ns.Store:Touch(sender)
  for short, field in pairs(FIELDS) do
    m[field] = state[short]
  end
  ns:Fire("DATA", "members")
end

function Profile:Changed(delay)
  self:Snapshot()
  ns:Fire("DATA", "members")
  ns.Sync:Dirty(delay)
end

function Profile:OnLogin()
  self:Snapshot()
  local quick = function() self:Changed(3) end
  local slow = function() ns:Debounce("profile-slow", 6, function() self:Changed(8) end) end
  for _, event in ipairs({ "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_TALENT_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    ns:RegisterEvent(event, quick)   -- un événement absent de ce client est simplement ignoré
  end
  -- talents et métiers ne sont pas toujours prêts à la connexion : nouvelle lecture un peu plus tard
  C_Timer.After(12, quick)
  for _, event in ipairs({ "PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "SKILL_LINES_CHANGED",
    "UPDATE_EXHAUSTION" }) do
    ns:RegisterEvent(event, slow)
  end
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, quick) end)
end
