-- KEK — accès rapide : bouton de minicarte standard (LibDBIcon, comme le demande WoW Forever),
-- entrée dans le menu des addons du jeu, et objet LibDataBroker pour les barres d'infos (Titan, etc.).
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local Button = ns:NewModule("MinimapButton", 80)

local NAME = "KEK"
local ICON = "Interface\\AddOns\\KEK\\Media\\logo"
local HINT = L["Clic : ouvrir · Clic droit : réglages · Glisser : déplacer"]

local function libs()
  if not LibStub then return nil, nil end
  return LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
end

function Button:FillTooltip(tt)
  tt:AddLine("|cffff8c3dKEK|r")
  local online = {}
  for name, m in pairs(ns.db.members) do
    if name ~= ns.me and ns.Store:IsOnline(name) then online[#online + 1] = m end
  end
  table.sort(online, function(x, y) return (x.level or 0) > (y.level or 0) end)
  if #online == 0 then
    tt:AddLine(L["Personne d'autre en ligne"], 0.6, 0.62, 0.68)
  else
    for _, m in ipairs(online) do
      local r, g, bl = U.ClassColor(m.class)
      tt:AddDoubleLine(U.Short(m.name) .. "  |cff8a8f9e" .. (m.level or "?") .. "|r", m.zone or "", r, g, bl, 0.75, 0.76, 0.8)
    end
  end
  tt:AddLine(" ")
end

local function onClick(_, mouseButton)
  if mouseButton == "RightButton" then ns.Window:Open("settings") else ns.Window:Toggle() end
end

-- Fonctions appelées par le menu des addons du jeu (noms déclarés dans KEK.toc).
function KEK_OnAddonCompartmentClick(_, mouseButton)
  onClick(nil, mouseButton)
end

function KEK_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
  Button:FillTooltip(GameTooltip)
  GameTooltip:AddLine(L["Clic : ouvrir · Clic droit : réglages"], 0.5, 0.52, 0.58)
  GameTooltip:Show()
end

function KEK_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

-- ------------------------------------------------------------------ bouton de la minicarte
function Button:Wanted()
  return not ns.db.ui.minimap.hide
end

function Button:SetWanted(on)
  ns.db.ui.minimap.hide = not on
  self:Update()
end

function Button:Update()
  local _, icon = libs()
  if not icon or not icon:IsRegistered(NAME) then return end
  if self:Wanted() then icon:Show(NAME) else icon:Hide(NAME) end
end

function Button:RefreshCount()
  local n = ns.Store:OnlineCount()
  if self.object then
    self.object.text = n > 0 and string.format(n == 1 and L["%d ami en ligne"] or L["%d amis en ligne"], n) or "KEK"
  end
  if self.count then self.count:SetText(n > 0 and tostring(n) or "") end
end

function Button:OnLogin()
  local mm = ns.db.ui.minimap
  -- reprise de la position de l'ancien bouton (même convention d'angle que LibDBIcon)
  if mm.minimapPos == nil and type(mm.angle) == "number" then mm.minimapPos = mm.angle % 360 end
  mm.angle, mm.forced = nil, nil

  local ldb, icon = libs()
  if not ldb or not icon then return end
  self.object = ldb:NewDataObject(NAME, {
    type = "launcher", label = "KEK", text = "KEK", icon = ICON,
    OnClick = onClick,
    OnTooltipShow = function(tt)
      Button:FillTooltip(tt)
      tt:AddLine(HINT, 0.5, 0.52, 0.58)
    end,
  })
  if not self.object then return end
  icon:Register(NAME, self.object, mm)

  -- pastille : nombre d'amis en ligne
  local button = icon:GetMinimapButton(NAME)
  if button then
    self.button = button
    self.count = button:CreateFontString(nil, "OVERLAY")
    self.count:SetFont(UI.T.font.title, 10, "OUTLINE")
    self.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, 2)
    self.count:SetTextColor(C.good[1], C.good[2], C.good[3])
  end
  ns:On("PRESENCE", function() self:RefreshCount() end)
  self:RefreshCount()
end
