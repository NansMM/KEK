-- KEK — autotest : vérifie en jeu ce qu'on ne peut pas voir hors du jeu (API disponibles, messages,
-- motifs du chat, réglages…) et affiche un rapport à copier-coller pour corriger l'addon.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local Autotest = {}
ns.Autotest = Autotest

local MARK = { ok = "[OK]", warn = "[!] ", fail = "[X] ", info = "[i] " }
local COLOR = { ok = "ff61db8f", warn = "ffffcc59", fail = "fff56161", info = "ff66adff" }

-- ------------------------------------------------------------------ vérifications
local function yes(v) return v and L["oui"] or L["non"] end

local function sample(fmt, ...)
  if type(fmt) ~= "string" then return nil end
  local ok, text = pcall(string.format, (fmt:gsub("%%%d%$", "%%")), ...)
  return ok and text or nil
end

local CHECKS = {}
local function add(label, fn) CHECKS[#CHECKS + 1] = { label = label, fn = fn } end

add(L["Fichier .toc"], function()
  local _, _, _, toc = GetBuildInfo()
  local read = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  -- les clients récents peuvent refuser de lire ce champ : ce n'est pas un problème
  local okRead, declared = false, nil
  if read then okRead, declared = pcall(read, "KEK", "Interface") end
  if not okRead or type(declared) ~= "string" or declared == "" then
    declared = "16001, 11508, 11507"   -- copie de la ligne ## Interface de KEK.toc
  end
  if not toc then return "info", L["numéro d'interface inconnu"] end
  if type(declared) == "string" and declared ~= "" then
    for n in declared:gmatch("%d+") do
      if tonumber(n) == toc then return "ok", string.format(L["interface %d bien déclarée"], toc) end
    end
    return "warn", string.format(L["le jeu attend %d, KEK.toc déclare %s"], toc, declared)
  end
  return "info", string.format(L["le jeu attend %d"], toc)
end)

add(L["Messages d'addon"], function()
  local CI = C_ChatInfo
  if not (CI and CI.SendAddonMessage) and not SendAddonMessage then return "fail", L["SendAddonMessage introuvable"] end
  local registered = CI and CI.IsAddonMessagePrefixRegistered and CI.IsAddonMessagePrefixRegistered("KEK")
  local lockFn = CI and CI.InChatMessagingLockdown
  local locked = ns.Comm:Locked()
  local enum = Enum and Enum.SendAddonMessageResult
  return registered == false and "fail" or "ok", string.format(L["préfixe enregistré : %s · verrou de donjon : %s (%s) · codes de retour : %s"],
    registered == nil and "?" or yes(registered), yes(locked), lockFn and L["fonction du jeu"] or L["déduit"],
    enum and string.format("verrou=%s, hors ligne=%s", tostring(enum.AddOnMessageLockdown), tostring(enum.TargetOffline)) or L["absents"])
end)

add(L["Bande"], function()
  local Comm, Store = ns.Comm, ns.Store
  local code = Comm:Code()
  local who = code ~= "" and string.format(L["code « %s »"], code) or (Comm:IsGuildBand() and L["guilde"] or L["aucune"])
  local queued = #Comm.queue[1] + #Comm.queue[2] + #Comm.queue[3]
  local status = Comm.mode == "ready" and "ok" or (Comm.mode == "none" and "warn" or "info")
  local detail = string.format(L["%s · mode %s · %d membre(s) connu(s), %d en ligne · file %d · dernière erreur %s"],
    who, Comm.mode, U.Count(ns.db.members) - 1, Store:OnlineCount(), queued, tostring(Comm.lastError or L["aucune"]))
  if Comm.mode == "none" then
    detail = detail .. L[" → entre le même code que tes amis (Réglages > Ta bande)"]
  end
  return status, detail
end)

add(L["Amis"], function()
  local friends = ns.Comm:OnlineFriends()
  local names = {}
  for i = 1, math.min(6, #friends) do
    names[i] = friends[i] .. (ns.Comm.bnIds[friends[i]] and " (BN)" or "")
  end
  local bn = (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendGameAccountInfo) and L["présente"] or L["absente"]
  return "info", string.format(L["%d perso(s) ami(s) en ligne : %s · API Battle.net %s, envoi Battle.net %s"], #friends,
    #names > 0 and table.concat(names, ", ") or "—", bn, ns.Comm:HasBN() and L["possible"] or L["absent"])
end)

local PING_STATE = {
  sent = L["pas de réponse"], ok = L["a répondu"], notfound = L["introuvable"], otherband = L["a KEK avec un autre code"],
}

add(L["Amis sondés"], function()
  local list, any, bad = {}, false, false
  for name, log in pairs(ns.Comm.pingLog) do
    list[#list + 1] = string.format("%s (%s)", name, PING_STATE[log.state] or log.state)
    any = any or log.state == "ok"
    bad = bad or log.state == "notfound" or log.state == "otherband"
  end
  table.sort(list)
  if #list == 0 then return "info", L["aucun pour l'instant"] end
  return any and "ok" or (bad and "warn" or "info"), table.concat(list, ", ")
end)

add(L["Présence lue dans le jeu"], function()
  local P = ns.Presence
  local seen = P:Collect()
  local list = {}
  for name, g in pairs(seen) do
    local bits = { g.on and L["connecté"] or L["déconnecté"] }
    if g.level then bits[#bits + 1] = string.format(L["niv. %d"], g.level) end
    if g.zone then bits[#bits + 1] = g.zone end
    list[#list + 1] = string.format("%s (%s, %s)", U.Short(name), g.src, table.concat(bits, " · "))
  end
  table.sort(list)
  local s = P.stats
  local sources = string.format(L["amis %d · Battle.net %d · guilde %d · groupe %d"], s.friend, s.bnet, s.guild, s.group)
  if #list == 0 then
    return "info", sources .. " · " .. L["aucun membre de la bande dans tes amis, ta guilde ou ton groupe : KEK se fie à ses seuls messages"]
  end
  return "ok", sources .. " · " .. table.concat(list, ", ")
end)

add(L["Objets LQE"], function()
  local B = ns.Boe
  -- le jeu dit-il comment un objet se lie ? (14e valeur de GetItemInfo)
  local tested, bindRead = 0, false
  local CC = C_Container
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local slots = CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = CC.GetContainerItemInfo and CC.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink and tested < 30 then
        tested = tested + 1
        if select(14, U.GetItemInfo(info.hyperlink)) ~= nil then bindRead = true end
      end
    end
  end
  local mine = ns.db.boe and ns.db.boe[ns.me] or {}
  local profile, auto = B:MyProfile()
  local _, specIndex = B:DetectedProfile()
  local gearKnown = 0
  for name in pairs(ns.db.gear or {}) do
    if name ~= ns.me and ns.db.members[name] then gearKnown = gearKnown + 1 end
  end
  local parts = {
    string.format(L["profil : %s (%s)"], B.PROFILE_NAMES[profile] or profile,
      auto and string.format(L["auto, branche %s"], tostring(specIndex or "?")) or L["choisi"]),
    string.format(L["équipement connu de %d membre(s)"], gearKnown),
    string.format(L["liaison lue : %s"], tested == 0 and L["sacs vides"] or yes(bindRead)),
    string.format(L["%d dans tes sacs"], #(mine.b or {})),
    mine.k and string.format(L["%d en banque"], #mine.k) or L["banque pas encore ouverte"],
    string.format(L["banque de guilde : %s"], B:HasGuildBank() and L["fonctions présentes"] or L["absente de ce client"]),
    string.format(L["caractéristiques : %s"], yes((C_Item and C_Item.GetItemStats) or GetItemStats)),
    string.format(L["infobulles : %s"], yes(C_TooltipInfo and C_TooltipInfo.GetHyperlink)),
    string.format(L["%d objet(s) de la bande pour toi"], B:ForMe()),
  }
  local status = (tested == 0 and "info") or (bindRead and "ok") or "warn"
  if status == "warn" then parts[#parts + 1] = L["le jeu ne dit pas comment les objets se lient : le Coffre restera vide"] end
  return status, table.concat(parts, " · ")
end)

add(L["Messages de KEK"], function()
  local st = ns.Comm.stats
  local sent = {}
  for dist, n in pairs(st.sent) do sent[#sent + 1] = dist .. " " .. n end
  table.sort(sent)
  local last = ""
  if st.from then
    -- nom tel que le jeu l'envoie, avec le code des caractères qui ne sont pas des lettres simples
    local codes = {}
    for ch in tostring(st.rawFrom):gmatch("[^%w\128-\255]") do codes[#codes + 1] = string.format("0x%02X", ch:byte()) end
    for seq in tostring(st.rawFrom):gmatch("[\194\226][\128-\191]+") do
      local bytes = {}
      for i = 1, #seq do bytes[i] = string.format("%02X", seq:byte(i)) end
      codes[#codes + 1] = table.concat(bytes)
    end
    last = string.format(L[" (dernier : %s via %s, nom brut « %s »%s)"], st.from, tostring(st.fromDist), tostring(st.rawFrom),
      #codes > 0 and (" " .. table.concat(codes, " ")) or "")
  end
  local old = st.oldFrom and string.format(L[" (de %s, version %s)"], st.oldFrom, tostring(st.oldV)) or ""
  return "info", string.format(L["envoyés : %s · refusés %d · reçus %d%s · ignorés : autre code %d, ancienne version %d%s, sans bande %d · Battle.net reçus %d"],
    #sent > 0 and table.concat(sent, ", ") or "0", st.refused, st.recv, last, st.otherBand, st.oldVersion, old, st.noBand, st.bnRecv or 0)
end)

add(L["Menu Options"], function()
  local O = ns.Options
  if O.category and not O.simple then return "ok", L["page native dans Options > AddOns"] end
  if O.simple then return "warn", string.format(L["page simple (repli) : %s"], tostring(O.nativeError or L["API Settings absente"]):sub(1, 90)) end
  return "fail", tostring(O.simpleError or L["aucune page créée"]):sub(1, 90)
end)

add(L["Menu des addons"], function()
  return AddonCompartmentFrame and "ok" or "info", AddonCompartmentFrame and L["présent (KEK y est inscrit)"] or L["absent dans ce client"]
end)

add(L["Bouton de minicarte"], function()
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not icon then return "fail", L["LibDBIcon non chargée"] end
  local _, minor = LibStub("LibDBIcon-1.0")
  local button = icon:GetMinimapButton("KEK")
  if not button then return "fail", string.format(L["LibDBIcon v%s chargée, mais bouton absent"], tostring(minor)) end
  return "ok", string.format(L["LibDBIcon v%s · %s"], tostring(minor), button:IsShown() and L["affiché"] or L["masqué"])
end)

add(L["Objets et sacs"], function()
  local source = (C_Item and C_Item.GetItemInfo) and "C_Item.GetItemInfo" or (GetItemInfo and "GetItemInfo" or nil)
  if not source then return "fail", L["aucune fonction GetItemInfo"] end
  local n = 0
  for _ in pairs(ns.Alerts:Holdings()) do n = n + 1 end
  return n > 0 and "ok" or "warn", string.format(L["%s · %d objet(s) différent(s) lus dans les sacs et l'équipement"], source, n)
end)

add(L["Fonctions du chat"], function()
  local filter = (ChatFrame_AddMessageEventFilter and "ChatFrame_AddMessageEventFilter") or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter and "ChatFrameUtil") or nil
  local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
  local link = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
  local hooks = U.HookInsertLink()
  local followed = hooks.ChatFrameUtil and "ChatFrameUtil.InsertLink" or (hooks.ChatEdit and "ChatEdit_InsertLink") or L["non"]
  local status = (filter and open and link and (hooks.ChatFrameUtil or hooks.ChatEdit)) and "ok" or "warn"
  return status, string.format(L["filtre : %s · ouvrir : %s · insérer un lien : %s · Maj+clic suivi : %s"], filter or L["absent"], yes(open), yes(link), followed)
end)

add(L["Motif « joueur introuvable »"], function()
  local text = sample(ERR_CHAT_PLAYER_NOT_FOUND_S, "Testeur")
  local pattern = ns.Comm:NotFoundPattern()
  if not text or not pattern then return "warn", L["texte du jeu absent : les sondages hors ligne s'afficheront dans le chat"] end
  return text:match(pattern) == "Testeur" and "ok" or "fail", "« " .. text .. " »"
end)

add(L["Motif « ennemi tué »"], function()
  local text = sample(COMBATLOG_XPGAIN_FIRSTPERSON, "Sanglier", 45)
  local pattern = ns.Session.killPattern
  if not text or not pattern then return "warn", L["texte du jeu absent : les ennemis ne seront pas comptés"] end
  return text:find(pattern) and "ok" or "fail", "« " .. text .. " »"
end)

add(L["Motif « palier de métier »"], function()
  local text = sample(SKILL_RANK_UP, "Couture", 75)
  local pattern = ns.Alerts.skillPattern
  if not text or not pattern then return "warn", L["texte du jeu absent : paliers de métier non détectés"] end
  local skill, rank = text:match(pattern)
  return (skill == "Couture" and tonumber(rank) == 75) and "ok" or "fail", "« " .. text .. " »"
end)

add(L["Temps de jeu"], function()
  local played = ns.Race:Played()
  if not played then return "warn", L["pas encore reçu (réessaie dans quelques secondes)"] end
  return "ok", U.Played(played)
end)

add(L["Talents"], function()
  local level = UnitLevel("player") or 0
  local api
  if GetNumTalentTabs then
    local ok, n = pcall(GetNumTalentTabs)
    api = string.format("GetNumTalentTabs = %s", ok and tostring(n) or L["erreur"])
  elseif (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization then
    api = L["spécialisations (interface récente)"]
  else
    api = L["aucune API de talents"]
  end
  local spec = ns.Profile:ReadSpec()
  local name, _, points, total = ns.Profile.SpecSummary(spec)
  if name then
    return "ok", string.format(L["%s · %s%s · niveau %d"], api, name, (points and points ~= "") and (" (" .. points .. ")") or "", level)
  end
  local read = type(spec) == "table" and #spec or 0
  if level < 10 then
    return "info", string.format(L["%s · %d arbre(s) lu(s), pas encore de points (niveau %d)"], api, read, level)
  end
  return "warn", string.format(L["%s · %d arbre(s) lu(s), %d point(s) dépensé(s) · niveau %d"], api, read, total or 0, level)
end)

add(L["Métiers"], function()
  local api, headers = nil, {}
  if GetNumSkillLines then
    local n = GetNumSkillLines() or 0
    for i = 1, n do
      local lineName, isHeader = GetSkillLineInfo(i)
      if isHeader and lineName then headers[#headers + 1] = lineName end
    end
    api = string.format(L["lignes de compétence (%d)"], n)
  elseif GetProfessions then
    api = "GetProfessions"
  else
    api = L["aucune API de métiers"]
  end
  local list = ns.Profile:ReadProfs() or {}
  if #list > 0 then
    local names = {}
    for _, p in ipairs(list) do names[#names + 1] = string.format("%s %d", p.n, p.r or 0) end
    return "ok", string.format("%s · %s", api, table.concat(names, ", "))
  end
  local seen = #headers > 0 and (L[" · en-têtes vus : "] .. table.concat(headers, ", ")) or ""
  return "warn", string.format(L["%s · aucun métier trouvé (aucun appris ?)%s"], api, seen)
end)

add(L["Recettes"], function()
  local own = ns.db.recipes[ns.me]
  local n, profs = 0, {}
  for prof, entry in pairs(own and own.p or {}) do
    local c = U.Count(entry.l or {})
    n = n + c
    profs[#profs + 1] = prof .. " " .. c
  end
  table.sort(profs)
  local api = (GetNumTradeSkills and "GetNumTradeSkills") or ((C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) and "C_TradeSkillUI") or L["aucune API"]
  -- dernière lecture d'une fenêtre de métier pendant cette session
  local scan = ns.Craft.lastScan
  local last
  if not scan then
    last = L["aucune fenêtre de métier lue depuis la connexion"]
  else
    last = string.format(L["dernière lecture %s : %s %s/%s, %s recette(s), %s apprise(s), composants pour %s"],
      U.Ago(scan.t), tostring(scan.prof or "?"), tostring(scan.rank or "?"), tostring(scan.max or "?"),
      tostring(scan.total or "?"), tostring(scan.learned or scan.total or "?"), tostring(scan.reagents or "?"))
    if scan.why then last = last .. " · " .. scan.why end
    if scan.info and scan.info ~= "" then last = last .. " · " .. scan.info end
  end
  if n == 0 then
    local status = (scan and scan.why) and "warn" or "info"
    return status, string.format(L["%s · aucune recette mémorisée · %s"], api, last)
  end
  local own, received = ns.Craft:ReagentCounts()
  local known = tostring(own)
  if received > 0 then known = known .. string.format(L[", et %d reçue(s) de la bande"], received) end
  return "ok", string.format(L["%s · %d recette(s) (%s) · composants connus pour %s · %s"], api, n, table.concat(profs, ", "),
    known, last)
end)

add(L["Morts (sans journal de combat)"], function()
  local fall, breath = IsFalling ~= nil, GetMirrorTimerProgress ~= nil
  return (fall and breath) and "ok" or "warn", string.format(L["chute : %s · respiration : %s · valeurs secrètes : %s"], yes(fall), yes(breath), yes(U.RESTRICTED))
end)

add(L["Polices"], function()
  local probe = UIParent:CreateFontString(nil, "OVERLAY")
  local loaded, total = 0, 0
  for _, path in pairs(UI.T.font) do
    total = total + 1
    if probe:SetFont(path, 12, "") ~= false then loaded = loaded + 1 end
  end
  probe:Hide()
  return loaded == total and "ok" or "warn", string.format(L["%d/%d chargée(s)"], loaded, total)
end)

add(L["Actions bloquées par le jeu"], function()
  local diag = ns.db.diag or {}
  if #diag == 0 then return "ok", L["aucune"] end
  local names = {}
  for i = 1, math.min(3, #diag) do names[#names + 1] = tostring(diag[i].f) end
  return "fail", string.format(L["%d enregistrée(s) : %s"], #diag, table.concat(names, ", "))
end)

add(L["Noms en double"], function()
  local repaired = ns.Store.repaired
  local seen, dup = {}, {}
  for name in pairs(ns.db.members) do
    local fixed = U.FullName(name)
    if seen[fixed] then dup[#dup + 1] = fixed end
    seen[fixed] = true
  end
  if #dup > 0 then return "fail", table.concat(dup, ", ") end
  if repaired then return "ok", string.format(L["aucun (%d nom(s) réparé(s) au démarrage)"], repaired) end
  return "ok", L["aucun"]
end)

add(L["Erreurs Lua de KEK"], function()
  if (ns.errorCount or 0) == 0 then return "ok", L["aucune pendant cette session"] end
  return "fail", string.format(L["%d · dernière : %s"], ns.errorCount, tostring(ns.lastError):gsub("[\r\n]+", " "):sub(1, 140))
end)

-- ------------------------------------------------------------------ exécution
function Autotest:Run()
  if self.running then return end
  self.running = true
  local results = {}
  for _, check in ipairs(CHECKS) do
    local ok, status, detail = pcall(check.fn)
    if not ok then status, detail = "fail", L["erreur : "] .. tostring(status) end
    results[#results + 1] = { label = check.label, status = status or "info", detail = detail or "" }
  end

  -- messages : à soi-même (le jeu les renvoie-t-il ?) et aller-retour avec les amis connectés
  local probes = {}
  if ns.Comm:Locked() then
    results[#results + 1] = { label = L["Message à soi-même"], status = "info", detail = L["impossible en donjon : relance l'autotest dehors"] }
  else
    probes[#probes + 1] = { label = L["Chuchotement à soi-même"], dist = "WHISPER", target = U.Short(ns.me), kind = "s", self = true }
    if IsInGuild() then probes[#probes + 1] = { label = L["Message de guilde"], dist = "GUILD", kind = "s", guild = true } end
    local group = ns.Comm:GroupChannel()
    if group then probes[#probes + 1] = { label = L["Message de groupe"], dist = group, kind = "s" } end
    -- amis à tester : ceux de la bande en ligne, sinon les amis en ligne (ceux qui ont KEK répondent,
    -- même avec un autre code : on vérifie ainsi que les messages passent entre vous)
    local friends, fromBand = {}, true
    for name in pairs(ns.Store.online) do
      if name ~= ns.me and ns.db.members[name] then friends[#friends + 1] = name end
    end
    if #friends == 0 then
      fromBand = false
      for _, name in ipairs(ns.Comm:OnlineFriends()) do
        if not ns.Comm:IsOwnCharacter(name) then friends[#friends + 1] = name end
      end
    end
    table.sort(friends)
    for i = 1, math.min(4, #friends) do
      local name = friends[i]
      probes[#probes + 1] = { label = string.format(L["Liaison avec %s"], U.Short(name)), dist = "WHISPER",
        target = ns.Comm:WhisperTarget(name), kind = "p", ping = true }
      local id = ns.Comm.bnIds[name]
      if id and ns.Comm:HasBN() then
        probes[#probes + 1] = { label = string.format(L["Liaison Battle.net avec %s"], U.Short(name)), bn = id, ping = true }
      end
    end
    if #friends == 0 then
      results[#results + 1] = { label = L["Liaison avec un ami"], status = "info",
        detail = L["aucun ami en ligne : relance l'autotest quand un ami avec KEK est connecté"] }
    elseif not fromBand then
      results[#results + 1] = { label = L["Liaison avec un ami"], status = "info",
        detail = L["personne de la bande en ligne : test avec tes amis en ligne (seuls ceux qui ont KEK 1.5.2 ou plus répondent)"] }
    end
  end
  local pending = #probes
  local function finish()
    -- si un ami répond, les chuchotements marchent : l'absence d'écho vers soi-même n'est pas un problème
    local pingOk = false
    for _, r in ipairs(results) do if r.ping and r.status == "ok" then pingOk = true end end
    for _, r in ipairs(results) do
      if r.guild then self:GuildVerdict(r) end
      if r.self and r.status ~= "ok" then
        if pingOk then
          r.status, r.detail = "info", L["pas d'écho vers soi-même (normal ici) : les chuchotements avec tes amis marchent"]
        else
          r.detail = r.detail .. L[" (le jeu ne renvoie peut-être pas les messages à soi-même : le vrai test se fait avec un ami)"]
        end
      end
    end
    self.running = false
    self:Report(results)
  end
  if pending == 0 then finish() return end
  for _, p in ipairs(probes) do
    local function done(ok, detail)
      if p.guild then ns.Comm:SetGuildEcho(ok) end
      results[#results + 1] = { label = p.label, status = ok and "ok" or "warn", detail = detail, self = p.self,
        ping = p.ping and not p.bn, guild = p.guild, echo = ok }
      pending = pending - 1
      if pending == 0 then finish() end
    end
    if p.bn then
      ns.Comm:ProbeBN(p.bn, done)
    else
      ns.Comm:Probe(p.dist, p.target, done, p.kind)
    end
  end
end

-- Message de guilde : l'écho, les messages de guilde reçus d'autres joueurs, et par où KEK passe.
function Autotest:GuildVerdict(r)
  local Comm = ns.Comm
  local from = {}
  for name in pairs(Comm.guildFrom) do from[#from + 1] = U.Short(name) end
  table.sort(from)
  local others = #from > 0 and string.format(L["messages de guilde reçus de : %s"], table.concat(from, ", ", 1, math.min(3, #from)))
    or L["aucun message de guilde reçu d'un autre joueur pour l'instant"]
  if r.echo then
    r.detail = r.detail .. " · " .. L["KEK passe par la guilde pour les membres de ta guilde"]
  elseif Comm:GuildWorks() then
    r.status = "info"
    r.detail = L["pas d'écho vers soi-même"] .. ", " .. others .. " · " .. L["la guilde transmet : KEK passe par elle"]
  elseif Comm:IsGuildBand() then
    r.status = "fail"
    r.detail = L["envoyé, mais rien ne revient et aucun message de guilde reçu"] .. " · "
      .. L["sans code, la bande de guilde ne peut pas marcher ici : choisissez un même code de bande entre amis"]
  else
    r.status = "info"
    r.detail = L["envoyé, mais pas reçu en retour"] .. " · " .. others .. " · "
      .. L["KEK parle aux membres de ta guilde par chuchotement (rien à faire)"]
  end
end

function Autotest:Report(results)
  local counts = { ok = 0, warn = 0, fail = 0, info = 0 }
  local _, build, _, toc = GetBuildInfo()
  local version = GetBuildInfo()
  local lines = {
    string.format("KEK %s · autotest du %s %s · %s", ns.VERSION, U.ShortDate(ns.Now()), U.Clock(ns.Now()), tostring(ns.me)),
    string.format(L["Jeu %s (%s) · interface %s · %s · projet %s"], tostring(version), tostring(build), tostring(toc),
      tostring(GetLocale and GetLocale() or "?"), tostring(WOW_PROJECT_ID or "?")),
    "",
  }
  for _, r in ipairs(results) do
    counts[r.status] = (counts[r.status] or 0) + 1
    lines[#lines + 1] = string.format("%s %s : %s", MARK[r.status] or "[?]", r.label, r.detail)
  end
  local summary = string.format(L["%d OK · %d à vérifier · %d problème(s)"], counts.ok, counts.warn, counts.fail)
  lines[#lines + 1] = ""
  lines[#lines + 1] = summary
  local text = table.concat(lines, "\n")
  ns.db.autotest = { t = ns.Now(), text = text }
  self.last = { text = text, summary = summary, counts = counts, results = results }

  local color = counts.fail > 0 and COLOR.fail or (counts.warn > 0 and COLOR.warn or COLOR.ok)
  ns.Print(string.format(L["autotest terminé : |c%s%s|r. Le rapport est ouvert : copie-le (Ctrl+C) pour le partager."], color, summary))
  self:Show(text, summary, counts)
end

-- ------------------------------------------------------------------ fenêtre du rapport
function Autotest:Build()
  local f = CreateFrame("Frame", "KEKAutotest", UIParent)
  f:SetSize(680, 600)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  UI.Shadow(f, 24, 0.6)
  UI.Round(f, 14, C.edge, "BACKGROUND", 0)
  UI.Round(f, 13, C.surface, "BACKGROUND", 1, 1)
  tinsert(UISpecialFrames, "KEKAutotest")

  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(UI.Media("logo"))
  logo:SetSize(32, 32)
  logo:SetPoint("TOPLEFT", 20, -18)
  f.title = UI.Title(f, 18)
  f.title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
  f.title:SetText(L["Autotest de KEK"])
  f.summary = UI.Text(f, 12, C.muted)
  f.summary:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  local close = UI.IconButton(f, "close", { size = 30, iconSize = 12, tooltip = L["Fermer (Échap)"], onClick = function() f:Hide() end })
  close:SetPoint("TOPRIGHT", -14, -14)

  local box = CreateFrame("Frame", nil, f)
  box:SetPoint("TOPLEFT", 16, -66)
  box:SetPoint("BOTTOMRIGHT", -16, 64)
  box:SetClipsChildren(true)
  UI.Round(box, 8, C.shell, "BACKGROUND", 0)
  local eb = CreateFrame("EditBox", nil, box)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFont(UI.T.font.body, 12, "")
  eb:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
  eb:SetPoint("TOPLEFT", 12, -10)
  eb:SetPoint("BOTTOMRIGHT", -12, 10)
  eb:SetMaxLetters(0)
  -- lecture seule : toute frappe remet le rapport
  eb:SetScript("OnTextChanged", function(self, user) if user and f.text then self:SetText(f.text); self:HighlightText() end end)
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  f.eb = eb
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() eb:SetFocus(); eb:HighlightText() end)

  local hint = UI.Text(f, 12, C.muted)
  hint:SetPoint("BOTTOMLEFT", 20, 26)
  hint:SetText(L["Le texte est sélectionné : Ctrl+C, puis colle-le à Claude."])
  local done = UI.Button(f, { text = L["Fermer"], style = "primary", h = 30, onClick = function() f:Hide() end })
  done:SetPoint("BOTTOMRIGHT", -16, 18)
  local again = UI.Button(f, { text = L["Relancer"], icon = "clock", style = "secondary", h = 30, onClick = function() Autotest:Run() end })
  again:SetPoint("RIGHT", done, "LEFT", -8, 0)
  local selectAll = UI.Button(f, { text = L["Tout sélectionner"], icon = "check", style = "secondary", h = 30, onClick = function() eb:SetFocus(); eb:HighlightText() end })
  selectAll:SetPoint("RIGHT", again, "LEFT", -8, 0)
  self.frame = f
  return f
end

function Autotest:Show(text, summary, counts)
  local f = self.frame or self:Build()
  f.text = text
  f.summary:SetText(summary)
  UI.SetTextColor(f.summary, (counts and counts.fail > 0) and C.bad or ((counts and counts.warn > 0) and C.gold or C.good))
  f.eb:SetText(text)
  f:Show()
  f:Raise()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

-- Rouvre le dernier rapport sans relancer les vérifications.
function Autotest:ShowLast()
  local last = ns.db.autotest
  if not last or not last.text then return false end
  self:Show(last.text, last.text:match("([^\n]+)$") or "")
  return true
end
