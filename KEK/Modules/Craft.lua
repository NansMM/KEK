-- KEK — atelier : annuaire des recettes, inventaires (sacs + banque, tous tes personnages), liste de besoins.
local _, ns = ...
local L, U = ns.L, ns.U

local Craft = ns:NewModule("Craft", 44)

local SEP, KV = "`", "="
local RSEP, RQTY, NONE = ";", "*", "-"   -- composants envoyés à la bande : « 2589*2;2320*1 », « - » si inconnus
local HASH_V = 2                          -- 2 : les composants comptent dans l'empreinte des recettes (1.10.1)

-- ------------------------------------------------------------------ recettes
local function ownRecipes()
  local r = ns.db.recipes[ns.me]
  if not r then
    r = { p = {} }
    ns.db.recipes[ns.me] = r
  end
  return r
end

local function profEntry(prof, rank, maxRank)
  local own = ownRecipes()
  local entry = own.p[prof]
  if not entry then
    entry = { l = {} }
    own.p[prof] = entry
  end
  entry.r, entry.m = rank, maxRank
  return entry
end

-- Composants d'une recette, mémorisés pour pouvoir les demander à la bande.
local function storeReagents(prof, recipe, list)
  if type(recipe) == "string" and #list > 0 then ns.db.reagents[recipe] = { p = prof, l = list } end
end

local function reagentList(count, info, link)
  local list = {}
  for r = 1, count or 0 do
    local name, _, need = info(r)
    local id = U.ItemID(link and link(r))
    if id or name then list[#list + 1] = { i = id, s = name, q = tonumber(need) or 1 } end
  end
  return list
end

function Craft:ScanTradeSkill()
  if not GetTradeSkillLine or not GetNumTradeSkills then return self:ScanModern() end
  local prof, rank, maxRank = GetTradeSkillLine()
  self.lastScan = { t = ns.Now(), api = "GetNumTradeSkills", prof = prof, rank = rank, max = maxRank, total = GetNumTradeSkills() or 0 }
  if not prof or prof == "UNKNOWN" or not rank or rank == 0 then
    self.lastScan.why = "aucun métier ouvert"
    return
  end
  local entry = profEntry(prof, rank, maxRank)
  local before = U.Count(entry.l)
  for i = 1, (GetNumTradeSkills() or 0) do
    local name, kind = GetTradeSkillInfo(i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
      entry.l[name] = U.ItemID(link) or 0
      if GetTradeSkillNumReagents and GetTradeSkillReagentInfo then
        local ok, list = pcall(reagentList, GetTradeSkillNumReagents(i),
          function(r) return GetTradeSkillReagentInfo(i, r) end,
          GetTradeSkillReagentItemLink and function(r) return GetTradeSkillReagentItemLink(i, r) end)
        if ok then storeReagents(prof, name, list) end
      end
    end
  end
  self:OwnChanged(before ~= U.Count(entry.l))
end

-- Quel métier est ouvert dans la fenêtre récente ? (nom, rang, rang max)
local function modernProfession(TS)
  local prof, rank, maxRank, seen = nil, nil, nil, {}
  for _, fn in ipairs({ "GetChildProfessionInfo", "GetBaseProfessionInfo" }) do
    if TS[fn] then
      local ok, info = pcall(TS[fn])
      if ok and type(info) == "table" then
        local name = (type(info.parentProfessionName) == "string" and info.parentProfessionName ~= "" and info.parentProfessionName)
          or info.professionName
        seen[#seen + 1] = string.format("%s=%s %s/%s", fn:gsub("^Get", ""):gsub("ProfessionInfo$", ""), tostring(name),
          tostring(info.skillLevel), tostring(info.maxSkillLevel))
        if type(name) == "string" and name ~= "" then
          prof = prof or name
          if not rank and (tonumber(info.skillLevel) or 0) > 0 then rank, maxRank = info.skillLevel, info.maxSkillLevel end
        end
      end
    end
  end
  if not prof and TS.GetTradeSkillLine then
    local ok, name, r, m = pcall(TS.GetTradeSkillLine)
    if ok and type(name) == "string" and name ~= "" then prof, rank, maxRank = name, r, m end
  end
  -- rang inconnu : on le prend dans la fiche du personnage (GetProfessions)
  if prof and not rank then
    for _, p in ipairs(ns.Store:Me().profs or {}) do
      if p.n == prof then rank, maxRank = p.r, p.m end
    end
  end
  return prof, rank, maxRank, table.concat(seen, ", ")
end

-- Interface récente (WoW Forever) : C_TradeSkillUI, recettes par identifiant et « schémas » de composants.
-- Chaque lecture est notée (Craft.lastScan) pour que l'autotest explique ce qui s'est passé.
function Craft:ScanModern()
  local TS = C_TradeSkillUI
  local log = { t = ns.Now(), api = "C_TradeSkillUI" }
  self.lastScan = log
  if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo) then
    log.why = "C_TradeSkillUI.GetAllRecipeIDs ou GetRecipeInfo absent"
    return false
  end
  local prof, rank, maxRank, seen = modernProfession(TS)
  log.info = seen
  if not prof then
    log.why = "métier ouvert inconnu"
    return false
  end
  log.prof, log.rank, log.max = prof, rank, maxRank
  local entry = profEntry(prof, rank or 1, maxRank)
  local before = U.Count(entry.l)
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  local ids = TS.GetAllRecipeIDs() or {}
  log.total, log.learned, log.reagents = #ids, 0, 0
  for _, recipeID in ipairs(ids) do
    local okR, r = pcall(TS.GetRecipeInfo, recipeID)
    -- « learned » absent dans certaines versions : on considère la recette comme connue
    if okR and type(r) == "table" and r.learned ~= false and type(r.name) == "string" then
      log.learned = log.learned + 1
      local id = 0
      if TS.GetRecipeOutputItemData then
        local okOut, out = pcall(TS.GetRecipeOutputItemData, recipeID)
        if okOut and type(out) == "table" then id = out.itemID or U.ItemID(out.hyperlink) or 0 end
      end
      if id == 0 and TS.GetRecipeItemLink then
        local okLink, link = pcall(TS.GetRecipeItemLink, recipeID)
        if okLink then id = U.ItemID(link) or 0 end
      end
      entry.l[r.name] = id
      if TS.GetRecipeSchematic then
        local okS, schematic = pcall(TS.GetRecipeSchematic, recipeID, false)
        if okS and type(schematic) == "table" and type(schematic.reagentSlotSchematics) == "table" then
          local list = {}
          for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local reagent = type(slot.reagents) == "table" and slot.reagents[1]
            local wanted = slot.required ~= false and (not basic or slot.reagentType == nil or slot.reagentType == basic)
            if wanted and reagent and reagent.itemID then
              list[#list + 1] = { i = reagent.itemID, s = U.GetItemInfo(reagent.itemID), q = slot.quantityRequired or 1 }
            end
          end
          if #list > 0 then log.reagents = log.reagents + 1 end
          storeReagents(prof, r.name, list)
        end
      end
    end
  end
  if log.learned == 0 then log.why = string.format("%d recette(s) listée(s), aucune apprise", log.total) end
  self:OwnChanged(before ~= U.Count(entry.l))
  return true
end

function Craft:ScanCraft()
  if not GetCraftDisplaySkillLine or not GetNumCrafts then return end
  local prof, rank, maxRank = GetCraftDisplaySkillLine()
  if not prof or not rank or rank == 0 then return end   -- dressage des familiers : ignoré
  local entry = profEntry(prof, rank, maxRank)
  local before = U.Count(entry.l)
  for i = 1, (GetNumCrafts() or 0) do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      entry.l[name] = U.ItemID(link) or 0
      if GetCraftNumReagents and GetCraftReagentInfo then
        local ok, list = pcall(reagentList, GetCraftNumReagents(i),
          function(r) return GetCraftReagentInfo(i, r) end,
          GetCraftReagentItemLink and function(r) return GetCraftReagentItemLink(i, r) end)
        if ok then storeReagents(prof, name, list) end
      end
    end
  end
  self:OwnChanged(before ~= U.Count(entry.l))
end

-- Retire les métiers oubliés et met à jour les rangs depuis la fiche de compétences.
function Craft:SyncProfessions()
  local profs = ns.Store:Me().profs
  if type(profs) ~= "table" or #profs == 0 then return end
  local known = {}
  for _, p in ipairs(profs) do known[p.n] = p end
  local own = ownRecipes()
  local changed = false
  for prof, entry in pairs(own.p) do
    if not known[prof] then
      own.p[prof] = nil
      changed = true
    elseif known[prof].r ~= entry.r then
      entry.r, entry.m = known[prof].r, known[prof].m
      changed = true
    end
  end
  if changed then self:OwnChanged(true) end
end

function Craft:OwnChanged(broadcast)
  ownRecipes().h = nil
  ns:Fire("DATA", "recipes")
  if broadcast then ns:Debounce("craft-push-r", 10, function() ns.Sync:Push("r") end) end
end

-- Composants d'une recette en texte compact : identifiant (ou nom, si le jeu n'a pas donné de lien) et quantité.
local function encodeReagents(list)
  local parts = {}
  for _, r in ipairs(list or {}) do
    local key = r.i or (type(r.s) == "string" and not r.s:find("[" .. SEP .. RSEP .. "%*]") and r.s)
    if key then parts[#parts + 1] = key .. RQTY .. (tonumber(r.q) or 1) end
  end
  return #parts > 0 and table.concat(parts, RSEP) or NONE
end

local function decodeReagents(text)
  if type(text) ~= "string" or text == NONE then return nil end
  local list = {}
  for part in text:gmatch("[^" .. RSEP .. "]+") do
    local key, q = part:match("^(.-)%" .. RQTY .. "(%d+)$")
    if key and key ~= "" then
      local id = key:match("^%d+$") and tonumber(key)
      list[#list + 1] = { i = id, s = not id and key or nil, q = tonumber(q) or 1 }
    end
  end
  return #list > 0 and list or nil
end

-- Recettes d'un métier dans un ordre fixe : « id=nom » et leurs composants, au même rang.
local function encodeProf(entry)
  local names = {}
  for name in pairs(entry.l) do names[#names + 1] = name end
  table.sort(names)
  local items, reagents = {}, {}
  for i, name in ipairs(names) do
    items[i] = entry.l[name] .. KV .. name
    local rec = ns.db.reagents and ns.db.reagents[name]
    reagents[i] = encodeReagents(rec and rec.l)
  end
  return table.concat(items, SEP), table.concat(reagents, SEP)
end

function Craft:RecipeHash()
  local own = ownRecipes()
  if own.h and own.hv == HASH_V then return own.h end
  local profs = {}
  for prof in pairs(own.p) do profs[#profs + 1] = prof end
  table.sort(profs)
  local parts = {}
  for _, prof in ipairs(profs) do
    local items, reagents = encodeProf(own.p[prof])
    parts[#parts + 1] = prof .. (own.p[prof].r or 0) .. items .. "|" .. reagents
  end
  own.h, own.hv = U.Hash(table.concat(parts, "|")), HASH_V
  return own.h
end

function Craft:EncodeRecipes()
  local out = {}
  for prof, entry in pairs(ownRecipes().p) do
    local items, reagents = encodeProf(entry)
    out[prof] = { r = entry.r, m = entry.m, s = items, g = reagents }
  end
  return out
end

-- Recettes reçues d'un membre, et les composants qui les accompagnent (KEK 1.10.1 et plus).
function Craft:DecodeRecipes(payload)
  local p, reagents = {}, {}
  for prof, entry in pairs(payload) do
    if type(entry) == "table" then
      local l, g = {}, {}
      for chunk in (type(entry.g) == "string" and entry.g or ""):gmatch("[^" .. SEP .. "]+") do g[#g + 1] = chunk end
      local i = 0
      for chunk in (type(entry.s) == "string" and entry.s or ""):gmatch("[^" .. SEP .. "]+") do
        i = i + 1
        local id, name = chunk:match("^(%d+)" .. KV .. "(.+)$")
        if id then
          l[name] = tonumber(id)
          local list = decodeReagents(g[i])
          if list then reagents[name] = { p = prof, l = list } end
        end
      end
      p[prof] = { r = entry.r, m = entry.m, l = l }
    end
  end
  return p, reagents
end

-- Composants appris des autres : ceux que tu as lus toi-même dans ta fenêtre de métier restent prioritaires.
function Craft:MergeReagents(sender, reagents)
  ns.db.reagents = ns.db.reagents or {}
  local asked = {}
  for name, rec in pairs(reagents or {}) do
    local cur = ns.db.reagents[name]
    if not cur or cur.f then
      rec.f = sender
      ns.db.reagents[name] = rec
    end
    -- demande au jeu les composants qu'il ne connaît pas encore (pour afficher leur nom)
    for _, r in ipairs(rec.l) do
      if r.i and not asked[r.i] and not U.GetItemInfo(r.i) and C_Item and C_Item.RequestLoadItemDataByID then
        asked[r.i] = true
        pcall(C_Item.RequestLoadItemDataByID, r.i)
      end
    end
  end
end

-- Recettes dont KEK connaît les composants : lues dans tes fenêtres de métier, ou reçues de la bande.
function Craft:ReagentCounts()
  local own, received = 0, 0
  for _, rec in pairs(ns.db.reagents or {}) do
    if rec.f then received = received + 1 else own = own + 1 end
  end
  return own, received
end

-- Recherche : regroupe par recette, liste qui sait la faire.
function Craft:Search(query, profFilter)
  local q = U.Fold(query or "")
  local results, index = {}, {}
  for who, data in pairs(ns.db.recipes) do
    if ns.db.members[who] and type(data.p) == "table" then
      for prof, entry in pairs(data.p) do
        if not profFilter or profFilter == prof then
          for name, id in pairs(entry.l or {}) do
            if q == "" or U.Fold(name):find(q, 1, true) then
              local row = index[name]
              if not row then
                row = { name = name, id = id ~= 0 and id or nil, prof = prof, crafters = {} }
                index[name] = row
                results[#results + 1] = row
              end
              row.crafters[#row.crafters + 1] = { name = who, rank = entry.r or 0 }
            end
          end
        end
      end
    end
  end
  table.sort(results, function(a, b) return a.name < b.name end)
  for _, row in ipairs(results) do
    table.sort(row.crafters, function(a, b) return a.rank > b.rank end)
  end
  return results
end

-- Vue d'ensemble : chaque métier et qui le pratique.
function Craft:Professions()
  local index, out = {}, {}
  for who, m in pairs(ns.db.members) do
    for _, p in ipairs(type(m.profs) == "table" and m.profs or {}) do
      local row = index[p.n]
      if not row then
        row = { prof = p.n, people = {}, recipes = 0 }
        index[p.n] = row
        out[#out + 1] = row
      end
      local rec = ns.db.recipes[who]
      local count = rec and rec.p and rec.p[p.n] and U.Count(rec.p[p.n].l) or 0
      row.recipes = math.max(row.recipes, count)
      row.people[#row.people + 1] = { name = who, rank = p.r or 0, max = p.m or 0, count = count }
    end
  end
  for _, row in ipairs(out) do
    table.sort(row.people, function(a, b) return a.rank > b.rank end)
  end
  table.sort(out, function(a, b)
    local sa, sb = U.PROF_SECONDARY[a.prof] and 1 or 0, U.PROF_SECONDARY[b.prof] and 1 or 0
    if sa ~= sb then return sa < sb end
    return a.prof < b.prof
  end)
  return out
end

function Craft:CraftersOf(itemID)
  local out = {}
  if not itemID then return out end
  for who, data in pairs(ns.db.recipes) do
    if ns.db.members[who] and type(data.p) == "table" then
      for prof, entry in pairs(data.p) do
        for _, id in pairs(entry.l or {}) do
          if id == itemID then out[#out + 1] = { name = who, prof = prof, rank = entry.r or 0 } break end
        end
      end
    end
  end
  return out
end

-- ------------------------------------------------------------------ inventaires
local function slots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function itemAt(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount or 1, info.hyperlink end
    return nil
  end
  if not GetContainerItemInfo then return nil end
  local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
  return id or U.ItemID(link), count or 1, link
end

-- Compte les objets (par identifiant) et retient leur nom au passage.
local function scan(bags, names)
  local counts = {}
  for _, bag in ipairs(bags) do
    for slot = 1, slots(bag) do
      local id, count, link = itemAt(bag, slot)
      if id then
        counts[id] = (counts[id] or 0) + count
        local name = names and U.ItemName(link)
        if name then names[id] = name end
      end
    end
  end
  return counts
end

function Craft:Inventory()
  local inv = ns.db.inv[ns.me]
  if not inv then inv = { bags = {}, bank = {} }; ns.db.inv[ns.me] = inv end
  inv.names = inv.names or {}
  return inv
end

function Craft:ScanBags()
  local list = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
  local inv = self:Inventory()
  inv.bags = scan(list, inv.names)
  self:InventoryChanged()
end

function Craft:ScanBank()
  if not self.bankOpen then return end
  local list = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do list[#list + 1] = bag end
  local inv = self:Inventory()
  inv.bank = scan(list, inv.names)
  self:InventoryChanged()
end

-- Quantité possédée sur tous tes personnages ; détail par personnage.
function Craft:OwnedCount(itemID)
  local total, detail = 0, {}
  for char, inv in pairs(ns.db.inv) do
    local n = ((inv.bags or {})[itemID] or 0) + ((inv.bank or {})[itemID] or 0)
    if n > 0 then
      total = total + n
      detail[#detail + 1] = { name = char, count = n }
    end
  end
  table.sort(detail, function(a, b) return a.count > b.count end)
  return total, detail
end

local function itemNameOf(inv, id)
  local name = inv.names and inv.names[id]
  if not name then name = U.GetItemInfo(id) end
  return name
end

-- Quantité possédée d'un objet désigné seulement par son nom (besoin tapé au clavier).
function Craft:OwnedCountByName(name)
  local want = U.Fold(name or "")
  local total, detail = 0, {}
  if want == "" then return total, detail end
  for char, inv in pairs(ns.db.inv) do
    local n = 0
    for _, place in ipairs({ inv.bags or {}, inv.bank or {} }) do
      for id, count in pairs(place) do
        local itemName = itemNameOf(inv, id)
        if itemName and U.Fold(itemName) == want then n = n + count end
      end
    end
    if n > 0 then
      total = total + n
      detail[#detail + 1] = { name = char, count = n }
    end
  end
  table.sort(detail, function(a, b) return a.count > b.count end)
  return total, detail
end

-- Quantité possédée pour un besoin (objet précis ou nom tapé).
function Craft:OwnedFor(need)
  if need.i then return self:OwnedCount(need.i) end
  return self:OwnedCountByName(need.s)
end

-- Clé d'un besoin : l'identifiant de l'objet, ou « s:nom » quand il a été tapé au clavier.
function Craft.NeedKey(need)
  if need.i then return need.i end
  return "s:" .. U.Fold(need.s or "")
end

-- Tous les objets dont KEK connaît le nom : sacs et banques de tes persos, recettes et besoins de la bande.
function Craft:KnownItems()
  local index = {}
  local function add(id, name, link)
    if type(name) ~= "string" or name == "" then return end
    local k = U.Fold(name)
    local e = index[k]
    if not e then
      index[k] = { id = id ~= 0 and id or nil, name = name, link = link }
    elseif not e.id and id and id ~= 0 then
      e.id, e.link = id, e.link or link
    end
  end
  for _, inv in pairs(ns.db.inv) do
    for id, name in pairs(inv.names or {}) do add(id, name) end
  end
  for _, data in pairs(ns.db.recipes) do
    for _, entry in pairs(type(data.p) == "table" and data.p or {}) do
      for name, id in pairs(entry.l or {}) do add(id, name) end
    end
  end
  for _, data in pairs(ns.db.needs) do
    for _, need in ipairs(type(data.l) == "table" and data.l or {}) do add(need.i, need.s or U.ItemName(need.k), need.k) end
  end
  for _, rec in pairs(ns.db.reagents or {}) do
    for _, r in ipairs(rec.l or {}) do add(r.i, r.s or (r.i and U.GetItemInfo(r.i))) end
  end
  return index
end

-- Suggestions pour un nom tapé (les noms qui commencent par le texte d'abord), dont les recettes
-- dont KEK connaît les composants (« Composants : … »).
function Craft:Suggest(text, limit)
  local q = U.Fold(text or "")
  local out = {}
  if #q < 3 then return out end
  for k, e in pairs(self:KnownItems()) do
    local at = k:find(q, 1, true)
    if at then out[#out + 1] = { e = e, score = (at == 1 and 0 or 1), k = k } end
  end
  for name in pairs(ns.db.reagents or {}) do
    local k = U.Fold(name)
    local at = k:find(q, 1, true)
    if at then out[#out + 1] = { e = { recipe = name, name = name }, score = (at == 1 and 0 or 1) - 0.5, k = k } end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score < b.score end
    return a.k < b.k
  end)
  local list = {}
  for i = 1, math.min(limit or 6, #out) do list[i] = out[i].e end
  return list
end

-- Lien, identifiant ou nom tapé -> identifiant (si connu), lien, nom affiché.
function Craft:Resolve(input)
  if type(input) == "number" then
    local name, link = U.GetItemInfo(input)
    return input, link, name
  end
  if type(input) == "table" and input.id then             -- { id, name } : objet pas encore dans le cache du jeu
    local name, link = U.GetItemInfo(input.id)
    return input.id, link, name or input.name
  end
  if type(input) ~= "string" then return nil end
  local id = U.ItemID(input)
  if id then
    local link = input:find("|H", 1, true) and input or select(2, U.GetItemInfo(id))
    return id, link, U.ItemName(link) or U.GetItemInfo(id)
  end
  local name = input:match("^%s*(.-)%s*$")
  if name == "" then return nil end
  local ok, cachedName, cachedLink = pcall(U.GetItemInfo, name)   -- objet présent dans le cache du jeu
  if ok and cachedLink then return U.ItemID(cachedLink), cachedLink, cachedName end
  local known = self:KnownItems()[U.Fold(name)]
  if known then return known.id, known.link, known.name end
  return nil, nil, (name:gsub("^%l", string.upper))
end

-- Qui sait fabriquer l'objet d'un besoin (par identifiant, ou par nom de recette).
function Craft:CraftersFor(need)
  local out, seen = {}, {}
  for _, c in ipairs(self:CraftersOf(need.i)) do
    seen[c.name] = true
    out[#out + 1] = c
  end
  local want = need.s and U.Fold(need.s)
  if want and want ~= "" then
    for who, data in pairs(ns.db.recipes) do
      if not seen[who] and ns.db.members[who] and type(data.p) == "table" then
        for prof, entry in pairs(data.p) do
          for name in pairs(entry.l or {}) do
            if U.Fold(name) == want then
              out[#out + 1] = { name = who, prof = prof, rank = entry.r or 0 }
              seen[who] = true
              break
            end
          end
          if seen[who] then break end
        end
      end
    end
  end
  return out
end

function Craft:InventoryChanged()
  ns:Debounce("craft-have", 8, function() self:AnswerAll() end)
end

-- ------------------------------------------------------------------ besoins
local function ownNeeds()
  local n = ns.db.needs[ns.me]
  if not n then
    n = { l = {} }
    ns.db.needs[ns.me] = n
  end
  return n
end

-- ------------------------------------------------------------------ composants des recettes
function Craft:ReagentsFor(recipe)
  local rec = type(recipe) == "string" and ns.db.reagents and ns.db.reagents[recipe]
  return rec and rec.l or nil
end

function Craft:ReagentName(r)
  return r.s or (r.i and U.GetItemInfo(r.i)) or ("#" .. tostring(r.i or "?"))
end

-- Recette dont KEK connaît les composants, retrouvée par son nom (accents et majuscules ignorés).
function Craft:FindRecipe(text)
  local want = U.Fold((text or ""):match("^%s*(.-)%s*$"))
  if want == "" then return nil end
  local partial
  for name in pairs(ns.db.reagents or {}) do
    local k = U.Fold(name)
    if k == want then return name end
    if k:find(want, 1, true) then partial = partial and false or name end
  end
  return partial or nil
end

function Craft:FindOwnNeed(key)
  for _, need in ipairs(ownNeeds().l) do
    if Craft.NeedKey(need) == key then return need end
  end
end

function Craft:SetNeedQty(key, qty)
  local need = self:FindOwnNeed(key)
  if not need then return false end
  need.q = math.max(1, math.floor(tonumber(qty) or 1))
  self:NeedsChanged()
  return true
end

-- Ajoute à tes besoins ce qui te manque pour fabriquer « crafts » fois une recette
-- (en comptant ce que tu as déjà sur tous tes persos). Une seule notification pour toute la liste.
function Craft:AddReagentNeeds(recipe, crafts)
  local list = self:ReagentsFor(recipe)
  if not list then return nil end
  crafts = math.max(1, math.floor(tonumber(crafts) or 1))
  local note = crafts > 1 and string.format(L["pour %d × %s"], crafts, recipe) or string.format(L["pour %s"], recipe)
  local added, complete = {}, {}
  for _, r in ipairs(list) do
    local probe = { i = r.i, s = self:ReagentName(r) }
    local missing = (r.q or 1) * crafts - self:OwnedFor(probe)
    if missing > 0 then
      local existing = self:FindOwnNeed(Craft.NeedKey(probe))
      if existing then
        existing.q = math.max(existing.q or 1, missing)
        existing.n = existing.n or note
        added[#added + 1] = { i = existing.i, s = existing.s or probe.s, q = existing.q }
      else
        local link = r.i and select(2, U.GetItemInfo(r.i)) or nil
        local ok, entry = self:AddNeed(link or (r.i and { id = r.i, name = probe.s }) or probe.s, missing, note, true)
        if ok and entry then added[#added + 1] = { i = entry.i, s = entry.s or probe.s, q = entry.q } end
      end
    else
      complete[#complete + 1] = probe.s
    end
  end
  if #added > 0 then
    self:NeedsChanged()
    if ns.Alerts then ns.Alerts:Emit("need", { m = added, r = recipe, c = crafts > 1 and crafts or nil }) end
  end
  return added, complete
end

-- input : lien d'objet, identifiant, ou simple nom tapé au clavier (« Viande de coyote »).
-- Un nouveau besoin est annoncé à la bande par une notification.
function Craft:AddNeed(input, qty, note, silent)
  local id, link, name = self:Resolve(input)
  if not id and not name then return false end
  qty = math.max(1, math.floor(tonumber(qty) or 1))
  note = (type(note) == "string" and note:match("^%s*(.-)%s*$")) or ""
  local fresh = { i = id, k = link, s = name, q = qty, n = note ~= "" and note or nil, t = ns.Now() }
  local key = Craft.NeedKey(fresh)
  local needs = ownNeeds()
  for _, need in ipairs(needs.l) do
    if Craft.NeedKey(need) == key then
      need.q = qty
      need.n = fresh.n or need.n
      need.k, need.s = need.k or link, need.s or name
      self:NeedsChanged()
      return true, need, false
    end
  end
  table.insert(needs.l, 1, fresh)
  self:NeedsChanged()
  if ns.Alerts and not silent then ns.Alerts:Emit("need", { i = id, lk = link, s = name, q = qty, n = fresh.n }) end
  return true, fresh, true
end

function Craft:RemoveNeed(key)
  local needs = ownNeeds()
  for i, need in ipairs(needs.l) do
    if Craft.NeedKey(need) == key then table.remove(needs.l, i) break end
  end
  if ns.db.have[ns.me] then ns.db.have[ns.me][key] = nil end
  self:NeedsChanged()
end

function Craft:NeedsChanged()
  ownNeeds().h = nil
  ns:Fire("DATA", "needs")
  ns:Debounce("craft-push-n", 2, function() ns.Sync:Push("n") end)
end

function Craft:NeedsHash()
  local needs = ownNeeds()
  if not needs.h then
    local parts = {}
    for _, need in ipairs(needs.l) do parts[#parts + 1] = tostring(Craft.NeedKey(need)) .. "x" .. need.q .. (need.n or "") end
    needs.h = U.Hash(table.concat(parts, ","))
  end
  return needs.h
end

-- Toutes les demandes de la bande, les miennes d'abord.
function Craft:AllNeeds()
  local out = {}
  for owner, data in pairs(ns.db.needs) do
    if ns.db.members[owner] and type(data.l) == "table" then
      for _, need in ipairs(data.l) do
        out[#out + 1] = { owner = owner, need = need, mine = owner == ns.me }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.mine ~= b.mine then return a.mine end
    return (a.need.t or 0) > (b.need.t or 0)
  end)
  return out
end

-- Qui possède l'objet demandé (réponses « V » des autres + mes propres personnages).
function Craft:Holders(owner, need)
  if type(need) ~= "table" then need = { i = need } end
  local out = {}
  local key = Craft.NeedKey(need)
  local perItem = ns.db.have[owner] and ns.db.have[owner][key]
  if perItem then
    for holder, count in pairs(perItem) do
      if count > 0 and holder ~= ns.me and ns.db.members[holder] then out[#out + 1] = { name = holder, count = count } end
    end
  end
  local mine = self:OwnedFor(need)
  if mine > 0 and owner ~= ns.me then
    out[#out + 1] = { name = ns.me, count = mine, mine = true }
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out
end

-- Réponds aux besoins d'un membre avec ce que j'ai.
Craft.lastAnswer = {}
function Craft:Answer(owner)
  if owner == ns.me then return end
  local data = ns.db.needs[owner]
  if not data or type(data.l) ~= "table" then return end
  local counts, changed = {}, false
  local last = self.lastAnswer[owner] or {}
  for _, need in ipairs(data.l) do
    local key = Craft.NeedKey(need)
    local n = self:OwnedFor(need)
    counts[key] = n
    if (last[key] or 0) ~= n then changed = true end
  end
  for id in pairs(last) do if counts[id] == nil then changed = true end end
  if not changed then return end
  self.lastAnswer[owner] = counts
  ns.Comm:Send("V", { o = owner, c = counts }, 2)
end

function Craft:AnswerAll()
  for owner in pairs(ns.db.needs) do
    if owner ~= ns.me and ns.db.members[owner] then self:Answer(owner) end
  end
end

-- ------------------------------------------------------------------ démarrage
function Craft:OnLogin()
  ns:RegisterEvent("TRADE_SKILL_SHOW", function() C_Timer.After(0.3, function() self:ScanTradeSkill() end) end)
  ns:RegisterEvent("TRADE_SKILL_UPDATE", function() ns:Debounce("craft-ts", 1, function() self:ScanTradeSkill() end) end)
  for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    ns:RegisterEvent(event, function() ns:Debounce("craft-ts", 1, function() self:ScanTradeSkill() end) end)
  end
  ns:RegisterEvent("CRAFT_SHOW", function() C_Timer.After(0.3, function() self:ScanCraft() end) end)
  ns:RegisterEvent("CRAFT_UPDATE", function() ns:Debounce("craft-cr", 1, function() self:ScanCraft() end) end)
  ns:RegisterEvent("SKILL_LINES_CHANGED", function() ns:Debounce("craft-skills", 5, function() self:SyncProfessions() end) end)

  ns:RegisterEvent("BAG_UPDATE_DELAYED", function() ns:Debounce("craft-bags", 2, function() self:ScanBags() end) end)
  ns:RegisterEvent("BANKFRAME_OPENED", function() self.bankOpen = true; self:ScanBank() end)
  ns:RegisterEvent("BANKFRAME_CLOSED", function() self.bankOpen = false end)
  ns:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() ns:Debounce("craft-bank", 1, function() self:ScanBank() end) end)
  ns:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", function() ns:Debounce("craft-bank", 1, function() self:ScanBank() end) end)
  C_Timer.After(3, function() self:ScanBags(); self:SyncProfessions() end)

  ns:On("MSG_V", function(sender, data)
    if type(data) == "table" and type(data.o) == "string" then data.o = U.FullName(data.o) end
    if type(data) ~= "table" or type(data.c) ~= "table" or data.o ~= ns.me and not ns.db.needs[data.o] then return end
    local owner = data.o
    local have = ns.db.have[owner]
    if not have then have = {}; ns.db.have[owner] = have end
    for _, perItem in pairs(have) do perItem[sender] = nil end
    for id, count in pairs(data.c) do
      id = tonumber(id) or (type(id) == "string" and id:sub(1, 2) == "s:" and id) or nil
      if id and type(count) == "number" and count > 0 then
        have[id] = have[id] or {}
        have[id][sender] = count
      end
    end
    ns:Fire("DATA", "needs")
  end)

  ns.Sync:Dataset("r", {
    prio = 3,
    ownHash = function() return self:RecipeHash() end,
    knownHash = function(sender) return ns.Sync:StoredHash(sender, "r") end,
    build = function() return self:EncodeRecipes() end,
    apply = function(sender, payload, hash)
      if type(payload) ~= "table" then return end
      local p, reagents = self:DecodeRecipes(payload)
      ns.db.recipes[sender] = { p = p }
      self:MergeReagents(sender, reagents)
      ns.Sync:StoreHash(sender, "r", hash)
    end,
  })

  ns.Sync:Dataset("n", {
    prio = 2,
    ownHash = function() return self:NeedsHash() end,
    knownHash = function(sender) return ns.Sync:StoredHash(sender, "n") end,
    build = function() return ownNeeds().l end,
    apply = function(sender, payload, hash)
      if type(payload) ~= "table" then return end
      local clean = {}
      for _, need in ipairs(payload) do
        if type(need) == "table" and (tonumber(need.i) or (type(need.s) == "string" and need.s ~= "")) then
          clean[#clean + 1] = need
        end
      end
      ns.db.needs[sender] = { l = clean }
      ns.Sync:StoreHash(sender, "n", hash)
      C_Timer.After(1 + math.random() * 2, function() self:Answer(sender) end)
    end,
  })
end
