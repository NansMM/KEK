-- KEK — noyau : espace de noms, événements, bus interne, modules, base de données.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.PROTO = 2   -- 2 : plus de canal personnalisé (interdit en Classic), guilde + groupe + chuchotements
ns.MAX_LEVEL = 60

-- Les textes sont écrits en français directement dans le code ; la table L
-- permet d'ajouter une traduction plus tard sans toucher aux modules.
ns.L = setmetatable({}, { __index = function(_, key) return key end })

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "1.9.1"

local pcall, type, ipairs = pcall, type, ipairs

local function report(err)
  -- compté pour l'autotest (les erreurs Lua sont souvent masquées en jeu)
  ns.errorCount = (ns.errorCount or 0) + 1
  ns.lastError = err
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(err) else print(err) end
end
ns.Report = report

function ns.SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then report(err) end
  return ok, err
end

function ns.Now()
  return (GetServerTime and GetServerTime()) or time()
end

-- ------------------------------------------------------------------ événements WoW
local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Retourne false si l'événement n'existe pas dans ce client (API différente selon la version).
function ns:RegisterEvent(event, fn)
  local list = handlers[event]
  if not list then
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
    list = {}
    handlers[event] = list
  end
  list[#list + 1] = fn
  return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then report(err) end
  end
end)

-- ------------------------------------------------------------------ bus interne
local listeners = {}

function ns:On(message, fn)
  local list = listeners[message]
  if not list then list = {}; listeners[message] = list end
  list[#list + 1] = fn
end

function ns:Fire(message, ...)
  local list = listeners[message]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then report(err) end
  end
end

-- Regroupe les appels rapprochés : fn s'exécute une seule fois, `delay` secondes après le premier appel.
local pending = {}
function ns:Debounce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    ns.SafeCall(fn)
  end)
end

-- ------------------------------------------------------------------ modules
ns.modules = {}

function ns:NewModule(name, order)
  local module = { name = name, order = order or 50 }
  self.modules[#self.modules + 1] = module
  self[name] = module
  return module
end

local function runModules(method)
  table.sort(ns.modules, function(a, b) return a.order < b.order end)
  for _, module in ipairs(ns.modules) do
    if type(module[method]) == "function" then
      ns.SafeCall(module[method], module)
    end
  end
end

-- ------------------------------------------------------------------ base de données
local DEFAULTS = {
  schema = 1,
  band = { code = "" },                     -- code vide : la bande, c'est la guilde
  nick = "",
  members = {},
  feed = {},
  deaths = {},
  prog = {},
  recipes = {},
  reagents = {},                           -- composants des recettes que tu connais (tous tes persos)
  needs = {},
  have = {},
  inv = {},
  hashes = {},
  ui = {
    view = "roster",
    scale = 1,
    width = 900,
    height = 620,
    rosterSort = "level",
    showOffline = true,
    feedFilter = "all",
    craftTab = "recipes",
    sessionTab = "current",
    minimap = { hide = false },             -- position et état gérés par LibDBIcon
  },
  alerts = {
    level = true, loot = true, death = true, boss = true, skill = true, presence = true, need = true, boe = true,
    sound = true, self = false, lootQuality = 4,
  },
}

local CHAR_DEFAULTS = {
  session = nil,
  last = nil,
}

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      merge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end
ns.MergeDefaults = merge

ns:RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  KEKDB = type(KEKDB) == "table" and KEKDB or {}
  KEKCharDB = type(KEKCharDB) == "table" and KEKCharDB or {}
  merge(KEKDB, DEFAULTS)
  merge(KEKCharDB, CHAR_DEFAULTS)
  ns.db = KEKDB
  ns.char = KEKCharDB
  runModules("OnInit")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
  local first, second = UnitName("player")
  ns.U.DetectNames(first, second)        -- WoW Forever : prénom + nom de famille
  ns.me = ns.U.FullName(first, second)
  runModules("OnLogin")
  ns.ready = true
  ns:Fire("READY")
end)

function ns:ResetAll()
  wipe(KEKDB)
  wipe(KEKCharDB)
  merge(KEKDB, DEFAULTS)
  merge(KEKCharDB, CHAR_DEFAULTS)
  ReloadUI()
end

function ns.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff8c3dKEK|r · " .. tostring(msg))
end

-- ------------------------------------------------------------------ diagnostic
-- Si le jeu bloque malgré tout une action attribuée à KEK, on dit laquelle dans le chat
-- et on la garde (commande /kek diag) : c'est ce qu'il faut pour corriger l'addon.
local blockedSeen = {}
local function onBlocked(event, addon, func)
  if addon ~= ADDON then return end
  func = tostring(func or "?")
  if ns.db then
    ns.db.diag = ns.db.diag or {}
    table.insert(ns.db.diag, 1, { t = ns.Now(), e = event, f = func, v = ns.VERSION })
    for i = #ns.db.diag, 21, -1 do ns.db.diag[i] = nil end
  end
  if blockedSeen[func] then return end
  blockedSeen[func] = true
  C_Timer.After(1, function()
    ns.Print(string.format(ns.L["le jeu a bloqué l'action |cffffd060%s|r (%s). Fais une capture de cette ligne : elle permet de corriger KEK."],
      func, event == "ADDON_ACTION_FORBIDDEN" and ns.L["interdite aux addons"] or ns.L["interdite en combat"]))
  end)
end
ns:RegisterEvent("ADDON_ACTION_FORBIDDEN", onBlocked)
ns:RegisterEvent("ADDON_ACTION_BLOCKED", onBlocked)
