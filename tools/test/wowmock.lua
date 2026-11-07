-- Simulation minimale (et stricte) de l'API WoW Classic pour tester KEK hors du jeu.
-- Les méthodes inconnues provoquent une erreur : toute faute de frappe dans l'addon est détectée.
local M = {}
Mock = M

M.now = 1000
M.server = 1762430000
M.timers = {}
M.events = {}
M.frames = {}
M.outbox = {}
M.errors = {}
M.undefined = {}
M.printed = {}
M.sounds = {}
M.chat = {}
M.whispers = {}
M.popups = {}
M.playedPrinted = 0
M.friends = {}
M.group = nil          -- liste de noms courts des autres membres du groupe
M.forbidden = 0
M.systemShown = {}
M.filters = {}
M.cursor = nil
M.mouseOver = nil
M.target = nil         -- { name = "…", hostile = true }
M.falling = false
M.mirror = {}
M.equipped = {}
M.lockdown = false
M.inInstance = false

M.player = {
  name = "Nans", realm = "Forever", class = "MAGE", classLoc = "Mage", race = "Human", raceLoc = "Humain",
  level = 10, xp = 500, xpMax = 7600, money = 123456, guild = nil, zone = "Forêt d'Elwynn", sub = "Comté-de-l'Or",
  guid = "Player-1-0001", dead = false, played = 36000, rested = 1200,
}
M.items = {
  [2589] = { name = "Étoffe de lin", q = 1, icon = 132889 },
  [2568] = { name = "Chemise en lin brune", q = 1, icon = 135018 },
  [12784] = { name = "Faucheuse d'arcanite", q = 4, icon = 135562 },
  [2575] = { name = "Chemise en lin blanche", q = 2, icon = 135019 },
  [2673] = { name = "Viande de coyote", q = 1, icon = 133970 },
  [2320] = { name = "Fil grossier", q = 1, icon = 132889 },
  [2684] = { name = "Ragoût de coyote", q = 1, icon = 133971 },
  -- objets LQE (« Lié quand équipé ») et sac, pour le Coffre
  [15001] = { name = "Robe de l'aigle", q = 2, icon = 132666, ilvl = 24, minLevel = 9, classID = 4, subclassID = 1,
              subType = "Tissu", equipLoc = "INVTYPE_ROBE", bind = 2, stats = { ITEM_MOD_INTELLECT_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 3 } },
  [15002] = { name = "Bottes en mailles du singe", q = 2, icon = 132535, ilvl = 18, minLevel = 13, classID = 4, subclassID = 3,
              subType = "Mailles", equipLoc = "INVTYPE_FEET", bind = 2, stats = { ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2 } },
  [15003] = { name = "Patron : Gilet en lin", q = 1, icon = 134939, ilvl = 11, minLevel = 0, classID = 9, subclassID = 2,
              subType = "Couture", bind = 2, tip = "Requiert Couture (55)" },
  [15004] = { name = "Sac en laine", q = 1, icon = 133639, ilvl = 15, minLevel = 0, classID = 1, subclassID = 0,
              subType = "Sac", bind = 0, tip = "8 emplacements Sac" },
  [15006] = { name = "Bottes en tissu de l'ours", q = 2, icon = 132539, ilvl = 18, minLevel = 10, classID = 4, subclassID = 1,
              subType = "Tissu", equipLoc = "INVTYPE_FEET", bind = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 3 } },
  [15007] = { name = "Cape du singe", q = 2, icon = 133762, ilvl = 17, minLevel = 10, classID = 4, subclassID = 1,
              subType = "Tissu", equipLoc = "INVTYPE_CLOAK", bind = 2, stats = { ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 2 } },
  [15008] = { name = "Jambières en cuir de l'ours", q = 2, icon = 134586, ilvl = 18, minLevel = 10, classID = 4, subclassID = 2,
              subType = "Cuir", equipLoc = "INVTYPE_LEGS", bind = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 2 } },
  [15005] = { name = "Lame du tigre", q = 2, icon = 135274, ilvl = 20, minLevel = 8, classID = 2, subclassID = 7,
              subType = "Épées à une main", equipLoc = "INVTYPE_WEAPON", bind = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_AGILITY_SHORT = 2 } },
}
M.bags = { [0] = { [1] = { id = 2589, count = 14 }, [3] = { id = 2568, count = 1 } } }
M.trade = nil

local function link(id)
  local it = M.items[id]
  local hex = ({ [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" })[it.q]
  return "|c" .. hex .. "|Hitem:" .. id .. "::::::::60:::::|h[" .. it.name .. "]|h|r"
end
M.link = link

-- ------------------------------------------------------------------ régions
local POINTS = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
local LAYERS = { BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 }
local STRATA = { BACKGROUND = 1, LOW = 1, MEDIUM = 1, HIGH = 1, DIALOG = 1, FULLSCREEN = 1, FULLSCREEN_DIALOG = 1, TOOLTIP = 1 }
local SCRIPTS = {
  OnEvent = 1, OnUpdate = 1, OnClick = 1, OnEnter = 1, OnLeave = 1, OnMouseDown = 1, OnMouseUp = 1, OnMouseWheel = 1,
  OnDragStart = 1, OnDragStop = 1, OnReceiveDrag = 1, OnShow = 1, OnHide = 1, OnSizeChanged = 1, OnTextChanged = 1,
  OnEnterPressed = 1, OnEscapePressed = 1, OnEditFocusGained = 1, OnEditFocusLost = 1,
}
local ANCHORS = { ANCHOR_RIGHT = 1, ANCHOR_LEFT = 1, ANCHOR_TOP = 1, ANCHOR_BOTTOM = 1, ANCHOR_CURSOR = 1, ANCHOR_NONE = 1, ANCHOR_TOPLEFT = 1, ANCHOR_TOPRIGHT = 1 }

local function num(v, what)
  if type(v) ~= "number" or v ~= v then error("nombre attendu pour " .. what .. ", reçu " .. tostring(v), 3) end
end

local function class(methods, ...)
  local c = {}
  for _, base in ipairs({ ... }) do for k, v in pairs(base) do c[k] = v end end
  for k, v in pairs(methods) do c[k] = v end
  return c
end

local Region = {}
function Region:SetPoint(point, a, b, c, d)
  if not POINTS[point] then error("point d'ancrage invalide : " .. tostring(point), 2) end
  local rel, relPoint, x, y = a, b, c, d
  if type(a) == "number" then rel, relPoint, x, y = nil, point, a, b end
  if type(rel) == "string" and POINTS[rel] then rel, relPoint, x, y = nil, rel, b, c end
  if relPoint ~= nil and not POINTS[relPoint] then error("point relatif invalide : " .. tostring(relPoint), 2) end
  if x ~= nil then num(x, "x") end
  if y ~= nil then num(y, "y") end
  self._points = self._points or {}
  self._points[#self._points + 1] = { point, rel, relPoint, x or 0, y or 0 }
end
function Region:ClearAllPoints() self._points = {} end
function Region:SetAllPoints(rel) self._points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } }; self._all = rel or self._parent end
function Region:GetPoint(i)
  local p = (self._points or {})[i or 1]
  if not p then return nil end
  return p[1], p[2], p[3], p[4], p[5]
end
function Region:GetNumPoints() return #(self._points or {}) end
function Region:SetSize(w, h) num(w, "largeur"); num(h, "hauteur"); self._w, self._h = w, h; if self._onSize then self:_onSize() end end
function Region:SetWidth(w) num(w, "largeur"); self._w = w; if self._onSize then self:_onSize() end end
function Region:SetHeight(h) num(h, "hauteur"); self._h = h; if self._onSize then self:_onSize() end end
function Region:GetWidth()
  if self._w then return self._w end
  local rel = self._all or self._parent
  return rel and rel.GetWidth and rel:GetWidth() or 600
end
function Region:GetHeight()
  if self._h then return self._h end
  local rel = self._all or self._parent
  return rel and rel.GetHeight and rel:GetHeight() or 400
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetCenter() return self._cx or 900, self._cy or 700 end
function Region:GetLeft() return 300 end
function Region:GetTop() return 800 end
function Region:Show() local was = self._shown; self._shown = true; if not was and self._fire then self:_fire("OnShow") end end
function Region:Hide() local was = self._shown; self._shown = false; if was and self._fire then self:_fire("OnHide") end end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown end
function Region:IsVisible()
  local r = self
  while r do
    if not r._shown then return false end
    r = r._parent
  end
  return true
end
function Region:SetAlpha(a) num(a, "alpha"); self._alpha = a end
function Region:GetAlpha() return self._alpha or 1 end
function Region:GetParent() return self._parent end
function Region:GetObjectType() return self._type end
function Region:SetScale(s) num(s, "échelle"); self._scale = s end
function Region:GetEffectiveScale() return 1 end

local TextureM = {}
function TextureM:SetTexture(t, wrapH, wrapV) if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("texture invalide", 2) end; self._tex = t end
function TextureM:GetTexture() return self._tex end
function TextureM:SetTexCoord(...)
  local n = select("#", ...)
  if n ~= 4 and n ~= 8 then error("SetTexCoord attend 4 ou 8 nombres", 2) end
  for i = 1, n do num(select(i, ...), "texcoord") end
end
function TextureM:SetVertexColor(r, g, b, a) num(r, "r"); num(g, "g"); num(b, "b"); if a ~= nil then num(a, "a") end; self._color = { r, g, b, a } end
function TextureM:GetVertexColor() local c = self._color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] or 1 end
function TextureM:SetColorTexture(r, g, b, a) num(r, "r"); num(g, "g"); num(b, "b") end
function TextureM:SetDesaturated(v) end
function TextureM:SetBlendMode(m) if m ~= "ADD" and m ~= "BLEND" and m ~= "MOD" and m ~= "DISABLE" then error("mode de fusion invalide", 2) end end
function TextureM:AddMaskTexture(mask) if not mask or mask._type ~= "MaskTexture" then error("masque invalide", 2) end end
function TextureM:SetDrawLayer(layer) end

local LineM = {}
function LineM:SetStartPoint(p, rel, x, y) if not POINTS[p] then error("point invalide", 2) end; num(x, "x"); num(y, "y") end
function LineM:SetEndPoint(p, rel, x, y) if not POINTS[p] then error("point invalide", 2) end; num(x, "x"); num(y, "y") end
function LineM:SetThickness(t) num(t, "épaisseur") end

local FontM = {}
function FontM:SetFont(path, size, flags)
  if type(path) ~= "string" then error("police invalide", 2) end
  num(size, "taille de police")
  if flags ~= nil and type(flags) ~= "string" then error("flags invalides", 2) end
  self._font = size
end
function FontM:SetText(t)
  if not self._font then error("Font not set", 2) end
  if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("texte invalide : " .. type(t), 2) end
  self._text = t and tostring(t) or nil
  if self._onTextChanged then self:_onTextChanged() end
end
function FontM:GetText() return self._text end
function FontM:SetTextColor(r, g, b, a) num(r, "r"); num(g, "g"); num(b, "b") end
function FontM:SetJustifyH(j) if j ~= "LEFT" and j ~= "CENTER" and j ~= "RIGHT" then error("justification invalide", 2) end end
function FontM:SetJustifyV(j) end
function FontM:SetWordWrap(v) end
function FontM:SetShadowOffset(x, y) num(x, "x"); num(y, "y") end
function FontM:SetShadowColor(r, g, b, a) num(r, "r") end
function FontM:GetStringWidth() return #(self._text or "") * (self._font or 12) * 0.45 end
function FontM:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end

local FrameM = {}
local function newRegion(kind, parent, methods, layer, sublevel)
  if layer and not LAYERS[layer] then error("couche invalide : " .. tostring(layer), 3) end
  if sublevel and (sublevel < -8 or sublevel > 7) then error("sous-niveau invalide : " .. sublevel, 3) end
  local r = setmetatable({ _type = kind, _parent = parent, _shown = true }, { __index = methods })
  return r
end
local TextureClass = class(TextureM, Region)
local LineClass = class(LineM, TextureM, Region)
local MaskClass = class({ SetTexture = TextureM.SetTexture }, Region)
local FontClass = class(FontM, Region)

function FrameM:CreateTexture(name, layer, template, sublevel) return newRegion("Texture", self, TextureClass, layer, sublevel) end
function FrameM:CreateLine(name, layer, template, sublevel) return newRegion("Line", self, LineClass, layer, sublevel) end
function FrameM:CreateMaskTexture() return newRegion("MaskTexture", self, MaskClass) end
function FrameM:CreateFontString(name, layer) return newRegion("FontString", self, FontClass, layer) end
function FrameM:SetScript(h, fn)
  if not SCRIPTS[h] then error("script inconnu : " .. tostring(h), 2) end
  self._scripts[h] = fn
end
function FrameM:GetScript(h) return self._scripts[h] end
function FrameM:HookScript(h, fn)
  if not SCRIPTS[h] then error("script inconnu : " .. tostring(h), 2) end
  local old = self._scripts[h]
  self._scripts[h] = old and function(...) old(...); fn(...) end or fn
end
function FrameM:_fire(h, ...)
  local fn = self._scripts[h]
  if fn then fn(self, ...) end
end
function FrameM:_onSize() self:_fire("OnSizeChanged", self:GetWidth(), self:GetHeight()) end
function FrameM:RegisterEvent(e)
  if type(e) ~= "string" then error("événement invalide", 2) end
  if e == "COMBAT_LOG_EVENT_UNFILTERED" or e == "COMBAT_LOG_EVENT" then M.forbidden = M.forbidden + 1; return end
  M.events[e] = M.events[e] or {}; M.events[e][self] = true
end
function FrameM:UnregisterEvent(e) if M.events[e] then M.events[e][self] = nil end end
function FrameM:IsEventRegistered(e) return M.events[e] ~= nil and M.events[e][self] == true end
function FrameM:SetFixedFrameStrata(v) end
function FrameM:Raise() end
function FrameM:SetFixedFrameLevel(v) end
-- animations (LibDBIcon)
local AnimM = {}
for _, m in ipairs({ "SetOrder", "SetDuration", "SetFromAlpha", "SetToAlpha", "SetStartDelay" }) do
  AnimM[m] = function(self, v) if type(v) ~= "number" then error(m .. " : nombre attendu", 2) end end
end
local GroupM = {}
function GroupM:CreateAnimation(kind) if kind ~= "Alpha" and kind ~= "Translation" and kind ~= "Scale" then error("animation inconnue", 2) end; return setmetatable({}, { __index = AnimM }) end
function GroupM:SetToFinalAlpha(v) end
function GroupM:Play() self.playing = true end
function GroupM:Stop() self.playing = false end
function FrameM:CreateAnimationGroup() return setmetatable({ _owner = self }, { __index = GroupM }) end
function FrameM:SetFrameStrata(s) if not STRATA[s] then error("strate invalide : " .. tostring(s), 2) end end
function FrameM:SetFrameLevel(l) num(l, "niveau"); self._level = l end
function FrameM:GetFrameLevel() return self._level or ((self._parent and self._parent.GetFrameLevel and self._parent:GetFrameLevel() or 0) + 1) end
function FrameM:EnableMouse(v) end
function FrameM:EnableMouseWheel(v) end
function FrameM:SetMovable(v) end
function FrameM:SetResizable(v) end
function FrameM:SetClampedToScreen(v) end
function FrameM:SetToplevel(v) end
function FrameM:GetScale() return self._scale or 1 end
function FrameM:StartMoving() end
function FrameM:StopMovingOrSizing() end
function FrameM:StartSizing(p) if not POINTS[p] then error("point invalide", 2) end end
function FrameM:SetResizeBounds(a, b, c, d) num(a, "min"); num(b, "min") end
function FrameM:SetClipsChildren(v) end
function FrameM:IsMouseOver() return M.mouseOver == self end
function FrameM:RegisterForDrag(...) end
function FrameM:SetParent(p) self._parent = p end

local ButtonM = {}
function ButtonM:RegisterForClicks(...) end
function ButtonM:SetHighlightTexture(t) if type(t) ~= "string" and type(t) ~= "number" then error("texture invalide", 2) end end
function ButtonM:LockHighlight() end
function ButtonM:UnlockHighlight() end
function ButtonM:Click(button) self:_fire("OnClick", button or "LeftButton") end
function ButtonM:Enable() end
function ButtonM:Disable() end

local EditM = {}
function EditM:SetAutoFocus(v) end
function EditM:SetMultiLine(v) end
function EditM:HighlightText(a, b) self._highlight = true end
function EditM:SetMaxLetters(n) num(n, "max") self._max = n end
function EditM:SetNumeric(v) end
function EditM:SetTextInsets(...) end
function EditM:SetText(t)
  if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("texte invalide", 2) end
  self._text = tostring(t or "")
  self:_fire("OnTextChanged", false)
end
function EditM:GetText() return self._text or "" end
function EditM:Insert(t) self._text = (self._text or "") .. t; self:_fire("OnTextChanged", true) end
function EditM:SetFocus()
  if M.focus and M.focus ~= self then M.focus:ClearFocus() end
  M.focus = self
  if not self._focus then self._focus = true; self:_fire("OnEditFocusGained") end
end
function EditM:ClearFocus()
  if M.focus == self then M.focus = nil end
  if self._focus then self._focus = false; self:_fire("OnEditFocusLost") end
end
function EditM:HasFocus() return self._focus == true end
function EditM:Type(t) self._text = t; self:_fire("OnTextChanged", true) end

local TooltipM = {}
function TooltipM:SetOwner(owner, anchor) if anchor and not ANCHORS[anchor] then error("ancre d'infobulle invalide : " .. tostring(anchor), 2) end; self._lines = {} end
function TooltipM:AddLine(t, r, g, b, wrap) if t ~= nil and type(t) ~= "string" then error("ligne invalide : " .. type(t), 2) end; self._lines[#self._lines + 1] = t end
function TooltipM:AddDoubleLine(a, b, ...)
  if type(a) ~= "string" or type(b) ~= "string" then error("double ligne invalide : " .. type(a) .. "/" .. type(b), 2) end
  self._lines[#self._lines + 1] = a .. " | " .. b
end
function TooltipM:SetText(t) self._lines = { t } end
function TooltipM:SetHyperlink(l) if type(l) ~= "string" then error("lien invalide", 2) end end
function TooltipM:SetItemByID(id) num(id, "id") end
function TooltipM:ClearLines() self._lines = {} end

local FrameClass = class(FrameM, Region)
local ButtonClass = class(ButtonM, FrameM, Region)
local EditClass = class(EditM, FontM, FrameM, Region)
EditClass.SetText, EditClass.GetText = EditM.SetText, EditM.GetText
local TooltipClass = class(TooltipM, FrameM, Region)
local TYPES = { Frame = FrameClass, Button = ButtonClass, EditBox = EditClass, GameTooltip = TooltipClass }

function CreateFrame(kind, name, parent, template)
  local methods = TYPES[kind]
  if not methods then error("type de cadre inconnu : " .. tostring(kind), 2) end
  local f = setmetatable({ _type = kind, _parent = parent, _shown = true, _scripts = {} }, { __index = methods })
  if name then _G[name] = f end
  M.frames[#M.frames + 1] = f
  return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent._w, UIParent._h = 1920, 1080
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap._w, Minimap._h = 140, 140
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip._lines = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.printed[#M.printed + 1] = msg end }
NUM_CHAT_WINDOWS = 10
-- fenêtres de chat : elles affichent la réponse de /played si elles écoutent TIME_PLAYED_MSG
for i = 1, 10 do
  local cf = CreateFrame("Frame", "ChatFrame" .. i, UIParent)
  cf:Hide()
  if i <= 2 then
    cf:RegisterEvent("TIME_PLAYED_MSG")
    cf:SetScript("OnEvent", function(_, event) if event == "TIME_PLAYED_MSG" then M.playedPrinted = M.playedPrinted + 1 end end)
  end
end
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}

-- ------------------------------------------------------------------ temps
date, time = os.date, os.time
function GetTime() return M.now end
function GetServerTime() return M.server + math.floor(M.now - 1000) end
C_Timer = {}
function C_Timer.After(d, fn) num(d, "délai"); M.timers[#M.timers + 1] = { at = M.now + d, fn = fn } end
function C_Timer.NewTicker(d, fn, n)
  local t = { cancelled = false }
  function t:Cancel() self.cancelled = true end
  local count = 0
  local function run()
    if t.cancelled then return end
    count = count + 1
    fn(t)
    if not n or count < n then C_Timer.After(d, run) end
  end
  C_Timer.After(d, run)
  return t
end

function M.fire(event, ...)
  local list = M.events[event]
  if not list then return end
  for f in pairs(list) do f:_fire("OnEvent", event, ...) end
end

function M.advance(seconds, step)
  step = step or 0.05
  local target = M.now + seconds
  while M.now < target - 1e-9 do
    M.now = M.now + step
    local due = {}
    local keep = {}
    for _, t in ipairs(M.timers) do
      if t.at <= M.now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    M.timers = keep
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do
      local ok, err = pcall(t.fn)
      if not ok then M.errors[#M.errors + 1] = "timer: " .. tostring(err) end
    end
    for _, f in ipairs(M.frames) do
      local fn = f._scripts.OnUpdate
      if fn and f:IsVisible() then
        local ok, err = pcall(fn, f, step)
        if not ok then M.errors[#M.errors + 1] = "OnUpdate: " .. tostring(err) end
      end
    end
  end
end

-- ------------------------------------------------------------------ API du jeu
local P = M.player
function UnitName(u)
  if u == "player" then return P.name, P.surname end   -- WoW Forever : prénom, nom de famille
  if u == "target" and M.target then return M.target.name end
  local i = tonumber(tostring(u):match("^party(%d+)$") or tostring(u):match("^raid(%d+)$"))
  if i and M.group and M.group[i] then return M.group[i], nil end
  return nil
end
function UnitClass(u) return P.classLoc, P.class end
function UnitRace(u) return P.raceLoc, P.race end
function UnitSex(u) return 2 end
M.groupState = {}
local function groupMember(u)
  local i = tonumber(tostring(u):match("^party(%d+)$") or tostring(u):match("^raid(%d+)$"))
  return i and M.group and M.group[i] or nil
end
function UnitLevel(u)
  local g = groupMember(u)
  if g then return (M.groupState[g] or {}).level end
  return P.level
end
function UnitIsConnected(u)
  local g = groupMember(u)
  if g then return (M.groupState[g] or {}).connected ~= false end
  return u == "player"
end
function UnitXP(u) return P.xp end
function UnitXPMax(u) return P.xpMax end
function GetXPExhaustion() return P.rested end
function UnitGUID(u) if u == "player" then return P.guid end return nil end
function UnitIsDeadOrGhost(u) return P.dead end
function IsInInstance() if M.inInstance then return true, M.instanceType or "party" end return false, "none" end
-- Battle.net : amis connectés à WoW et données d'addon entre comptes
M.bnFriends = {}
M.bnOutbox = {}
M.gameAccountID = nil
function BNGetNumFriends() return #M.bnFriends, #M.bnFriends end
C_BattleNet = {}
function C_BattleNet.GetFriendNumGameAccounts(i) return M.bnFriends[i] and 1 or 0 end
function C_BattleNet.GetFriendGameAccountInfo(i, j) return M.bnFriends[i] end
function BNSendGameData(id, prefix, text)
  if type(id) ~= "number" then error("identifiant de compte attendu", 2) end
  if type(text) ~= "string" or #text > 4078 then error("données invalides", 2) end
  M.bnOutbox[#M.bnOutbox + 1] = { id, prefix, text }
end
function GetInstanceInfo() if M.inInstance then return "Les Mortemines", "party" end return "Royaumes de l'Est", "none" end
function UnitExists(u) return u == "player" or (u == "target" and M.target ~= nil) or groupMember(u) ~= nil end
function UnitCanAttack(a, u) return u == "target" and M.target ~= nil and M.target.hostile == true end
function UnitIsPlayer(u) return u == "player" end
function IsFalling() return M.falling end
function GetMirrorTimerProgress(t) return M.mirror[t] or 0 end
function GetInventoryItemID(u, slot) local e = M.equipped[slot]; return e and e.id end
function GetInventoryItemLink(u, slot) local e = M.equipped[slot]; return e and M.link(e.id) end
-- valeurs secrètes (interface 12.x) : illisibles par les addons
local SECRET = setmetatable({}, { __mode = "k" })
function M.secret() local v = newproxy and newproxy(false) or {}; SECRET[v] = true; return v end
function issecretvalue(v) return SECRET[v] == true end
function GetRealZoneText() return P.zone end
function GetZoneText() return P.zone end
function GetSubZoneText() return P.sub end
function GetGuildInfo(u) return P.guild end
function IsInGuild() return P.guild ~= nil end
function IsInGroup() return M.group ~= nil end
function IsInRaid() return false end
function GetNumGroupMembers() return M.group and (#M.group + 1) or 0 end
C_FriendList = {}
function C_FriendList.GetNumFriends() return #M.friends end
function C_FriendList.GetFriendInfoByIndex(i)
  local f = M.friends[i]
  return f and { name = f.name, connected = f.connected, level = f.connected and f.level or 0, area = f.connected and f.area or nil }
end
M.polls = { friends = 0, guild = 0 }
function C_FriendList.ShowFriends() M.polls.friends = M.polls.friends + 1 end
-- liste de la guilde : M.guildRoster = { { name = "Nom-Royaume", level, zone, online }, … }
M.guildRoster = {}
function GetNumGuildMembers()
  if not P.guild then return 0, 0, 0 end
  local on = 0
  for _, g in ipairs(M.guildRoster) do if g.online then on = on + 1 end end
  return #M.guildRoster, on, on
end
function GetGuildRosterInfo(i)
  local g = M.guildRoster[i]
  if not g then return nil end
  return g.name, "Membre", 2, g.level, "Mage", g.zone, "", "", g.online == true, 0, "MAGE"
end
C_GuildInfo = { GuildRoster = function() M.polls.guild = M.polls.guild + 1 end }
function GetNormalizedRealmName() return P.realm end
function GetRealmName() return P.realm end
function GetMoney() return P.money end
function GetAddOnMetadata(a, k) return M.meta[k] end
function GetBuildInfo() return "1.60.1", "70790", "Oct 30 2026", 16001 end
function GetLocale() return "frFR" end
ERR_CHAT_PLAYER_NOT_FOUND_S = ERR_CHAT_PLAYER_NOT_FOUND_S
SKILL_RANK_UP = SKILL_RANK_UP
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i)
  local names = { "Arcanes", "Feu", "Givre" }
  local pts = { 0, P.level >= 10 and 1 or 0, 0 }
  return names[i], 135932 + i, pts[i], "MageFire"
end
function GetNumSkillLines() return 5 end
function GetSkillLineInfo(i)
  local lines = {
    { "Métiers", true }, { "Couture", false, 75, 150 }, { "Enchantement", false, 30, 75 },
    { "Compétences secondaires", true }, { "Cuisine", false, 12, 75 },
  }
  local l = lines[i]
  return l[1], l[2], false, l[3] or 0, 0, 0, l[4] or 0
end
TRADE_SKILLS = "Métiers"
SECONDARY_SKILLS = "Compétences secondaires :"
function RequestTimePlayed()
  C_Timer.After(0.4, function() M.fire("TIME_PLAYED_MSG", P.played, 1000) end)
end
COMBATLOG_XPGAIN_FIRSTPERSON = "%s meurt, vous gagnez %d points d'expérience."
COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "Vous gagnez %d points d'expérience."

-- filtres de messages du chat (ChatFrame_AddMessageEventFilter)
function ChatFrame_AddMessageEventFilter(event, fn) M.filters[event] = M.filters[event] or {}; table.insert(M.filters[event], fn) end
function M.system(msg)
  for _, fn in ipairs(M.filters.CHAT_MSG_SYSTEM or {}) do
    if fn(ChatFrame1, "CHAT_MSG_SYSTEM", msg) then return false end
  end
  M.systemShown[#M.systemShown + 1] = msg
  return true
end
ERR_CHAT_PLAYER_NOT_FOUND_S = "Aucun joueur nommé '%s' n'est connecté."

C_ChatInfo = {}
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9, AddOnMessageLockdown = 11, TargetOffline = 12 } }
function C_ChatInfo.InChatMessagingLockdown() return M.lockdown end
local prefixes = {}
function C_ChatInfo.IsAddonMessagePrefixRegistered(p) return prefixes[p] == true end
function C_ChatInfo.RegisterAddonMessagePrefix(p) if #p > 16 then error("préfixe trop long", 2) end; prefixes[p] = true; return true end
function C_ChatInfo.SendAddonMessage(prefix, msg, dist, target)
  if not prefixes[prefix] then error("préfixe non enregistré", 2) end
  if type(msg) ~= "string" or #msg > 255 then error("message trop long : " .. #msg, 2) end
  if msg:find("\0", 1, true) then error("octet nul interdit", 2) end
  -- comme en Classic : les messages d'addon sur un canal personnalisé sont interdits (addon bloqué)
  if dist == "CHANNEL" then M.forbidden = M.forbidden + 1; return 9 end
  local ok = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true, SAY = true, YELL = true }
  if not ok[dist] then error("type de message invalide : " .. tostring(dist), 2) end
  if dist == "WHISPER" and (type(target) ~= "string" or target == "") then error("destinataire manquant", 2) end
  if dist == "GUILD" and not P.guild then return 10 end
  if (dist == "PARTY" or dist == "RAID") and not M.group then return 5 end
  if M.lockdown then M.lockedSends = (M.lockedSends or 0) + 1; return 11 end
  if M.sendResult then return M.sendResult end
  M.outbox[#M.outbox + 1] = { prefix, msg, dist, target }
  return 0
end
function SendChatMessage(msg, channel)
  if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "GUILD" then error("canal de chat interdit : " .. tostring(channel), 2) end
  M.chat[#M.chat + 1] = { msg, channel }
end

C_Container = {}
M.bagSlots = { [0] = 16, [-1] = 24 }   -- sac à dos, banque
function C_Container.GetContainerNumSlots(bag) return M.bagSlots[bag] or 0 end
function C_Container.GetContainerItemInfo(bag, slot)
  local b = M.bags[bag]
  local it = b and b[slot]
  if not it then return nil end
  return { itemID = it.id, stackCount = it.count, hyperlink = link(it.id), quality = M.items[it.id].q, isBound = it.bound == true }
end
NUM_BAG_SLOTS, NUM_BANKBAGSLOTS, BANK_CONTAINER = 4, 6, -1

M.uncached = {}
local function getItemInfo(x)
  if x == nil then error("bad argument #1 to 'GetItemInfo'", 2) end
  local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
  local it = id and M.items[id]
  if not it or M.uncached[id] then return nil end
  return it.name, link(id), it.q, it.ilvl or 20, it.minLevel or 15, "Divers", it.subType or "Divers", 20, it.equipLoc or "", it.icon,
    0, it.classID or 15, it.subclassID or 0, it.bind or 0
end
function GetItemIcon(id) local it = M.items[id]; return it and it.icon end
-- comme dans l'interface 12.x : plus de GetItemInfo global, seulement C_Item.GetItemInfo
C_Item = { GetItemIconByID = function(id) local it = M.items[id]; return it and it.icon end, GetItemInfo = getItemInfo }
function C_Item.GetItemStats(l)
  local id = tonumber(tostring(l):match("item:(%d+)"))
  local it = id and M.items[id]
  local out = {}
  for k, v in pairs(it and it.stats or {}) do out[k] = v end
  return out
end
-- infobulles (interface 12.x) : lignes de texte d'un objet
C_TooltipInfo = {}
function C_TooltipInfo.GetHyperlink(l)
  local id = tonumber(tostring(l):match("item:(%d+)"))
  local it = id and M.items[id]
  if not it then return nil end
  local lines = { { leftText = it.name } }
  if it.bind == 2 then lines[#lines + 1] = { leftText = "Lié quand équipé" } end
  if it.tip then lines[#lines + 1] = { leftText = it.tip } end
  return { lines = lines }
end
ITEM_MIN_SKILL = "Requiert %s (%d)"
CONTAINER_SLOTS = "%d emplacements %s"
-- banque de guilde : M.gbank = { [onglet] = { [case] = { id, count } } }
M.gbank = {}
M.gbankQueries = 0
MAX_GUILDBANK_SLOTS_PER_TAB = 98
function GetNumGuildBankTabs() return #M.gbank end
function GetGuildBankTabInfo(tab) return "Onglet " .. tab, 0, true end
function QueryGuildBankTab(tab) M.gbankQueries = M.gbankQueries + 1 end
function GetGuildBankItemLink(tab, slot) local t = M.gbank[tab]; local it = t and t[slot]; return it and link(it.id) or nil end
function GetGuildBankItemInfo(tab, slot)
  local t = M.gbank[tab]
  local it = t and t[slot]
  if not it then return nil end
  return M.items[it.id].icon, it.count or 1, false, false, M.items[it.id].q
end
function C_Item.RequestLoadItemDataByID(id)
  num(id, "id")
  if M.uncached[id] then C_Timer.After(0.3, function() M.uncached[id] = nil; M.fire("GET_ITEM_INFO_RECEIVED", id, true) end) end
end

function GetTradeSkillLine() if M.trade then return M.trade.name, M.trade.rank, M.trade.max end return "UNKNOWN", 0, 0 end
function GetNumTradeSkills() return M.trade and #M.trade.list or 0 end
function GetTradeSkillInfo(i) local r = M.trade.list[i]; return r.name, r.kind end
function GetTradeSkillItemLink(i) local r = M.trade.list[i]; return r.id and link(r.id) or nil end
-- composants (API Classic)
function GetTradeSkillNumReagents(i) local r = M.trade.list[i]; return r.reagents and #r.reagents or 0 end
function GetTradeSkillReagentInfo(i, n)
  local g = M.trade.list[i].reagents[n]
  local it = M.items[g.id]
  return it.name, it.icon, g.count, 0
end
function GetTradeSkillReagentItemLink(i, n) return link(M.trade.list[i].reagents[n].id) end

function GetCursorInfo() if M.cursor then return "item", M.cursor, link(M.cursor) end return nil end
function ClearCursor() M.cursor = nil end
function GetCursorPosition() return 500, 400 end
M.modified = {}
function IsModifiedClick(kind) return M.modified[kind or "CHATLINK"] == true end
function GetCurrentKeyBoardFocus() return M.focus end
M.inserted = {}
ChatFrameUtil = {}
function ChatFrameUtil.GetActiveWindow() return M.activeChat end
function ChatFrameUtil.InsertLink(text)
  if not text then return false end
  local active = ChatFrameUtil.GetActiveWindow()
  if active then active:Insert(text); active:SetFocus(); M.inserted[#M.inserted + 1] = text; return true end
  return false
end
ChatEdit_InsertLink = ChatFrameUtil.InsertLink
function HandleModifiedItemClick(l)
  if not l then return false end
  if IsModifiedClick("CHATLINK") and ChatFrameUtil.InsertLink(l) then return true end
  return false
end
-- Maj+clic sur un objet : sacs, lien du chat, fenêtre de métier… passent tous par HandleModifiedItemClick
function M.shiftClick(id)
  M.modified.CHATLINK = true
  local r = HandleModifiedItemClick(link(id))
  M.modified.CHATLINK = nil
  return r
end
function ChatFrame_OpenChat(text) M.whispers[#M.whispers + 1] = text end
function InviteUnit(n) end
function PlaySound(id, ch) M.sounds[#M.sounds + 1] = id; return true end
function PlaySoundFile(path, ch) return false end
SOUNDKIT = { IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
function StaticPopup_Show(name) M.popups[#M.popups + 1] = name end
function ReloadUI() M.reloaded = true end
YES, CANCEL = "Oui", "Annuler"
MELEE = "Mêlée"

function hooksecurefunc(a, b, c)
  local tbl, name, fn = _G, a, b
  if type(a) == "table" then tbl, name, fn = a, b, c end
  if type(tbl[name]) ~= "function" or type(fn) ~= "function" then error("hooksecurefunc : fonction absente : " .. tostring(name), 2) end
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end

function securecallfunction(f, ...) return f(...) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove

function geterrorhandler()
  return function(err) M.errors[#M.errors + 1] = tostring(err) end
end

RAID_CLASS_COLORS = {
  MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 },
}
ITEM_QUALITY_COLORS = {}
for q, c in pairs({ [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }) do
  ITEM_QUALITY_COLORS[q] = { r = c[1], g = c[2], b = c[3] }
end
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Guerrier", PRIEST = "Prêtre" }
LOOT_ITEM_SELF = "Vous recevez le butin : %s."
LOOT_ITEM_SELF_MULTIPLE = "Vous recevez le butin : %sx%d."
LOOT_ITEM_PUSHED_SELF = "Vous recevez l'objet : %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "Vous recevez l'objet : %sx%d."
LOOT_ITEM_CREATED_SELF = "Vous créez : %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "Vous créez : %sx%d."
SKILL_RANK_UP = "Votre compétence en %s est maintenant de %d."

-- ------------------------------------------------------------------ menu Options (API Settings, interface 11.x et plus)
M.settings = { categories = {}, addon = {}, controls = {}, buttons = {}, byVar = {} }
Settings = { VarType = { Boolean = "boolean", Number = "number", String = "string" } }
local function newCategory(name)
  local c = { name = name, id = #M.settings.categories + 1 }
  function c:GetID() return self.id end
  function c:GetName() return self.name end
  M.settings.categories[#M.settings.categories + 1] = c
  return c
end
local function isCategory(c) return type(c) == "table" and c.GetID ~= nil end
function Settings.RegisterVerticalLayoutCategory(name)
  if type(name) ~= "string" then error("nom de catégorie attendu", 2) end
  local c = newCategory(name)
  local layout = { inits = {} }
  function layout:AddInitializer(init)
    if type(init) ~= "table" then error("initialiseur attendu", 2) end
    self.inits[#self.inits + 1] = init
  end
  c.layout = layout
  return c, layout
end
function Settings.RegisterCanvasLayoutCategory(frame, name)
  if type(frame) ~= "table" or not frame._type then error("cadre attendu", 2) end
  if type(name) ~= "string" then error("nom attendu", 2) end
  local c = newCategory(name)
  c.frame = frame
  return c
end
function Settings.RegisterAddOnCategory(c)
  if not isCategory(c) then error("catégorie attendue", 2) end
  M.settings.addon[#M.settings.addon + 1] = c
end
function Settings.RegisterProxySetting(c, variable, varType, name, default, get, set)
  if not isCategory(c) or type(variable) ~= "string" or type(name) ~= "string" or type(get) ~= "function" or type(set) ~= "function" then
    error("RegisterProxySetting : arguments invalides", 2)
  end
  if varType ~= "boolean" and varType ~= "number" and varType ~= "string" then error("type de réglage invalide", 2) end
  if type(default) ~= varType then error("valeur par défaut du mauvais type", 2) end
  if M.settings.byVar[variable] then error("variable déjà enregistrée : " .. variable, 2) end
  local st = { variable = variable, name = name, type = varType, default = default }
  function st:GetValue() return get() end
  function st:SetValue(v) if type(v) ~= varType then error("mauvais type de valeur", 2) end; set(v) end
  function st:GetVariable() return variable end
  M.settings.byVar[variable] = st
  return st
end
local function newControl(kind, c, st, extra, tooltip)
  if not isCategory(c) or type(st) ~= "table" or not st.GetValue then error(kind .. " : arguments invalides", 3) end
  if tooltip ~= nil and type(tooltip) ~= "string" then error("infobulle invalide", 3) end
  local ctl = { kind = kind, setting = st, extra = extra }
  M.settings.controls[#M.settings.controls + 1] = ctl
  return ctl
end
function Settings.CreateCheckbox(c, st, tooltip)
  if st and st.type ~= "boolean" then error("case à cocher : réglage booléen attendu", 2) end
  return newControl("checkbox", c, st, nil, tooltip)
end
function Settings.CreateControlTextContainer()
  local data = {}
  return {
    Add = function(self, value, label) if type(label) ~= "string" then error("libellé attendu", 2) end; data[#data + 1] = { value = value, label = label } end,
    GetData = function() return data end,
  }
end
function Settings.CreateDropdown(c, st, options, tooltip)
  if type(options) ~= "function" then error("fonction d'options attendue", 2) end
  return newControl("dropdown", c, st, options, tooltip)
end
function Settings.CreateSliderOptions(lo, hi, step)
  num(lo, "min"); num(hi, "max"); num(step, "pas")
  local o = { min = lo, max = hi, step = step }
  function o:SetLabelFormatter(side, fn) if type(fn) ~= "function" then error("formateur attendu", 2) end; self.formatter = fn end
  return o
end
function Settings.CreateSlider(c, st, options, tooltip)
  if not st or st.type ~= "number" or type(options) ~= "table" then error("curseur invalide", 2) end
  return newControl("slider", c, st, options, tooltip)
end
MinimalSliderWithSteppersMixin = { Label = { Right = 4 } }
function CreateSettingsButtonInitializer(name, text, onClick, tooltip, search)
  if type(name) ~= "string" or type(text) ~= "string" or type(onClick) ~= "function" then error("bouton : arguments invalides", 2) end
  local b = { kind = "button", name = name, text = text, onClick = onClick }
  M.settings.buttons[#M.settings.buttons + 1] = b
  return b
end
function CreateSettingsListSectionHeaderInitializer(text)
  if type(text) ~= "string" then error("titre attendu", 2) end
  return { kind = "header", text = text }
end

-- globales absentes : on note les accès pour repérer les fautes de frappe
setmetatable(_G, { __index = function(_, k)
  M.undefined[k] = (M.undefined[k] or 0) + 1
  return nil
end })

-- ------------------------------------------------------------------ chargement de l'addon
M.meta = {}
function M.load(dir, toc)
  M.ns = {}
  for line in io.lines(dir .. "/" .. toc) do
    local k, v = line:gsub("\r", ""):match("^## ([%w]+): (.+)$")
    if k then M.meta[k] = v end
  end
  for line in io.lines(dir .. "/" .. toc) do
    line = line:gsub("\r", "")
    if line ~= "" and not line:find("^##") then
      local path = dir .. "/" .. line:gsub("\\", "/")
      local chunk, err = loadfile(path)
      if not chunk then error("syntaxe : " .. err) end
      chunk("KEK", M.ns)
    end
  end
  return M.ns
end
