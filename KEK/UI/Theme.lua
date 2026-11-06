-- KEK — thème visuel : couleurs, polices, textures.
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

UI.T = {
  font = {
    title = "Fonts\\FRIZQT__.TTF",
    body = "Fonts\\ARIALN.TTF",
  },
  c = {
    shell = { 0.063, 0.070, 0.090, 0.985 },   -- fond de fenêtre / barre latérale
    surface = { 0.094, 0.104, 0.130, 1 },     -- zone de contenu
    card = { 0.125, 0.137, 0.170, 1 },        -- cartes
    cardHi = { 0.157, 0.171, 0.211, 1 },      -- cartes survolées, champs
    edge = { 0.178, 0.192, 0.235, 1 },        -- bordures
    line = { 1, 1, 1, 0.06 },
    hover = { 1, 1, 1, 0.045 },
    text = { 0.945, 0.935, 0.905, 1 },
    muted = { 0.640, 0.660, 0.720, 1 },
    faint = { 0.430, 0.450, 0.520, 1 },
    accent = { 1.000, 0.549, 0.239, 1 },      -- braise
    accentDim = { 1.000, 0.549, 0.239, 0.14 },
    gold = { 1.000, 0.800, 0.350, 1 },
    good = { 0.380, 0.860, 0.560, 1 },
    bad = { 0.960, 0.380, 0.380, 1 },
    info = { 0.400, 0.680, 1.000, 1 },
    ink = { 0.110, 0.070, 0.035, 1 },         -- texte sur bouton braise
  },
}

function UI.Media(name)
  return MEDIA .. name
end

function UI.Icon(name)
  return MEDIA .. "Icons\\" .. name
end

UI.WHITE = "Interface\\Buttons\\WHITE8X8"
