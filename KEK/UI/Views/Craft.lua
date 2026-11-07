-- KEK — vue « Atelier » : qui sait fabriquer quoi, et la liste des besoins de la bande.
local _, ns = ...
local L, U, UI = ns.L, ns.U, ns.UI
local C = UI.T.c

local NAMED_ICON = "Interface\\Icons\\INV_Misc_Note_01"   -- besoin indiqué par son nom

local View = { id = "craft", order = 6, label = L["Atelier"], title = L["Atelier"], glyph = "hammer" }

function View:Subtitle()
  if ns.db.ui.craftTab == "needs" then
    local n = #ns.Craft:AllNeeds()
    if n == 0 then return L["Personne n'a besoin de rien. Pour l'instant."] end
    return string.format(n == 1 and L["%d demande en cours"] or L["%d demandes en cours"], n)
  end
  local profs = ns.Craft:Professions()
  local recipes = #ns.Craft:Search("")
  return string.format(L["%d métier(s) · %d recette(s) connues dans la bande"], #profs, recipes)
end

function View:Badge()
  local n = 0
  for _, row in ipairs(ns.Craft:AllNeeds()) do
    if not row.mine and ns.Craft:OwnedFor(row.need) > 0 then n = n + 1 end
  end
  return n > 0 and n or nil
end

local function whisper(name, text)
  U.OpenChat("/w " .. name .. " " .. text)
end

local function crafterChips(row, crafters, maxChips, rightAnchor)
  for _, chip in ipairs(row.chips) do chip:Hide() end
  local prev
  local shown = math.min(#crafters, maxChips)
  for i = shown, 1, -1 do
    local c = crafters[i]
    local chip = row.chips[i]
    local m = ns.db.members[c.name]
    local r, g, b = U.ClassColor(m and m.class)
    chip:Set(U.Short(c.name) .. (c.rank and c.rank > 0 and (" " .. c.rank) or ""), { r, g, b, 1 })
    chip:ClearAllPoints()
    if prev then chip:SetPoint("RIGHT", prev, "LEFT", -6, 0) else chip:SetPoint("RIGHT", rightAnchor, "RIGHT", -14, 0) end
    chip:Show()
    prev = chip
  end
  if #crafters > maxChips then
    local more = row.chips[maxChips + 1]
    more:Set("+" .. (#crafters - maxChips), C.muted)
    more:ClearAllPoints()
    more:SetPoint("RIGHT", prev, "LEFT", -6, 0)
    more:Show()
  end
end

-- ================================================================== recettes
local function createRecipeRow(list, kind)
  local row = CreateFrame("Button", nil, list)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.Hoverable(row, 10)
  row.icon = UI.ItemIcon(row, kind == "prof" and 38 or 34)
  row.icon:SetPoint("LEFT", 10, 0)
  row.name = UI.Title(row, kind == "prof" and 14 or 13)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", kind == "prof" and 60 or 56, kind == "prof" and -14 or -10)
  row.sub = UI.Text(row, 11, C.faint)
  row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
  row.chips = {}
  for i = 1, 6 do row.chips[i] = UI.Chip(row, 20) end
  UI.Tip(row, function(tt, self)
    local item = self.item
    if not item then return end
    if item.id then
      pcall(tt.SetItemByID, tt, item.id)
    else
      tt:AddLine(item.name or item.prof, 1, 1, 1)
    end
    if item.crafters then
      tt:AddLine(" ")
      tt:AddLine(L["Qui sait le faire"], 1, 0.55, 0.24)
      for _, c in ipairs(item.crafters) do
        local m = ns.db.members[c.name]
        local r, g, b = U.ClassColor(m and m.class)
        tt:AddDoubleLine(U.Short(c.name), tostring(c.rank), r, g, b, 1, 1, 1)
      end
      local reagents = ns.Craft:ReagentsFor(item.name)
      if reagents then
        tt:AddLine(" ")
        tt:AddLine(L["Composants"], 1, 0.55, 0.24)
        for _, r in ipairs(reagents) do
          local have = ns.Craft:OwnedFor({ i = r.i, s = ns.Craft:ReagentName(r) })
          local enough = have >= (r.q or 1)
          tt:AddDoubleLine(string.format("%s ×%d", ns.Craft:ReagentName(r), r.q or 1), string.format(L["tu en as %d"], have),
            0.85, 0.85, 0.85, enough and 0.38 or 0.96, enough and 0.86 or 0.5, enough and 0.56 or 0.4)
        end
      else
        tt:AddLine(" ")
        tt:AddLine(L["Composants pas encore connus : ils arrivent quand l'artisan a KEK 1.10.1 ou plus et a ouvert une fois sa fenêtre de métier."], 0.6, 0.62, 0.68, true)
      end
      tt:AddLine(" ")
      tt:AddLine(L["Clic droit : demander à un artisan, demander les composants · Maj+clic : lien dans le chat"], 0.5, 0.52, 0.58, true)
    elseif item.people then
      tt:AddLine(" ")
      for _, p in ipairs(item.people) do
        local m = ns.db.members[p.name]
        local r, g, b = U.ClassColor(m and m.class)
        tt:AddDoubleLine(U.Short(p.name), string.format(L["%d / %d · %d recettes"], p.rank, p.max, p.count), r, g, b, 1, 1, 1)
      end
    end
  end, "ANCHOR_CURSOR")
  row:SetScript("OnClick", function(self, button)
    local item = self.item
    if not item then return end
    if item.prof and not item.crafters then
      View.profFilter = item.prof
      View.profDropdown:SetValue(item.prof)
      View:Refresh()
      return
    end
    if button == "LeftButton" and item.id and IsModifiedClick and IsModifiedClick("CHATLINK") then
      U.WithItemLink(item.id, function(link) if link then U.InsertLink(link) end end)
      return
    end
    if button == "RightButton" and item.crafters then
      local menu = {}
      for _, c in ipairs(item.crafters) do
        if c.name ~= ns.me then
          menu[#menu + 1] = { label = string.format(L["Demander à %s"], U.Short(c.name)), glyph = "chat", onClick = function()
            local link = item.id and select(2, U.GetItemInfo(item.id))
            whisper(c.name, string.format(L["Salut ! Tu pourrais me fabriquer %s ?"], link or ("[" .. item.name .. "]")))
          end }
        end
      end
      if item.id then
        menu[#menu + 1] = { label = L["Ajouter à mes besoins"], glyph = "plus", onClick = function()
          local _, link = U.GetItemInfo(item.id)
          ns.Craft:AddNeed(link or { id = item.id, name = item.name }, 1, "")
        end }
      end
      if ns.Craft:ReagentsFor(item.name) then
        menu[#menu + 1] = { label = L["Demander les composants qui me manquent"], glyph = "bag", onClick = function()
          View:RequestReagents(item.name, 1)
        end }
      end
      if #menu > 0 then UI.Menu(nil, menu, { cursor = true }) end
    end
  end)
  return row
end

local function updateRecipeRow(row, item)
  row.item = item
  if item.crafters then
    local q = item.id and U.ItemQuality(select(2, U.GetItemInfo(item.id)) or item.id)
    row.icon:SetItem(item.id and U.ItemIcon(item.id) or U.ProfIcon(item.prof), q)
    row.name:SetText(item.name)
    if q then
      local r, g, b = U.QualityColor(q)
      row.name:SetTextColor(r, g, b)
    else
      UI.SetTextColor(row.name, C.text)
    end
    row.sub:SetText(item.prof)
    row.name:SetWidth(row:GetWidth() * 0.5)
    crafterChips(row, item.crafters, 3, row)
  else
    row.icon:SetItem(U.ProfIcon(item.prof))
    row.name:SetText(item.prof)
    UI.SetTextColor(row.name, C.text)
    row.sub:SetText(item.recipes > 0 and string.format(L["%d recette(s) partagée(s)"], item.recipes) or L["ouvre ta fenêtre de métier pour partager tes recettes"])
    row.name:SetWidth(row:GetWidth() * 0.4)
    local people = {}
    for _, p in ipairs(item.people) do people[#people + 1] = { name = p.name, rank = p.rank } end
    crafterChips(row, people, 5, row)
  end
end

-- ================================================================== besoins
local function createNeedRow(list)
  local row = CreateFrame("Button", nil, list)
  UI.Hoverable(row, 10)
  row.icon = UI.ItemIcon(row, 40)
  row.icon:SetPoint("LEFT", 10, 0)
  row.name = UI.Title(row, 13)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 62, -12)
  row.qty = UI.Title(row, 13, C.muted)
  row.qty:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.dec = UI.IconButton(row, "minus", { size = 20, iconSize = 9, tooltip = L["Un de moins (Maj : 10)"] })
  row.dec:SetPoint("LEFT", row.qty, "RIGHT", 6, 0)
  row.inc = UI.IconButton(row, "plus", { size = 20, iconSize = 9, tooltip = L["Un de plus (Maj : 10)"] })
  row.inc:SetPoint("LEFT", row.dec, "RIGHT", 2, 0)
  row.who = UI.Text(row, 12, C.muted)
  row.who:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -6)
  row.chips = {}
  for i = 1, 4 do row.chips[i] = UI.Chip(row, 20) end
  row.action = UI.Button(row, { text = L["Proposer"], icon = "chat", style = "secondary", h = 26, size = 12 })
  row.action:SetPoint("RIGHT", row, "RIGHT", -12, 0)
  row.remove = UI.IconButton(row, "trash", { size = 28, iconSize = 13, tooltip = L["Retirer ce besoin"], hoverColor = C.bad })
  row.remove:SetPoint("RIGHT", row, "RIGHT", -12, 0)
  UI.Tip(row, function(tt, self)
    local data = self.data
    if not data then return end
    local need = data.need
    if need.k then
      pcall(tt.SetHyperlink, tt, need.k)
    elseif need.i then
      pcall(tt.SetItemByID, tt, need.i)
    else
      tt:AddLine(need.s or "?", 1, 1, 1)
      tt:AddLine(L["Objet indiqué par son nom : KEK le cherche dans les sacs, les banques et les recettes de la bande."], 0.7, 0.7, 0.75, true)
    end
    local _, detail = ns.Craft:OwnedFor(need)
    if #detail > 0 then
      tt:AddLine(" ")
      tt:AddLine(L["Sur tes personnages"], 1, 0.55, 0.24)
      for _, d in ipairs(detail) do tt:AddDoubleLine(U.Short(d.name), tostring(d.count), 0.85, 0.85, 0.85, 1, 1, 1) end
    end
  end, "ANCHOR_CURSOR")
  return row
end

local function updateNeedRow(row, data)
  row.data = data
  local need = data.need
  local text = (need.k or need.i) and U.ItemText(need.k, need.i, need.s) or (need.s or "?")
  local q = (need.k or need.i) and U.ItemQuality(need.k or need.i) or nil
  row.icon:SetItem(need.i and U.ItemIcon(need.i) or NAMED_ICON, q)
  row.name:SetText(text)
  row.name:SetWidth(math.min(row.name:GetStringWidth() + 4, row:GetWidth() * 0.42))
  row.qty:SetText("×" .. (need.q or 1))
  local who = data.mine and L["Ta demande"] or string.format(L["Demandé par %s"], U.MemberName(data.owner))
  who = who .. " · " .. U.Ago(need.t)
  if need.n then who = who .. " · « " .. need.n .. " »" end
  row.who:SetText(who)
  row.who:SetWidth(row:GetWidth() * 0.5)

  -- disponibilité : qui l'a, qui peut le fabriquer
  local chips = {}
  for _, h in ipairs(ns.Craft:Holders(data.owner, need)) do
    local label = h.mine and string.format(L["Tu en as %d"], h.count) or string.format(L["%s en a %d"], U.Short(h.name), h.count)
    chips[#chips + 1] = { label, C.good, "bag" }
  end
  for _, c in ipairs(ns.Craft:CraftersFor(need)) do
    if c.name ~= data.owner then
      chips[#chips + 1] = { c.name == ns.me and L["Tu sais le fabriquer"] or string.format(L["%s sait le faire"], U.Short(c.name)), C.info, "hammer" }
    end
  end
  if #chips == 0 then chips[1] = { L["personne pour l'instant"], C.faint } end
  local anchor = data.mine and row.remove or row.action
  local prev
  for i, chip in ipairs(row.chips) do
    local c = chips[i]
    if c and i <= 3 then
      chip:Set(c[1], c[2], c[3])
      chip:ClearAllPoints()
      if prev then chip:SetPoint("RIGHT", prev, "LEFT", -6, 0) else chip:SetPoint("RIGHT", anchor, "LEFT", -10, 0) end
      chip:Show()
      prev = chip
    else
      chip:Hide()
    end
  end

  row.remove:SetShown(data.mine)
  row.action:SetShown(not data.mine)
  row.dec:SetShown(data.mine)
  row.inc:SetShown(data.mine)
  local function step(delta)
    local n = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
    ns.Craft:SetNeedQty(ns.Craft.NeedKey(need), (need.q or 1) + delta * n)
  end
  row.dec:SetScript("OnClick", function() U.Click(); step(-1) end)
  row.inc:SetScript("OnClick", function() U.Click(); step(1) end)
  row.remove:SetScript("OnClick", function()
    U.Click()
    ns.Craft:RemoveNeed(ns.Craft.NeedKey(need))
  end)
  row.action:SetScript("OnClick", function()
    U.Click()
    local have = ns.Craft:OwnedFor(need)
    local link = need.k or (need.i and U.ItemText(nil, need.i, need.s)) or ("[" .. (need.s or "?") .. "]")
    if have > 0 then
      whisper(data.owner, string.format(L["J'ai %d %s pour toi !"], math.min(have, need.q or 1), link))
    else
      whisper(data.owner, string.format(L["Pour ta demande de %s :"], link))
    end
  end)
end

-- Zone d'ajout : nom tapé au clavier (avec suggestions), glisser-déposer ou Maj+clic sur un objet.
function View:ShowSuggestions(text)
  if not self.itemInput:HasFocus() or U.ItemID(text) then UI.CloseMenu() return end
  local list = ns.Craft:Suggest(text, 6)
  if #list == 0 or (#list == 1 and U.Fold(list[1].name) == U.Fold(text)) then UI.CloseMenu() return end
  local items = {}
  for _, e in ipairs(list) do
    if e.recipe then
      items[#items + 1] = { label = string.format(L["Composants : %s"], e.name), glyph = "hammer", onClick = function()
        self:SetRecipeDraft(e.recipe)
        self.qtyInput.eb:SetFocus()
      end }
    else
      items[#items + 1] = { label = e.name, glyph = "bag", onClick = function()
        self:SetDraft(e.link or e.id or e.name)
        self.qtyInput.eb:SetFocus()
      end }
    end
  end
  UI.Menu(self.itemInput, items, { width = 240 })
end

function View:BuildComposer(parent)
  local card = UI.Card(parent, { radius = 12, fill = C.card })
  card:SetHeight(72)
  self.composer = card

  local slot = CreateFrame("Button", nil, card)
  slot:SetSize(46, 46)
  slot:SetPoint("LEFT", 14, 0)
  slot.edge = UI.Round(slot, 10, UI.Alpha(C.accent, 0.5))
  slot.fill = UI.Round(slot, 9, C.shell, "BACKGROUND", 1, 1)
  slot.plus = UI.Glyph(slot, "plus", 16, C.accent)
  slot.plus:SetPoint("CENTER")
  slot.item = UI.ItemIcon(slot, 46)
  slot.item:SetAllPoints()
  slot.item:Hide()
  local function accept()
    local kind, id, link = GetCursorInfo()
    if kind == "item" then
      self:SetDraft(link or id)
      ClearCursor()
      return true
    end
  end
  slot:SetScript("OnReceiveDrag", accept)
  slot:SetScript("OnClick", function()
    if not accept() then self.itemInput.eb:SetFocus() end
  end)
  UI.Tip(slot, function(tt)
    if self.draft then
      pcall(tt.SetHyperlink, tt, self.draft)
    else
      tt:AddLine(L["Glisse un objet ici"], 1, 1, 1)
      tt:AddLine(L["ou Maj+clic sur n'importe quel objet : sacs, lien dans le chat, fenêtre de métier, butin…"], 0.7, 0.7, 0.75, true)
    end
  end)
  self.slot = slot

  local input = UI.Input(card, { placeholder = L["Nom de l'objet (ex. Viande de coyote), Maj+clic ou glisser"], max = 255, onChange = function(text, user)
    local id = U.ItemID(text)
    if id then
      self.draft = text
      slot.item:SetItem(U.ItemIcon(id), U.ItemQuality(text))
      slot.item:Show()
      slot.plus:Hide()
    else
      self.draft = nil
      slot.item:Hide()
      slot.plus:Show()
    end
    if user then
      self.draftRecipe = nil
      ns:Debounce("craft-suggest", 0.25, function() self:ShowSuggestions(self.itemInput:GetText()) end)
    end
  end })
  input.eb:SetScript("OnEnterPressed", function(eb) eb:ClearFocus(); UI.CloseMenu(); self:SubmitDraft() end)
  input:SetHeight(32)
  input:SetPoint("LEFT", slot, "RIGHT", 12, 0)
  self.itemInput = input

  local submit = function() UI.CloseMenu(); self:SubmitDraft() end
  local qty = UI.Input(card, { placeholder = "1", max = 4, numeric = true, noClear = true, justify = "CENTER", onEnter = submit })
  qty:SetSize(52, 32)
  self.qtyInput = qty
  local note = UI.Input(card, { placeholder = L["Note (facultatif)"], max = 60, onEnter = submit })
  note:SetSize(170, 32)
  self.noteInput = note
  local add = UI.Button(card, { text = L["Ajouter"], icon = "plus", style = "primary", h = 32, onClick = function() self:SubmitDraft() end })
  add:SetPoint("RIGHT", card, "RIGHT", -14, 0)
  note:SetPoint("RIGHT", add, "LEFT", -10, 0)
  qty:SetPoint("RIGHT", note, "LEFT", -8, 0)
  input:SetPoint("RIGHT", qty, "LEFT", -8, 0)

  U.OnInsertLink(function(link) self:OnItemLink(link) end)
end

-- Maj+clic sur un objet, où qu'il soit (sacs, lien dans le chat, fenêtre de métier, butin…), pendant que
-- la liste des besoins est affichée.
function View:OnItemLink(link)
  if not link:find("|Hitem:", 1, true) or not self.composer or not self.composer:IsVisible() then return end
  local ours = { [self.itemInput.eb] = true, [self.qtyInput.eb] = true, [self.noteInput.eb] = true }
  local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
  if focus and not ours[focus] then return end            -- le lien est parti dans un autre champ (chat, macro…)
  if not focus then
    -- Personne n'a le focus : le lien est pour nous, sauf si une fenêtre du jeu l'a déjà pris.
    local chat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
      or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
    if chat or (AuctionHouseFrame and AuctionHouseFrame:IsVisible()) then return end
  end
  self.draftRecipe = nil
  self.itemInput:SetText(link)
  UI.CloseMenu()
  UI.FadeColor(self.slot.edge, C.accent, 0.1)
  C_Timer.After(0.5, function() UI.FadeColor(self.slot.edge, UI.Alpha(C.accent, 0.5), 0.3) end)
  self.qtyInput.eb:SetFocus()
  self.qtyInput.eb:HighlightText()
end

function View:SetDraft(link)
  if type(link) == "number" then link = select(2, U.GetItemInfo(link)) or ("item:" .. link) end
  self.itemInput:SetText(link or "")
end

-- Composants d'une recette : la quantité indique combien de fois tu veux la fabriquer.
function View:SetRecipeDraft(recipe)
  self.itemInput:SetText(string.format(L["Composants : %s"], recipe))
  self.draftRecipe = recipe
  self.qtyInput:SetText("")
end

function View:RequestReagents(recipe, crafts)
  local added, complete = ns.Craft:AddReagentNeeds(recipe, crafts)
  if not added then
    ns.Print(L["composants inconnus : ouvre une fois ta fenêtre de métier pour que KEK les mémorise."])
  elseif #added == 0 then
    ns.Print(string.format(L["tu as déjà tout ce qu'il faut pour %s."], recipe))
  else
    local names = {}
    for _, it in ipairs(added) do names[#names + 1] = string.format("%s ×%d", tostring(it.s or "?"), it.q or 1) end
    ns.Print(string.format(L["ajouté à tes besoins pour %s : %s. La bande est prévenue."], recipe, table.concat(names, ", ")))
  end
  ns.db.ui.craftTab = "needs"
  if ns.Window.frame and ns.Window.frame:IsShown() then ns.Window:Refresh() end
end

function View:SubmitDraft()
  if self.draftRecipe then
    local qty = tonumber(self.qtyInput:GetText()) or 1
    local recipe = self.draftRecipe
    self.draftRecipe = nil
    self.itemInput:SetText("")
    self.qtyInput:SetText("")
    self.noteInput:SetText("")
    UI.CloseMenu()
    self:RequestReagents(recipe, math.max(1, qty))
    return
  end
  local draft = self.draft or self.itemInput:GetText()
  if not draft or not draft:find("%S") then
    UI.FadeColor(self.itemInput.edge, C.bad, 0.1)
    C_Timer.After(0.6, function() UI.FadeColor(self.itemInput.edge, C.edge, 0.3) end)
    self.itemInput.eb:SetFocus()
    return
  end
  UI.CloseMenu()
  local qty = tonumber(self.qtyInput:GetText()) or 1
  ns.Craft:AddNeed(draft, math.max(1, qty), self.noteInput:GetText())
  self.itemInput:SetText("")
  self.qtyInput:SetText("")
  self.noteInput:SetText("")
end

-- ================================================================== construction
function View:Build(frame, actions)
  self.frame = frame

  -- onglet recettes
  self.recipesPane = CreateFrame("Frame", nil, frame)
  self.recipesPane:SetAllPoints()
  local search = UI.Input(self.recipesPane, { placeholder = L["Rechercher une recette, un objet…"], icon = "search", max = 60, onChange = function(text)
    self.query = text
    ns:Debounce("craft-search", 0.12, function() self:Refresh() end)
  end })
  search:SetHeight(34)
  search:SetPoint("TOPLEFT", 0, 0)
  self.search = search

  local profItems = { { value = "", label = L["Tous les métiers"] } }
  self.profDropdown = UI.Dropdown(self.recipesPane, { w = 190, h = 34, items = profItems, value = "", onChange = function(v)
    self.profFilter = v ~= "" and v or nil
    self:Refresh()
  end })
  self.profDropdown:SetPoint("TOPRIGHT", 0, 0)
  search:SetPoint("RIGHT", self.profDropdown, "LEFT", -10, 0)
  self.profItems = profItems

  self.recipes = UI.List(self.recipesPane, {
    gap = 4,
    kind = function(item) return item.crafters and "recipe" or "prof" end,
    height = function(_, kind) return kind == "prof" and 64 or 52 end,
    create = createRecipeRow, update = updateRecipeRow,
    empty = { glyph = "book", title = L["Aucune recette"], text = L["Ouvre ta fenêtre de métier une fois : KEK mémorise tes recettes et les partage avec la bande."] },
  })
  self.recipes:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -14)
  self.recipes:SetPoint("BOTTOMRIGHT", self.recipesPane, "BOTTOMRIGHT", 0, 0)

  -- onglet besoins
  self.needsPane = CreateFrame("Frame", nil, frame)
  self.needsPane:SetAllPoints()
  self:BuildComposer(self.needsPane)
  self.composer:SetPoint("TOPLEFT", 0, 0)
  self.composer:SetPoint("TOPRIGHT", 0, 0)
  self.needs = UI.List(self.needsPane, {
    rowHeight = 64, gap = 4, create = createNeedRow, update = updateNeedRow,
    empty = { glyph = "bag", title = L["Aucun besoin"], text = L["Tape le nom d'un objet qu'il te manque (ex. Viande de coyote) : la bande est prévenue, et KEK indique qui l'a dans ses sacs ou sa banque, et qui sait le fabriquer."] },
  })
  self.needs:SetPoint("TOPLEFT", self.composer, "BOTTOMLEFT", 0, -14)
  self.needs:SetPoint("BOTTOMRIGHT", self.needsPane, "BOTTOMRIGHT", 0, 0)

  local tabs = UI.Segmented(actions, {
    { value = "recipes", label = L["Recettes"] },
    { value = "needs", label = L["Besoins"] },
  }, ns.db.ui.craftTab, function(v)
    ns.db.ui.craftTab = v
    ns.Window:Refresh()
  end)
  tabs:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
end

function View:Refresh()
  local tab = ns.db.ui.craftTab
  self.recipesPane:SetShown(tab ~= "needs")
  self.needsPane:SetShown(tab == "needs")
  if tab == "needs" then
    self.needs:SetData(ns.Craft:AllNeeds(), true)
    return
  end
  -- liste des métiers pour le filtre
  local profs = ns.Craft:Professions()
  for i = #self.profItems, 2, -1 do self.profItems[i] = nil end
  for _, p in ipairs(profs) do self.profItems[#self.profItems + 1] = { value = p.prof, label = p.prof } end
  self.profDropdown:SetValue(self.profFilter or "")
  local query = self.query or ""
  if query == "" and not self.profFilter then
    self.recipes:SetData(profs, true)
  else
    self.recipes:SetData(ns.Craft:Search(query, self.profFilter))
  end
end

ns.Window:Register(View)
