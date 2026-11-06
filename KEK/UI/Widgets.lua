-- KEK — kit d'interface : animations, formes arrondies, boutons, champs, listes virtualisées, menus.
local _, ns = ...
local UI, U = ns.UI, ns.U
local T = UI.T
local C = T.c

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local unpack = unpack

-- ================================================================== animations
UI.Ease = {
  linear = function(p) return p end,
  out = function(p) local q = 1 - p; return 1 - q * q * q end,
  inOut = function(p)
    if p < 0.5 then return 4 * p * p * p end
    local q = -2 * p + 2
    return 1 - q * q * q / 2
  end,
  back = function(p) local q = p - 1; return 1 + 2.70158 * q * q * q + 1.70158 * q * q end,
}

local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
  local i = 1
  while i <= #tweens do
    local tw = tweens[i]
    if tw.dead then
      table.remove(tweens, i)
    else
      tw.e = tw.e + elapsed
      local p = tw.d > 0 and min(1, tw.e / tw.d) or 1
      local ok, err = pcall(tw.fn, tw.ease(p), p)
      if not ok then ns.Report(err) end
      if p >= 1 or not ok then
        tw.dead = true
        table.remove(tweens, i)
        if tw.done then ns.SafeCall(tw.done) end
      else
        i = i + 1
      end
    end
  end
  if #tweens == 0 then driver:Hide() end
end)

function UI.StopTween(owner, key)
  for _, tw in ipairs(tweens) do
    if tw.owner == owner and (key == nil or tw.key == key) then tw.dead = true end
  end
end

function UI.Tween(owner, key, duration, fn, done, ease)
  UI.StopTween(owner, key)
  tweens[#tweens + 1] = { owner = owner, key = key, d = duration, e = 0, fn = fn, done = done, ease = ease or UI.Ease.out }
  driver:Show()
end

-- ================================================================== couleurs
function UI.SetColor(tex, c, alpha)
  tex:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

function UI.SetTextColor(fs, c, alpha)
  fs:SetTextColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

function UI.Alpha(c, a)
  return { c[1], c[2], c[3], a }
end

function UI.FadeColor(obj, to, duration)
  local from = obj.c or to
  local f1, f2, f3, f4 = from[1], from[2], from[3], from[4] or 1
  local t1, t2, t3, t4 = to[1], to[2], to[3], to[4] or 1
  UI.Tween(obj, "color", duration or 0.15, function(p)
    obj:SetColor(f1 + (t1 - f1) * p, f2 + (t2 - f2) * p, f3 + (t3 - f3) * p, f4 + (t4 - f4) * p)
  end)
end

-- ================================================================== formes
local CORNER = UI.Media("corner")

-- Rectangle arrondi dessiné avec 4 coins + 3 bandes, teinté par SetColor.
function UI.Round(frame, radius, color, layer, sublevel, inset)
  inset = inset or 0
  layer = layer or "BACKGROUND"
  sublevel = sublevel or 0
  local r = { parts = {} }
  local function tex()
    local t = frame:CreateTexture(nil, layer, nil, sublevel)
    r.parts[#r.parts + 1] = t
    return t
  end
  local tl, tr, bl, br = tex(), tex(), tex(), tex()
  for _, c in ipairs({ tl, tr, bl, br }) do
    c:SetTexture(CORNER)
    c:SetSize(radius, radius)
  end
  tl:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset);          tl:SetTexCoord(0, 1, 0, 1)
  tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset);       tr:SetTexCoord(1, 0, 0, 1)
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset);     bl:SetTexCoord(0, 1, 1, 0)
  br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset);  br:SetTexCoord(1, 0, 1, 0)
  local top, mid, bot = tex(), tex(), tex()
  for _, t in ipairs({ top, mid, bot }) do t:SetTexture(UI.WHITE) end
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  mid:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); mid:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  r.corners = { tl, tr, bl, br }

  function r:SetColor(cr, cg, cb, ca)
    self.c = { cr, cg, cb, ca or 1 }
    for _, t in ipairs(self.parts) do t:SetVertexColor(cr, cg, cb, ca or 1) end
  end
  function r:SetShown(show)
    for _, t in ipairs(self.parts) do t:SetShown(show) end
  end
  function r:Show() self:SetShown(true) end
  function r:Hide() self:SetShown(false) end
  function r:SetRadius(rad)
    for _, c in ipairs(self.corners) do c:SetSize(rad, rad) end
  end

  color = color or C.card
  r:SetColor(color[1], color[2], color[3], color[4])
  return r
end

-- Ombre portée douce autour d'un cadre (9 morceaux d'une même texture).
function UI.Shadow(frame, size, alpha, dy)
  size, alpha, dy = size or 20, alpha or 0.5, dy or -3
  local k = 24 / 64
  local tex = UI.Media("shadow")
  local inset = floor(size * 0.35)
  local function piece(l, r, t, b)
    local p = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    p:SetTexture(tex)
    p:SetTexCoord(l, r, t, b)
    p:SetVertexColor(1, 1, 1, alpha)
    return p
  end
  local tl, tr = piece(0, k, 0, k), piece(1 - k, 1, 0, k)
  local bl, br = piece(0, k, 1 - k, 1), piece(1 - k, 1, 1 - k, 1)
  for _, p in ipairs({ tl, tr, bl, br }) do p:SetSize(size, size) end
  tl:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", inset, -inset + dy)
  tr:SetPoint("BOTTOMLEFT", frame, "TOPRIGHT", -inset, -inset + dy)
  bl:SetPoint("TOPRIGHT", frame, "BOTTOMLEFT", inset, inset + dy)
  br:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", -inset, inset + dy)
  local top, bottom = piece(k, 1 - k, 0, k), piece(k, 1 - k, 1 - k, 1)
  local left, right = piece(0, k, k, 1 - k), piece(1 - k, 1, k, 1 - k)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  return { tl, tr, bl, br, top, bottom, left, right }
end

function UI.Line(parent, color, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(UI.WHITE)
  UI.SetColor(t, color or C.line)
  return t
end

-- ================================================================== texte et icônes
function UI.Text(parent, size, color, font, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(font or T.font.body, size or 13, "")
  UI.SetTextColor(fs, color or C.text)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  fs:SetShadowOffset(0, -1)
  fs:SetShadowColor(0, 0, 0, 0.45)
  return fs
end

function UI.Title(parent, size, color)
  return UI.Text(parent, size or 15, color, T.font.title)
end

function UI.Caps(parent, text, color)
  local fs = UI.Text(parent, 10, color or C.faint, T.font.title)
  fs:SetText(text or "")
  return fs
end

function UI.Glyph(parent, name, size, color, layer, sublevel)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
  t:SetTexture(UI.Icon(name))
  t:SetSize(size, size)
  UI.SetColor(t, color or C.text)
  return t
end

-- ================================================================== conteneurs
function UI.Card(parent, opts)
  opts = opts or {}
  local f = CreateFrame(opts.button and "Button" or "Frame", nil, parent)
  local radius = opts.radius or 10
  f.edge = UI.Round(f, radius, opts.edge or C.edge, "BACKGROUND", 0)
  f.fill = UI.Round(f, radius - 1, opts.fill or C.card, "BACKGROUND", 1, 1)
  return f
end

-- Survol doux : fond invisible qui apparaît sous la souris.
function UI.Hoverable(frame, radius, normal, hover)
  normal = normal or { 1, 1, 1, 0 }
  hover = hover or C.hover
  frame.hoverBg = UI.Round(frame, radius or 8, normal, "BACKGROUND", 0)
  frame:HookScript("OnEnter", function(self)
    if not self.selected then UI.FadeColor(self.hoverBg, hover, 0.1) end
  end)
  frame:HookScript("OnLeave", function(self)
    if not self.selected then UI.FadeColor(self.hoverBg, normal, 0.2) end
  end)
  function frame:SetSelected(on, color)
    self.selected = on
    local c = on and (color or C.accentDim) or normal
    self.hoverBg:SetColor(c[1], c[2], c[3], c[4])
  end
  return frame
end

-- ================================================================== infobulles
function UI.Tip(frame, fill, anchor)
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
    local ok, err = pcall(fill, GameTooltip, self)
    if not ok then ns.Report(err) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.ShowTip(owner, text, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_TOP")
  GameTooltip:SetText(text, 1, 1, 1, 1, true)
  GameTooltip:Show()
end

-- ================================================================== boutons
local STYLES = {
  primary = { bg = C.accent, hover = { 1, 0.65, 0.38, 1 }, text = C.ink },
  secondary = { bg = C.cardHi, hover = { 0.205, 0.222, 0.272, 1 }, text = C.text },
  ghost = { bg = { 1, 1, 1, 0 }, hover = { 1, 1, 1, 0.07 }, text = C.muted, hoverText = C.text },
  danger = { bg = { 0.96, 0.38, 0.38, 0.13 }, hover = { 0.96, 0.38, 0.38, 0.24 }, text = C.bad },
}

function UI.Button(parent, opts)
  local style = STYLES[opts.style or "secondary"]
  local b = CreateFrame("Button", nil, parent)
  local h = opts.h or 30
  b:SetHeight(h)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.bg = UI.Round(b, min(opts.radius or 8, h / 2), style.bg)
  b.label = UI.Text(b, opts.size or 13, style.text, opts.font)
  if opts.icon then b.icon = UI.Glyph(b, opts.icon, opts.iconSize or 14, style.text) end
  local pad = opts.pad or 14

  function b:Layout()
    local tw = self.label:GetText() and self.label:GetStringWidth() or 0
    local iw = self.icon and (self.icon:GetWidth() + (tw > 0 and 7 or 0)) or 0
    local w = opts.w or ceil(tw + iw + pad * 2)
    self:SetWidth(w)
    local x = floor((w - (tw + iw)) / 2)
    if self.icon then
      self.icon:ClearAllPoints()
      self.icon:SetPoint("LEFT", self, "LEFT", x, 0)
    end
    self.label:ClearAllPoints()
    self.label:SetPoint("LEFT", self, "LEFT", x + iw, 0)
  end
  function b:SetText(text)
    self.label:SetText(text or "")
    self:Layout()
  end
  function b:SetDisabled(flag)
    self.disabled = flag and true or false
    self:SetAlpha(self.disabled and 0.4 or 1)
  end
  local function paint(textColor)
    UI.SetTextColor(b.label, textColor)
    if b.icon then UI.SetColor(b.icon, textColor) end
  end

  b:SetScript("OnEnter", function(self)
    if self.disabled then return end
    UI.FadeColor(self.bg, style.hover, 0.12)
    if style.hoverText then paint(style.hoverText) end
    if opts.tooltip then UI.ShowTip(self, opts.tooltip) end
  end)
  b:SetScript("OnLeave", function(self)
    UI.FadeColor(self.bg, style.bg, 0.2)
    paint(style.text)
    GameTooltip:Hide()
  end)
  b:SetScript("OnMouseDown", function(self) if not self.disabled then self:SetAlpha(0.82) end end)
  b:SetScript("OnMouseUp", function(self) self:SetAlpha(self.disabled and 0.4 or 1) end)
  b:SetScript("OnClick", function(self, button)
    if self.disabled then return end
    U.Click()
    if opts.onClick then opts.onClick(self, button) end
  end)
  b:SetText(opts.text)
  return b
end

function UI.IconButton(parent, glyph, opts)
  opts = opts or {}
  local size = opts.size or 28
  local normal = opts.color or C.muted
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.bg = UI.Round(b, opts.radius or min(7, size / 2), { 1, 1, 1, 0 })
  b.icon = UI.Glyph(b, glyph, opts.iconSize or 14, normal)
  b.icon:SetPoint("CENTER")
  b:SetScript("OnEnter", function(self)
    UI.FadeColor(self.bg, { 1, 1, 1, 0.08 }, 0.1)
    UI.SetColor(self.icon, opts.hoverColor or C.text)
    if opts.tooltip then UI.ShowTip(self, opts.tooltip) end
  end)
  b:SetScript("OnLeave", function(self)
    UI.FadeColor(self.bg, { 1, 1, 1, 0 }, 0.2)
    UI.SetColor(self.icon, self.color or normal)
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function(self, button)
    U.Click()
    if opts.onClick then opts.onClick(self, button) end
  end)
  function b:SetGlyph(name) self.icon:SetTexture(UI.Icon(name)) end
  function b:SetGlyphColor(c) self.color = c; UI.SetColor(self.icon, c) end
  return b
end

-- ================================================================== interrupteur
function UI.Toggle(parent, value, onChange)
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(34, 20)
  t.track = UI.Round(t, 10, C.edge)
  t.knob = t:CreateTexture(nil, "ARTWORK")
  t.knob:SetTexture(UI.Media("circle"))
  t.knob:SetSize(14, 14)
  t.knob:SetVertexColor(1, 1, 1, 1)
  function t:SetValue(v, animate)
    self.value = v and true or false
    local x1 = self.value and 17 or 3
    local target = self.value and C.accent or C.edge
    if animate then
      local x0 = self.kx or x1
      UI.Tween(self, "knob", 0.18, function(p)
        self.kx = x0 + (x1 - x0) * p
        self.knob:SetPoint("LEFT", self, "LEFT", self.kx, 0)
      end)
      UI.FadeColor(self.track, target, 0.18)
    else
      self.kx = x1
      self.knob:SetPoint("LEFT", self, "LEFT", x1, 0)
      self.track:SetColor(target[1], target[2], target[3], target[4])
    end
  end
  t:SetScript("OnClick", function(self)
    U.Click()
    self:SetValue(not self.value, true)
    if onChange then onChange(self.value) end
  end)
  t:SetValue(value)
  return t
end

-- ================================================================== sélecteur segmenté
function UI.Segmented(parent, items, value, onChange, opts)
  opts = opts or {}
  local h = opts.h or 28
  local s = CreateFrame("Frame", nil, parent)
  s:SetHeight(h)
  s.bg = UI.Round(s, 8, opts.bg or C.shell)
  s.pill = CreateFrame("Frame", nil, s)
  s.pill:SetHeight(h - 6)
  s.pill:SetFrameLevel(s:GetFrameLevel() + 1)
  s.pill.bg = UI.Round(s.pill, 6, C.cardHi)
  s.buttons = {}
  local x = 3
  for i, item in ipairs(items) do
    local b = CreateFrame("Button", nil, s)
    b:SetFrameLevel(s:GetFrameLevel() + 2)
    b.label = UI.Text(b, opts.size or 12, C.muted)
    b.label:SetText(item.label)
    b.label:SetPoint("CENTER")
    local w = ceil(b.label:GetStringWidth()) + (opts.pad or 22)
    b:SetSize(w, h - 6)
    b:SetPoint("LEFT", s, "LEFT", x, 0)
    b.value, b.x, b.w = item.value, x, w
    x = x + w
    b:SetScript("OnClick", function()
      if s.value == item.value then return end
      U.Click()
      s:SetValue(item.value, true)
      if onChange then onChange(item.value) end
    end)
    b:SetScript("OnEnter", function() if s.value ~= item.value then UI.SetTextColor(b.label, C.text) end end)
    b:SetScript("OnLeave", function() if s.value ~= item.value then UI.SetTextColor(b.label, C.muted) end end)
    s.buttons[i] = b
  end
  s:SetWidth(x + 3)

  function s:SetValue(v, animate)
    self.value = v
    for _, b in ipairs(self.buttons) do
      local on = b.value == v
      UI.SetTextColor(b.label, on and C.text or C.muted)
      if on then
        local x0, w0 = self.px or b.x, self.pw or b.w
        if animate then
          UI.Tween(self, "pill", 0.22, function(p)
            self.px, self.pw = x0 + (b.x - x0) * p, w0 + (b.w - w0) * p
            self.pill:SetPoint("LEFT", self, "LEFT", self.px, 0)
            self.pill:SetWidth(self.pw)
          end)
        else
          self.px, self.pw = b.x, b.w
          self.pill:SetPoint("LEFT", self, "LEFT", b.x, 0)
          self.pill:SetWidth(b.w)
        end
      end
    end
  end
  s:SetValue(value)
  return s
end

-- ================================================================== champ de saisie
function UI.Input(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(opts.h or 32)
  f.edge = UI.Round(f, 8, C.edge)
  f.fill = UI.Round(f, 7, C.shell, "BACKGROUND", 1, 1)
  local left = 11
  if opts.icon then
    f.icon = UI.Glyph(f, opts.icon, 14, C.faint)
    f.icon:SetPoint("LEFT", 11, 0)
    left = 32
  end
  local eb = CreateFrame("EditBox", nil, f)
  eb:SetPoint("TOPLEFT", f, "TOPLEFT", left, 0)
  eb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", opts.noClear and -8 or -26, 0)
  eb:SetFont(T.font.body, opts.size or 13, "")
  eb:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(opts.max or 64)
  if opts.numeric then eb:SetNumeric(true) end
  if opts.justify then eb:SetJustifyH(opts.justify) end
  f.eb = eb

  f.ph = UI.Text(f, opts.size or 13, C.faint)
  f.ph:SetPoint("LEFT", eb, "LEFT", opts.justify == "CENTER" and 0 or 1, 0)
  if opts.justify == "CENTER" then f.ph:SetPoint("RIGHT", eb, "RIGHT"); f.ph:SetJustifyH("CENTER") end
  f.ph:SetText(opts.placeholder or "")

  if not opts.noClear then
    f.clear = UI.IconButton(f, "close", { size = 20, iconSize = 10, onClick = function()
      eb:SetText("")
      eb:ClearFocus()
    end })
    f.clear:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  end

  local function refresh()
    local empty = eb:GetText() == ""
    f.ph:SetShown(empty)
    if f.clear then f.clear:SetShown(not empty) end
  end
  eb:SetScript("OnEditFocusGained", function()
    UI.FadeColor(f.edge, C.accent, 0.15)
    if f.icon then UI.SetColor(f.icon, C.accent) end
  end)
  eb:SetScript("OnEditFocusLost", function()
    UI.FadeColor(f.edge, C.edge, 0.2)
    if f.icon then UI.SetColor(f.icon, C.faint) end
  end)
  eb:SetScript("OnTextChanged", function(self, user)
    refresh()
    if opts.onChange then opts.onChange(self:GetText(), user) end
  end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    if opts.onEnter then opts.onEnter(self:GetText()) end
    self:ClearFocus()
  end)
  f:EnableMouse(true)
  f:SetScript("OnMouseDown", function() eb:SetFocus() end)

  function f:GetText() return eb:GetText() end
  function f:SetText(text) eb:SetText(text or ""); refresh() end
  function f:Insert(text) eb:Insert(text) end
  function f:HasFocus() return eb:HasFocus() end
  refresh()
  return f
end

-- ================================================================== avatars et icônes
local function addMask(frame, tex, file)
  if not frame.CreateMaskTexture then return end
  local mask = frame:CreateMaskTexture()
  mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(tex)
  tex:AddMaskTexture(mask)
end

function UI.Avatar(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  f.bg:SetTexture(UI.Media("circle"))
  f.bg:SetAllPoints()
  f.icon = f:CreateTexture(nil, "ARTWORK")
  local pad = max(2, floor(size * 0.1))
  f.icon:SetPoint("TOPLEFT", pad, -pad)
  f.icon:SetPoint("BOTTOMRIGHT", -pad, pad)
  addMask(f, f.icon, UI.Media("circle"))
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetTexture(UI.Media("ring"))
  f.ring:SetAllPoints()

  local d = max(8, floor(size * 0.27))
  f.dotBg = f:CreateTexture(nil, "OVERLAY", nil, 1)
  f.dotBg:SetTexture(UI.Media("circle"))
  f.dotBg:SetSize(d + 4, d + 4)
  f.dotBg:SetPoint("CENTER", f, "BOTTOMRIGHT", -floor(d * 0.4), floor(d * 0.4))
  UI.SetColor(f.dotBg, C.surface)
  f.dot = f:CreateTexture(nil, "OVERLAY", nil, 2)
  f.dot:SetTexture(UI.Media("circle"))
  f.dot:SetSize(d, d)
  f.dot:SetPoint("CENTER", f.dotBg)

  function f:SetDotBackground(c) UI.SetColor(self.dotBg, c, 1) end
  function f:SetMember(m, online, showDot)
    local class = m and m.class
    local r, g, b = U.ClassColor(class)
    local l, rr, t, bb = U.ClassCoords(class)
    if l then
      self.icon:SetTexture(U.CLASS_TEXTURE)
      self.icon:SetTexCoord(l, rr, t, bb)
    else
      self.icon:SetTexture(U.QUESTION)
      self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    self.bg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 1)
    self.icon:SetDesaturated(not online)
    self.icon:SetAlpha(online and 1 or 0.6)
    self.ring:SetVertexColor(r, g, b, online and 0.95 or 0.28)
    local show = showDot ~= false
    self.dot:SetShown(show)
    self.dotBg:SetShown(show)
    if m and m.dead and online then UI.SetColor(self.dot, C.bad)
    elseif online then UI.SetColor(self.dot, C.good)
    else UI.SetColor(self.dot, C.faint) end
  end
  return f
end

function UI.ItemIcon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  local radius = max(4, floor(size * 0.24))
  f.border = UI.Round(f, radius, C.edge, "BACKGROUND", 2)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOPLEFT", 2, -2)
  f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  addMask(f, f.icon, UI.Media("roundsq"))
  function f:SetItem(texture, quality, desaturate)
    self.icon:SetTexture(texture or U.QUESTION)
    self.icon:SetDesaturated(desaturate and true or false)
    if quality and quality >= 2 then
      local r, g, b = U.QualityColor(quality)
      self.border:SetColor(r, g, b, 0.95)
    else
      self.border:SetColor(C.edge[1], C.edge[2], C.edge[3], 1)
    end
  end
  return f
end

-- Pastille ronde avec glyphe (icônes d'événements).
function UI.Badge(parent, size, glyph)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  f.bg:SetTexture(UI.Media("circle"))
  f.bg:SetAllPoints()
  f.glyph = UI.Glyph(f, glyph or "star", floor(size * 0.5), C.text)
  f.glyph:SetPoint("CENTER")
  function f:Set(g, color)
    self.glyph:SetTexture(UI.Icon(g))
    UI.SetColor(self.glyph, color)
    self.bg:SetVertexColor(color[1], color[2], color[3], 0.16)
  end
  return f
end

-- ================================================================== barres, puces
function UI.Progress(parent, h, color)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(h)
  f.track = UI.Round(f, h / 2, { 1, 1, 1, 0.07 })
  f.fillFrame = CreateFrame("Frame", nil, f)
  f.fillFrame:SetPoint("TOPLEFT")
  f.fillFrame:SetPoint("BOTTOMLEFT")
  f.fill = UI.Round(f.fillFrame, h / 2, color or C.accent)
  f.shown = 0
  function f:Apply(v)
    local w = self:GetWidth() or 0
    if v <= 0 or w <= 0 then
      self.fillFrame:Hide()
      return
    end
    self.fillFrame:Show()
    self.fillFrame:SetWidth(max(h, w * v))
  end
  function f:SetValue(v, animate)
    v = U.Clamp(v or 0, 0, 1)
    local from = self.shown or 0
    if animate and math.abs(v - from) > 0.002 then
      UI.Tween(self, "value", 0.6, function(p)
        self.shown = from + (v - from) * p
        self:Apply(self.shown)
      end)
    else
      UI.StopTween(self, "value")
      self.shown = v
      self:Apply(v)
    end
  end
  function f:SetColor(c) self.fill:SetColor(c[1], c[2], c[3], c[4] or 1) end
  f:SetScript("OnSizeChanged", function(self) self:Apply(self.shown or 0) end)
  return f
end

function UI.Chip(parent, h)
  h = h or 20
  local c = CreateFrame("Frame", nil, parent)
  c:SetHeight(h)
  c.bg = UI.Round(c, h / 2, { 1, 1, 1, 0.06 })
  c.text = UI.Text(c, 11, C.muted)
  function c:Set(text, color, glyph)
    local col = color or C.muted
    self.text:SetText(text or "")
    UI.SetTextColor(self.text, col)
    self.bg:SetColor(col[1], col[2], col[3], 0.14)
    local w = ceil(self.text:GetStringWidth()) + 16
    if glyph then
      if not self.glyph then self.glyph = UI.Glyph(self, glyph, 10, col) end
      self.glyph:SetTexture(UI.Icon(glyph))
      UI.SetColor(self.glyph, col)
      self.glyph:Show()
      self.glyph:ClearAllPoints()
      self.glyph:SetPoint("LEFT", self, "LEFT", 8, 0)
      self.text:ClearAllPoints()
      self.text:SetPoint("LEFT", self.glyph, "RIGHT", 4, 0)
      w = w + 14
    else
      if self.glyph then self.glyph:Hide() end
      self.text:ClearAllPoints()
      self.text:SetPoint("CENTER")
    end
    self:SetWidth(w)
  end
  return c
end

-- ================================================================== état vide
function UI.Empty(parent, glyph, title, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(340, 150)
  f:SetPoint("CENTER", parent, "CENTER", 0, 10)
  f.circle = f:CreateTexture(nil, "ARTWORK")
  f.circle:SetTexture(UI.Media("circle"))
  f.circle:SetSize(64, 64)
  f.circle:SetPoint("TOP", 0, 0)
  UI.SetColor(f.circle, C.card)
  f.glyph = UI.Glyph(f, glyph or "star", 26, C.faint, "OVERLAY")
  f.glyph:SetPoint("CENTER", f.circle)
  f.title = UI.Title(f, 14, C.text)
  f.title:SetPoint("TOP", f.circle, "BOTTOM", 0, -14)
  f.text = UI.Text(f, 12, C.muted)
  f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
  f.text:SetWidth(320)
  f.text:SetWordWrap(true)
  f.text:SetJustifyH("CENTER")
  function f:Set(g, t, x)
    if g then self.glyph:SetTexture(UI.Icon(g)) end
    self.title:SetText(t or "")
    self.text:SetText(x or "")
  end
  f:Set(glyph, title, text)
  f:Hide()
  return f
end

-- ================================================================== liste virtualisée (hauteurs variables)
function UI.List(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  if f.SetClipsChildren then f:SetClipsChildren(true) end
  f.data, f.pos, f.heights = {}, {}, {}
  f.total, f.offset, f.target, f.ver = 0, 0, 0, 0
  f.active, f.pools = {}, {}
  f.gap = opts.gap or 4
  f:EnableMouseWheel(true)

  f.bar = CreateFrame("Frame", nil, f)
  f.bar:SetWidth(4)
  f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  f.bar:SetFrameLevel(f:GetFrameLevel() + 30)
  f.thumb = CreateFrame("Frame", nil, f.bar)
  f.thumb:SetWidth(4)
  f.thumb:EnableMouse(true)
  f.thumb.bg = UI.Round(f.thumb, 2, { 1, 1, 1, 0.16 })
  f.thumb:SetScript("OnEnter", function(t) UI.FadeColor(t.bg, { 1, 1, 1, 0.32 }, 0.1) end)
  f.thumb:SetScript("OnLeave", function(t) UI.FadeColor(t.bg, { 1, 1, 1, 0.16 }, 0.2) end)
  f.thumb:SetScript("OnMouseDown", function(t)
    local scale = t:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    t.startY, t.startOff = cy / scale, f.offset
    t:SetScript("OnUpdate", function()
      local _, y = GetCursorPosition()
      y = y / scale
      local room = f.bar:GetHeight() - t:GetHeight()
      if room > 0 then f:ScrollTo(t.startOff + (t.startY - y) * f:MaxScroll() / room, true) end
    end)
  end)
  f.thumb:SetScript("OnMouseUp", function(t) t:SetScript("OnUpdate", nil) end)

  if opts.empty then f.empty = UI.Empty(f, opts.empty.glyph, opts.empty.title, opts.empty.text) end

  function f:KindOf(item) return opts.kind and opts.kind(item) or "row" end
  function f:HeightOf(item, kind) return (opts.height and opts.height(item, kind)) or opts.rowHeight or 40 end
  function f:MaxScroll() return max(0, self.total - (self:GetHeight() or 0)) end
  function f:Clamp()
    local m = self:MaxScroll()
    self.target = U.Clamp(self.target, 0, m)
    self.offset = U.Clamp(self.offset, 0, m)
  end

  function f:Acquire(kind)
    local pool = self.pools[kind]
    if not pool then pool = {}; self.pools[kind] = pool end
    local row = table.remove(pool)
    if not row then
      row = opts.create(self, kind)
      row.kind = kind
    end
    return row
  end
  function f:Release(idx)
    local row = self.active[idx]
    if not row then return end
    row:Hide()
    self.active[idx] = nil
    local pool = self.pools[row.kind]
    pool[#pool + 1] = row
  end
  function f:ReleaseAll()
    local keys = {}
    for idx in pairs(self.active) do keys[#keys + 1] = idx end
    for _, idx in ipairs(keys) do self:Release(idx) end
  end

  function f:SetData(data, keepScroll)
    self.data = data or {}
    self.ver = self.ver + 1
    local y = 0
    for i, item in ipairs(self.data) do
      local h = self:HeightOf(item, self:KindOf(item))
      self.pos[i], self.heights[i] = y, h
      y = y + h + self.gap
    end
    for i = #self.data + 1, #self.pos do self.pos[i], self.heights[i] = nil, nil end
    self.total = max(0, y - self.gap)
    self:ReleaseAll()
    if not keepScroll then self.offset, self.target = 0, 0 end
    self:Clamp()
    self:Layout()
    if self.empty then self.empty:SetShown(#self.data == 0) end
  end

  function f:Layout()
    local h = self:GetHeight() or 0
    local top, bottom = self.offset, self.offset + h
    local first, last
    for i = 1, #self.data do
      local y, ih = self.pos[i], self.heights[i]
      if y + ih >= top and y <= bottom then
        first = first or i
        last = i
      elseif first then
        break
      end
    end
    local stale = {}
    for idx in pairs(self.active) do
      if not first or idx < first or idx > last then stale[#stale + 1] = idx end
    end
    for _, idx in ipairs(stale) do self:Release(idx) end
    local scrollable = self.total > h + 0.5
    if first then
      local inset = scrollable and 12 or 0
      for i = first, last do
        local row = self.active[i]
        local fresh = false
        if not row then
          row = self:Acquire(self:KindOf(self.data[i]))
          self.active[i] = row
          fresh = true
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -floor(self.pos[i] - self.offset + 0.5))
        row:SetPoint("RIGHT", self, "RIGHT", -inset, 0)
        row:SetHeight(self.heights[i])
        if fresh or row.ver ~= self.ver then
          row.ver = self.ver
          local ok, err = pcall(opts.update, row, self.data[i], i)
          if not ok then ns.Report(err) end
        end
        row:Show()
      end
    end
    if scrollable then
      self.bar:Show()
      local bh = self.bar:GetHeight()
      local th = max(28, bh * h / self.total)
      self.thumb:SetHeight(th)
      self.thumb:ClearAllPoints()
      self.thumb:SetPoint("TOP", self.bar, "TOP", 0, -((bh - th) * self.offset / max(1, self:MaxScroll())))
    else
      self.bar:Hide()
    end
  end

  function f:ScrollTo(y, instant)
    self.target = U.Clamp(y, 0, self:MaxScroll())
    if instant then
      UI.StopTween(self, "scroll")
      self.offset = self.target
      self:Layout()
      return
    end
    local from, to = self.offset, self.target
    UI.Tween(self, "scroll", 0.25, function(p)
      self.offset = from + (to - from) * p
      self:Layout()
    end)
  end

  -- Rafraîchit le contenu des lignes visibles sans changer les données.
  function f:Refresh()
    self.ver = self.ver + 1
    self:Layout()
  end

  f:SetScript("OnMouseWheel", function(self, delta)
    self:ScrollTo(self.target - delta * (opts.wheelStep or 72))
  end)
  f:SetScript("OnSizeChanged", function(self)
    self:Clamp()
    self:Refresh()   -- les lignes recalculent leurs colonnes à la nouvelle largeur
  end)
  return f
end

-- ================================================================== menu contextuel / liste déroulante
local menu
local function buildMenu()
  menu = CreateFrame("Frame", nil, UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetFrameLevel(50)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:Hide()
  UI.Shadow(menu, 18, 0.55)
  menu.edge = UI.Round(menu, 9, C.edge, "BACKGROUND", 0)
  menu.fill = UI.Round(menu, 8, C.cardHi, "BACKGROUND", 1, 1)
  menu.rows = {}

  menu.catcher = CreateFrame("Button", nil, UIParent)
  menu.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  menu.catcher:SetFrameLevel(40)
  menu.catcher:SetAllPoints(UIParent)
  menu.catcher:RegisterForClicks("AnyUp")
  menu.catcher:SetScript("OnClick", function() UI.CloseMenu() end)
  menu.catcher:Hide()
end

function UI.CloseMenu()
  if not menu or not menu:IsShown() then return end
  menu:Hide()
  menu.catcher:Hide()
end

-- items : { { label, glyph, color, checked, onClick }, … } ; « - » insère un séparateur.
function UI.Menu(anchor, items, opts)
  opts = opts or {}
  if not menu then buildMenu() end
  for _, row in ipairs(menu.rows) do row:Hide() end
  local y, width = 6, opts.width or 150
  local n = 0
  for _, item in ipairs(items) do
    n = n + 1
    local row = menu.rows[n]
    if not row then
      row = CreateFrame("Button", nil, menu)
      row:SetHeight(28)
      UI.Hoverable(row, 6)
      row.glyph = UI.Glyph(row, "check", 12, C.muted)
      row.glyph:SetPoint("LEFT", 10, 0)
      row.label = UI.Text(row, 13, C.text)
      row.label:SetPoint("LEFT", 30, 0)
      row.sep = UI.Line(row)
      row.sep:SetHeight(1)
      row.sep:SetPoint("LEFT", 8, 0)
      row.sep:SetPoint("RIGHT", -8, 0)
      menu.rows[n] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -y)
    row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
    if item == "-" then
      row:SetHeight(9)
      row.sep:Show(); row.glyph:Hide(); row.label:Hide()
      row:EnableMouse(false)
      y = y + 9
    else
      row:SetHeight(28)
      row.sep:Hide(); row.label:Show()
      row:EnableMouse(true)
      row.label:SetText(item.label)
      local color = item.color or C.text
      UI.SetTextColor(row.label, color)
      local glyph = item.glyph or (item.checked and "check")
      if glyph then
        row.glyph:SetTexture(UI.Icon(glyph))
        UI.SetColor(row.glyph, item.checked and C.accent or (item.color or C.muted))
        row.glyph:Show()
      else
        row.glyph:Hide()
      end
      width = max(width, ceil(row.label:GetStringWidth()) + 50)
      row:SetScript("OnClick", function()
        U.Click()
        UI.CloseMenu()
        if item.onClick then item.onClick() end
      end)
      y = y + 28
    end
    row:Show()
  end
  menu:SetSize(width, y + 6)
  menu:ClearAllPoints()
  if opts.cursor then
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 2, cy / scale - 2)
  else
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
  end
  menu.catcher:Show()
  menu:SetAlpha(0)
  menu:Show()
  UI.Tween(menu, "fade", 0.12, function(p) menu:SetAlpha(p) end)
end

function UI.Dropdown(parent, opts)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(opts.w or 160, opts.h or 28)
  b.edge = UI.Round(b, 8, C.edge)
  b.fill = UI.Round(b, 7, C.shell, "BACKGROUND", 1, 1)
  b.label = UI.Text(b, 12, C.text)
  b.label:SetPoint("LEFT", 10, 0)
  b.label:SetPoint("RIGHT", -24, 0)
  b.chev = UI.Glyph(b, "chevdown", 12, C.muted)
  b.chev:SetPoint("RIGHT", -9, 0)
  function b:SetValue(v)
    self.value = v
    for _, item in ipairs(opts.items) do
      if item.value == v then self.label:SetText(item.label) end
    end
  end
  b:SetScript("OnEnter", function(self) UI.FadeColor(self.edge, C.faint, 0.1) end)
  b:SetScript("OnLeave", function(self) UI.FadeColor(self.edge, C.edge, 0.2) end)
  b:SetScript("OnClick", function(self)
    U.Click()
    local items = {}
    for _, item in ipairs(opts.items) do
      items[#items + 1] = {
        label = item.label, checked = item.value == self.value,
        onClick = function()
          self:SetValue(item.value)
          if opts.onChange then opts.onChange(item.value) end
        end,
      }
    end
    UI.Menu(self, items, { width = self:GetWidth() })
  end)
  b:SetValue(opts.value)
  return b
end

-- ================================================================== curseur
function UI.Slider(parent, opts)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(opts.w or 180, 20)
  s.track = CreateFrame("Frame", nil, s)
  s.track:SetHeight(4)
  s.track:SetPoint("LEFT", 0, 0)
  s.track:SetPoint("RIGHT", 0, 0)
  s.track.bg = UI.Round(s.track, 2, C.edge)
  s.fillF = CreateFrame("Frame", nil, s.track)
  s.fillF:SetPoint("TOPLEFT")
  s.fillF:SetPoint("BOTTOMLEFT")
  s.fillF.bg = UI.Round(s.fillF, 2, C.accent)
  s.knob = CreateFrame("Button", nil, s)
  s.knob:SetSize(16, 16)
  s.knob:SetFrameLevel(s:GetFrameLevel() + 3)
  s.knob.tex = s.knob:CreateTexture(nil, "ARTWORK")
  s.knob.tex:SetTexture(UI.Media("circle"))
  s.knob.tex:SetAllPoints()
  s.knob.ring = s.knob:CreateTexture(nil, "OVERLAY")
  s.knob.ring:SetTexture(UI.Media("ring"))
  s.knob.ring:SetAllPoints()
  UI.SetColor(s.knob.ring, C.accent)

  local lo, hi, step = opts.min or 0, opts.max or 1, opts.step or 0.05
  function s:SetValue(v, silent)
    v = U.Clamp(floor((v - lo) / step + 0.5) * step + lo, lo, hi)
    self.value = v
    local w = self.track:GetWidth() or 0
    local x = (hi > lo) and (v - lo) / (hi - lo) * w or 0
    self.knob:ClearAllPoints()
    self.knob:SetPoint("CENTER", self.track, "LEFT", x, 0)
    self.fillF:SetWidth(max(0.1, x))
    if not silent and opts.onChange then opts.onChange(v) end
  end
  local function fromCursor()
    local scale = s.track:GetEffectiveScale()
    local cx = GetCursorPosition() / scale
    local left, width = s.track:GetLeft() or 0, s.track:GetWidth() or 1
    s:SetValue(lo + (cx - left) / max(1, width) * (hi - lo))
  end
  s.knob:SetScript("OnMouseDown", function(k) k:SetScript("OnUpdate", fromCursor) end)
  s.knob:SetScript("OnMouseUp", function(k) k:SetScript("OnUpdate", nil); if opts.onRelease then opts.onRelease(s.value) end end)
  s:EnableMouse(true)
  s:SetScript("OnMouseDown", function() fromCursor() end)
  s:SetScript("OnSizeChanged", function(self) self:SetValue(self.value or lo, true) end)
  s:SetValue(opts.value or lo, true)
  return s
end

-- ================================================================== divers
-- Positionne une suite d'éléments les uns après les autres sur une ligne.
function UI.Flow(anchor, items, gap, point, relPoint)
  local prev
  for _, item in ipairs(items) do
    if item:IsShown() then
      item:ClearAllPoints()
      if prev then
        item:SetPoint("LEFT", prev, "RIGHT", gap or 6, 0)
      else
        item:SetPoint(point or "LEFT", anchor, relPoint or "LEFT", 0, 0)
      end
      prev = item
    end
  end
end

-- Confirmation modale (StaticPopup natif, fiable et accessible).
function UI.Confirm(text, onAccept, accept)
  StaticPopupDialogs["KEK_CONFIRM"] = {
    text = text, button1 = accept or YES or "Oui", button2 = CANCEL or "Annuler",
    OnAccept = function() ns.SafeCall(onAccept) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("KEK_CONFIRM")
end
