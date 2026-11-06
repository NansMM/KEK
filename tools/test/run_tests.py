#!/usr/bin/env python3
"""Banc de test de KEK : plusieurs clients WoW Classic simulés (Lua 5.1) qui se parlent comme en jeu :
guilde, groupe et chuchotements d'addon. Les canaux personnalisés sont interdits, comme dans le vrai client.

Usage : python tools/test/run_tests.py   (nécessite le module « lupa » : pip install lupa)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(ROOT, "KEK").replace("\\", "/")
MOCK = os.path.join(HERE, "wowmock.lua").replace("\\", "/")
if os.environ.get("KEK_PYLIB"):
    sys.path.insert(0, os.environ["KEK_PYLIB"])
from lupa import lua51  # noqa: E402

FAILS = []


def check(cond, label):
    print(("  ok   " if cond else "  ÉCHEC ") + label)
    if not cond:
        FAILS.append(label)


class Client:
    def __init__(self, name, cls, guid, level, pre=None, surname=None, realm=None):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().dofile(MOCK)
        if pre:
            self.lua.execute(pre)  # variante du jeu à simuler avant le chargement de l'addon
        self.M = self.lua.globals().Mock
        p = self.M.player
        p.name, p["class"], p.guid, p.level = name, cls, guid, level
        if surname:
            p.surname = surname
        if realm:
            p.realm = realm
        self.name = name
        # WoW Forever : le jeu désigne un joueur par « Prénom Nom », sans royaume
        self.full = (name + " " + surname) if surname else (name + "-Forever")
        self.match = {self.full.lower()} if surname else {name.lower(), self.full.lower()}
        self.online = True
        self.ns = self.M.load(ADDON, "KEK.toc")
        self.M.fire("ADDON_LOADED", "KEK")
        self.M.fire("PLAYER_LOGIN")
        self.M.fire("PLAYER_ENTERING_WORLD", True, False)

    def run(self, code):
        return self.lua.execute(code)

    def errors(self):
        return list(self.M.errors.values())


SENT = []  # (expéditeur, type, destinataire) de chaque message d'addon parti


def group_of(c):
    return [n for n in c.M.group.values()] if c.M.group is not None else []


def pump(clients, seconds, step=0.25):
    """Avance le temps et distribue les messages d'addon comme le ferait le serveur."""
    for _ in range(int(seconds / step)):
        for c in clients:
            c.M.advance(step)
        for c in clients:
            msgs = list(c.M.outbox.values())
            c.run("Mock.outbox = {}")
            for m in msgs:
                prefix, text, dist, target = m[1], m[2], m[3], m[4]
                SENT.append((c.name, dist, target))
                if dist == "WHISPER":
                    t = str(target).lower()
                    dest = [d for d in clients if d.online and t in d.match]
                    if not dest:
                        # le serveur répond « joueur introuvable » dans le chat de l'expéditeur
                        c.M.system("Aucun joueur nommé '%s' n'est connecté." % target)
                elif dist == "GUILD":
                    dest = [d for d in clients if d.online and d.M.player.guild
                            and d.M.player.guild == c.M.player.guild]
                elif dist in ("PARTY", "RAID"):
                    dest = [d for d in clients if d.online and (d is c or d.name in group_of(c) or d.full in group_of(c))]
                else:
                    dest = []
                for d in dest:
                    d.M.fire("CHAT_MSG_ADDON", prefix, text, dist, c.full)
            # données Battle.net : livrées au compte visé
            bn = list(c.M.bnOutbox.values())
            c.run("Mock.bnOutbox = {}")
            for m in bn:
                for d in clients:
                    if d.online and d.M.gameAccountID is not None and d.M.gameAccountID == m[1]:
                        d.M.fire("BN_CHAT_MSG_ADDON", m[2], m[3], "WHISPER", c.M.gameAccountID)


def lua_len(t):
    return len(list(t.values())) if t is not None else 0


def main():
    print("Chargement de deux clients…")
    a = Client("Nans", "MAGE", "Player-1-0001", 10)
    b = Client("Kevin", "WARRIOR", "Player-1-0002", 12)
    ab = [a, b]
    pump(ab, 8)
    check(a.ns.Comm.mode == "none", "sans code ni guilde : mode « none »")

    print("Bande « loutres » (A a B dans sa liste d'amis, pas de guilde ni de groupe)")
    a.M.friends = a.lua.table(a.lua.table_from({"name": "Kevin", "connected": True}))
    b.lua.globals().SlashCmdList.KEK("code loutres")
    a.ns.Comm.SetCode(a.ns.Comm, "Loutres!")
    pump(ab, 12)
    check(a.ns.Comm.mode == "ready" and b.ns.Comm.mode == "ready", "les deux clients sont prêts")
    check(a.ns.db.band.code == "loutres", "code normalisé et mémorisé")
    check(all(d == "WHISPER" for (_, d, _) in SENT), "seuls des chuchotements d'addon sont utilisés")
    check(a.ns.db.members[b.full] is not None, "A voit B dans la bande")
    check(a.ns.Store.IsOnline(a.ns.Store, b.full), "B est en ligne chez A")
    check(b.ns.db.members[a.full]["class"] == "MAGE", "B connaît la classe de A")
    check(b.ns.db.members[a.full].spec is not None, "spécialisation partagée")
    check(lua_len(b.ns.db.members[a.full].profs) == 3, "métiers partagés (Couture, Enchantement, Cuisine)")

    print("Montée de niveau")
    a.M.player.level = 11
    a.M.fire("PLAYER_LEVEL_UP", 11)
    pump(ab, 6)
    feed = b.ns.db.feed
    check(feed[1] is not None and feed[1].k == "level" and feed[1].w == a.full and feed[1].l == 11, "B reçoit le niveau 11 de A")
    check(lua_len(b.ns.Toasts.active) >= 1, "notification affichée chez B")
    check(b.ns.db.members[a.full].level == 11, "état de A mis à jour chez B")

    print("Butin épique (repéré dans les sacs, marche aussi en donjon)")
    a.run("Mock.bags[0][5] = { id = 12784, count = 1 }")
    a.M.fire("BAG_UPDATE_DELAYED")
    pump(ab, 3)
    check(b.ns.db.feed[1].k == "loot" and b.ns.db.feed[1].q == 4, "B reçoit le butin épique")
    check(a.ns.Session.cur.it == 1 and a.ns.Session.cur.bq == 4, "la soirée de A compte l'objet et retient le meilleur")
    # s'équiper de l'objet puis le ranger n'est pas du butin
    a.run("Mock.bags[0][5] = nil; Mock.equipped[16] = { id = 12784 }")
    a.M.fire("PLAYER_EQUIPMENT_CHANGED", 16, False)
    a.M.fire("BAG_UPDATE_DELAYED")
    a.M.advance(1)
    a.run("Mock.equipped[16] = nil; Mock.bags[0][6] = { id = 12784, count = 1 }")
    a.M.fire("BAG_UPDATE_DELAYED")
    a.M.advance(1)
    # un achat chez le marchand non plus
    a.M.fire("MERCHANT_SHOW")
    a.run("Mock.bags[0][7] = { id = 2575, count = 1 }")
    a.M.fire("BAG_UPDATE_DELAYED")
    a.M.fire("MERCHANT_CLOSED")
    pump(ab, 3)
    check(a.ns.Session.cur.it == 1 and len([f for f in b.ns.db.feed.values() if f.k == "loot"]) == 1,
          "s'équiper, ranger ou acheter ne compte pas comme du butin")

    print("Mort (sans le journal de combat, fermé aux addons)")
    a.M.target = a.lua.table_from({"name": "Pillard défias", "hostile": True})
    a.M.fire("PLAYER_REGEN_DISABLED")
    a.M.fire("PLAYER_DEAD")
    pump(ab, 5)
    recent = b.ns.Deaths.Recent(b.ns.Deaths)
    check(lua_len(recent) == 1 and recent[1].d.by == "Pillard défias" and recent[1].d.cb, "B sait contre qui A est mort")
    cause = b.ns.Deaths.Cause(b.ns.Deaths, recent[1].d)
    check("Pillard défias" in cause, "cause lisible : " + cause)
    a.M.target = None
    a.M.fire("PLAYER_REGEN_ENABLED")
    titles = b.ns.Deaths.Titles(b.ns.Deaths)
    check(any(t.title == "Paillasson" and t.name == a.full for t in titles.values()), "titre « Paillasson » attribué")
    check(b.ns.db.members[a.full].deaths == 1, "compteur de morts synchronisé")

    print("Besoins et inventaires")
    b.ns.Craft.AddNeed(b.ns.Craft, b.M.link(2589), 10, "pour la couture")
    pump(ab, 10)
    check(a.ns.db.needs[b.full] is not None, "A reçoit la liste de besoins de B")
    holders = b.ns.Craft.Holders(b.ns.Craft, b.full, 2589)
    check(lua_len(holders) == 1 and holders[1].name == a.full and holders[1].count == 14, "B voit que A a 14 étoffes")

    print("Recettes (gros message découpé)")
    a.run("""
      Mock.trade = { name = "Couture", rank = 75, max = 150, list = { { name = "Tissu", kind = "header" } } }
      for i = 1, 60 do
        Mock.trade.list[#Mock.trade.list + 1] = { name = "Chemise en lin numéro " .. i, kind = "optimal", id = (i % 2 == 0) and 2568 or 2575 }
      end
    """)
    a.M.fire("TRADE_SKILL_SHOW")
    pump(ab, 45)
    res = b.ns.Craft.Search(b.ns.Craft, "LIN NUMERO 4")
    check(lua_len(res) >= 1, "B trouve les recettes de A (recherche sans accents)")
    res = b.ns.Craft.Search(b.ns.Craft, "")
    check(lua_len(res) == 60, "les 60 recettes sont arrivées (%d)" % lua_len(res))
    profs = b.ns.Craft.Professions(b.ns.Craft)
    check(any(p.prof == "Couture" for p in profs.values()), "vue d'ensemble des métiers")

    print("Course au 60")
    check(a.M.playedPrinted == 0, "/played interrogé sans rien afficher dans le chat")
    check(lua_len(a.ns.db.prog[a.full].pts) >= 1, "points de progression enregistrés")
    pump(ab, 130)
    check(b.ns.db.prog[a.full] is not None and lua_len(b.ns.db.prog[a.full].pts) >= 1, "B reçoit la courbe de A")

    print("Soirée")
    a.M.player.xp = 900
    a.M.fire("PLAYER_XP_UPDATE", "player")
    a.M.player.money = 133456
    a.M.fire("PLAYER_MONEY")
    a.M.fire("QUEST_TURNED_IN", 1, 100, 0)
    a.M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Pillard défias meurt, vous gagnez 45 points d'expérience. (+22 exp. bonus de repos)")
    a.M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Vous gagnez 100 points d'expérience.")
    a.M.fire("CHAT_MSG_COMBAT_XP_GAIN", a.M.secret())   # en donjon : message illisible
    s = a.ns.Session.Current(a.ns.Session)
    # A est passé niveau 11 plus tôt : (7600 - 500) restants du niveau 10 + 900 du niveau 11
    check(s.xp == 8000 and s.lv == 1 and s.g == 10000 and s.q == 1 and s.de == 1,
          "XP à cheval sur un niveau, or, quêtes, morts comptés (%s xp, %s or)" % (s.xp, s.g))
    check(s.k == 1, "ennemis comptés grâce aux messages d'expérience (%s)" % s.k)
    share = a.ns.Session.ShareText(a.ns.Session)
    check(share.startswith("KEK"), "texte de partage : " + share[:70])

    print("Interface : toutes les vues")
    for c in ab:
        c.ns.Window.Open(c.ns.Window)
        for view in ["roster", "feed", "deaths", "session", "race", "craft", "settings"]:
            c.ns.Window.Select(c.ns.Window, view)
            c.M.advance(0.4)
        c.run("""
          local ns = Mock.ns
          ns.db.ui.craftTab = "needs"; ns.Window:Select("craft"); ns.Window:Refresh()
          ns.db.ui.sessionTab = "last"; ns.Window:Select("session"); ns.Window:Refresh()
          ns.db.ui.sessionTab = "current"; ns.Window:Refresh()
          ns.db.ui.feedFilter = "death"; ns.Window:Select("feed"); ns.Window:Refresh()
          KEKWindow:SetSize(1200, 760)
          for _, v in ipairs({ "roster", "feed", "deaths", "session", "race", "craft", "settings" }) do ns.Window:Select(v) end
        """)
        c.M.advance(1)
        # survol de tout ce qui est visible
        c.run("""
          for _, f in ipairs(Mock.frames) do
            if f:IsVisible() and f._scripts.OnEnter then
              Mock.mouseOver = f
              local ok, err = pcall(f._scripts.OnEnter, f)
              if not ok then Mock.errors[#Mock.errors + 1] = "OnEnter: " .. tostring(err) end
              if f._scripts.OnLeave then pcall(f._scripts.OnLeave, f) end
              Mock.mouseOver = nil
            end
          end
        """)
        c.M.advance(0.5)
    check(True, "chaque vue se construit et se rafraîchit")

    print("Interactions")
    b.run("""
      local ns = Mock.ns
      ns.Window:Select("craft")
      ns.db.ui.craftTab = "recipes"; ns.Window:Refresh()
      local view = ns.Window.byId.craft
      view.search.eb:Type("chemise")
      Mock.advance(0.5)
      assert(#view.recipes.data > 0, "recherche vide")
      ns.db.ui.craftTab = "needs"; ns.Window:Refresh()
      Mock.cursor = 2568
      view.slot:_fire("OnReceiveDrag")
      assert(view.draft and view.draft:find("item:2568"), "glisser-déposer")
      view.qtyInput:SetText("3")
      view:SubmitDraft()
      Mock.advance(0.3)
      assert(#ns.db.needs[ns.me].l == 2, "besoin ajouté")
      ns.Craft:RemoveNeed(2568)
      assert(#ns.db.needs[ns.me].l == 1, "besoin retiré")
      ns.Window:Select("roster")
      ns.RosterView:ContextMenu(ns.db.members["Nans-Forever"])
      ns.UI.CloseMenu()
      ns.Window:Select("session")
      ns.Session:Share()
    """)
    check(lua_len(b.M.chat) == 0, "partage sans groupe ni guilde : rien n'est envoyé")
    b.M.player.guild = "Les Loutres"
    b.ns.Session.Share(b.ns.Session)
    check(lua_len(b.M.chat) == 1 and b.M.chat[1][2] == "GUILD", "partage du récap dans la guilde")
    b.M.player.guild = None

    print("Besoins : « j'ai besoin de viande de coyote pour ma cuisine »")
    # Kevin a 6 viandes de coyote dans ses sacs ; Nans ne l'a jamais vue (objet inconnu de son jeu)
    b.run("Mock.bags[0][8] = { id = 2673, count = 6 }")
    b.M.fire("BAG_UPDATE_DELAYED")
    pump(ab, 4)
    a.run("""
      local ns = Mock.ns
      ns.Window:Open("craft"); ns.db.ui.craftTab = "needs"; ns.Window:Refresh()
      local view = ns.Window.byId.craft
      view.itemInput.eb:SetFocus()
      view.itemInput.eb:Type("viande de coyote")
      Mock.advance(0.5)
      view.qtyInput:SetText("10")
      view.noteInput:SetText("pour ma cuisine")
      view:SubmitDraft()
    """)
    mine = a.ns.db.needs[a.full].l[1]
    check(mine.s == "Viande de coyote" and mine.i is None and mine.q == 10 and mine.n == "pour ma cuisine",
          "besoin tapé au clavier, même sans avoir l'objet (%s ×%s)" % (mine.s, mine.q))
    pump(ab, 4)
    feed_need = [f for f in b.ns.db.feed.values() if f.k == "need" and f.w == a.full]
    check(len(feed_need) == 1 and feed_need[0].s == "Viande de coyote" and feed_need[0].q == 10,
          "Kevin voit le besoin dans son fil (%s)" % [(f.s, f.q, f.w) for f in feed_need])
    if len(feed_need) != 1:
        print("        A feed:", [(f.k, f.s, f.t) for f in list(a.ns.db.feed.values())[:4]], "B online chez A:", a.ns.Store.IsOnline(a.ns.Store, b.full),
              "file A:", lua_len(a.ns.Comm.queue[1]), lua_len(a.ns.Comm.queue[2]), lua_len(a.ns.Comm.queue[3]), "pause:", a.ns.Comm.pausedUntil, a.M.now)
    need_toasts = [t for t in b.ns.Toasts.active.values() if t.spec.kind == "need" and t.spec.who == a.full]
    if len(need_toasts) != 1:
        print("        toasts B:", [(t.spec.kind, t.spec.who, t.spec.title, t.spec.body) for t in b.ns.Toasts.active.values()],
              "queue:", [(t.kind, t.title) for t in (b.ns.Toasts.queue.values() if b.ns.Toasts.queue else [])])
    check(len(need_toasts) == 1 and "a besoin de Viande de coyote ×10" in need_toasts[0].spec.title
          and "tu en as 6" in (need_toasts[0].spec.body or ""),
          "notification chez Kevin : « Nans a besoin de Viande de coyote ×10 » · « tu en as 6 »")
    pump(ab, 8)
    holders = a.ns.Craft.Holders(a.ns.Craft, a.full, mine)
    check(lua_len(holders) == 1 and holders[1].name == b.full and holders[1].count == 6,
          "Nans voit que Kevin en a 6, retrouvé par le nom")
    # commande rapide, avec un objet que Kevin connaît (dans ses sacs) puis avec un lien
    b.lua.globals().SlashCmdList.KEK("besoin 5 étoffe de lin : pour la couture")
    first = b.ns.db.needs[b.full].l[1]
    check(first.i == 2589 and first.q == 5 and first.n == "pour la couture",
          "/kek besoin 5 étoffe de lin : pour la couture -> objet reconnu, quantité et note")
    b.lua.globals().SlashCmdList.KEK("besoin 2 " + b.M.link(12784))
    check(b.ns.db.needs[b.full].l[1].i == 12784 and b.ns.db.needs[b.full].l[1].q == 2, "/kek besoin avec un lien d'objet (Maj+clic)")
    sugg = a.ns.Craft.Suggest(a.ns.Craft, "chemise", 6)
    check(lua_len(sugg) >= 1, "suggestions pendant la frappe (%d pour « chemise »)" % lua_len(sugg))
    a.run("""
      local ns = Mock.ns
      local view = ns.Window.byId.craft
      view.itemInput.eb:SetFocus()
      view.itemInput.eb:Type("chemise")
      Mock.advance(0.5)
      ns.UI.CloseMenu()
      view.itemInput:SetText("")
      ns.Craft:RemoveNeed(ns.Craft.NeedKey(ns.db.needs[ns.me].l[1]))
    """)
    check(lua_len(a.ns.db.needs[a.full].l) == 0, "retirer un besoin tapé au clavier")
    pump(ab, 6)

    print("Besoins : Maj+clic sur un objet qui n'est pas dans les sacs")
    # Interface 12.x : le jeu appelle ChatFrameUtil.InsertLink ; ChatEdit_InsertLink n'en est qu'une copie.
    hooks = a.ns.U.HookInsertLink()
    check(hooks.ChatFrameUtil and hooks.ChatEdit, "Maj+clic suivi par ChatFrameUtil.InsertLink et ChatEdit_InsertLink")
    a.run("""
      local ns = Mock.ns
      Mock.uncached[2684] = true                  -- Ragoût de coyote : jamais vu par le jeu de Nans
      ns.Window:Open("craft"); ns.db.ui.craftTab = "needs"; ns.Window:Refresh()
      local view = ns.Window.byId.craft
      view.itemInput:SetText("")
      view.itemInput.eb:SetFocus()
      Mock.shiftClick(2684)                       -- lien dans le chat d'un objet jamais vu
    """)
    view = a.ns.Window.byId.craft
    check("Ragoût de coyote" in view.itemInput.GetText(view.itemInput) and view.draft is not None,
          "champ actif : Maj+clic sur un objet jamais vu le met dans le brouillon")
    check(a.lua.eval("Mock.focus == Mock.ns.Window.byId.craft.qtyInput.eb"), "le curseur passe à la quantité")
    a.run("""
      local view = Mock.ns.Window.byId.craft
      view.qtyInput.eb:Type("3")
      view.qtyInput.eb:_fire("OnEnterPressed")
    """)
    mine = a.ns.db.needs[a.full].l[1]
    check(mine.i == 2684 and mine.s == "Ragoût de coyote" and mine.q == 3,
          "Entrée dans la quantité : besoin ajouté (%s ×%s, id %s)" % (mine.s, mine.q, mine.i))
    a.run("""
      local view = Mock.ns.Window.byId.craft
      if Mock.focus then Mock.focus:ClearFocus() end
      Mock.shiftClick(2673)                       -- aucun champ actif, onglet Besoins affiché
    """)
    check("Viande de coyote" in view.itemInput.GetText(view.itemInput),
          "sans cliquer dans le champ : Maj+clic remplit le brouillon quand Besoins est affiché")
    a.run("""
      if Mock.focus then Mock.focus:ClearFocus() end
      Mock.activeChat = CreateFrame("EditBox")
      Mock.activeChat:SetFocus()
      Mock.shiftClick(2320)                       -- chat ouvert : le lien va dans le chat
      Mock.activeChat:ClearFocus(); Mock.activeChat = nil
      local macro = CreateFrame("EditBox")
      macro:SetFocus()
      Mock.shiftClick(2320)                       -- autre champ actif (macro…) : pas pour KEK
      macro:ClearFocus()
    """)
    check("Viande de coyote" in view.itemInput.GetText(view.itemInput) and a.M.inserted[1] is not None and "Fil grossier" in a.M.inserted[1],
          "chat ou autre champ actif : le lien y va, le brouillon ne change pas")
    a.run("""
      local ns = Mock.ns
      ns.Window:Close()
      Mock.shiftClick(2320)                       -- fenêtre fermée
      ns.Window:Open("craft")
      Mock.ns.db.ui.craftTab = "recipes"; ns.Window:Refresh()
      Mock.shiftClick(2320)                       -- onglet Recettes
      Mock.ns.db.ui.craftTab = "needs"; ns.Window:Refresh()
    """)
    check("Viande de coyote" in view.itemInput.GetText(view.itemInput), "fenêtre fermée ou onglet Recettes : Maj+clic ignoré")
    a.run("""
      local view = Mock.ns.Window.byId.craft
      view.itemInput:SetText("")
      if Mock.focus then Mock.focus:ClearFocus() end
      ChatEdit_InsertLink(Mock.link(2589))        -- un vieil addon (base de butin…) qui appelle l'ancienne fonction
    """)
    check("Étoffe de lin" in view.itemInput.GetText(view.itemInput), "lien envoyé par un vieil addon avec ChatEdit_InsertLink")
    a.run("""
      Mock.uncached[2575] = true
      Mock.got = nil
      Mock.ns.U.WithItemLink(2575, function(l) Mock.got = l or false end)
    """)
    check(a.M.got is None, "lien d'un objet hors cache : KEK attend que le jeu le charge")
    a.M.advance(1)
    check(a.M.got and "Chemise en lin blanche" in a.M.got, "puis le lien arrive (%s)" % a.M.got)
    a.run("Mock.uncached[2575] = true")
    rid, rlink, rname = a.ns.Craft.Resolve(a.ns.Craft, a.lua.table_from({"id": 2575, "name": "Chemise en lin blanche"}))
    check(rid == 2575 and rname == "Chemise en lin blanche", "Ajouter à mes besoins depuis Recettes, objet hors cache : nom gardé")
    a.run("""
      local ns = Mock.ns
      Mock.uncached[2575] = nil
      Mock.ns.Window.byId.craft.itemInput:SetText("")
      for _, n in ipairs({ unpack(ns.db.needs[ns.me].l) }) do ns.Craft:RemoveNeed(ns.Craft.NeedKey(n)) end
    """)
    check(lua_len(a.ns.db.needs[a.full].l) == 0, "besoins de test retirés")
    pump(ab, 6)

    print("Composants d'une recette")
    a.run("""
      Mock.trade = { name = "Couture", rank = 75, max = 150, list = {
        { name = "Chemise en lin brune", kind = "optimal", id = 2568, reagents = { { id = 2589, count = 2 }, { id = 2320, count = 1 } } },
      } }
    """)
    a.M.fire("TRADE_SKILL_SHOW")
    a.M.advance(1)
    reag = a.ns.Craft.ReagentsFor(a.ns.Craft, "Chemise en lin brune")
    check(reag is not None and lua_len(reag) == 2, "composants mémorisés à l'ouverture de la fenêtre de métier")
    owned_cloth = a.ns.Craft.OwnedCount(a.ns.Craft, 2589)[0]
    view_a = a.ns.Window.byId.craft
    view_a.RequestReagents(view_a, "Chemise en lin brune", 10)
    needs_a = {(n.i, n.q) for n in a.ns.db.needs[a.full].l.values()}
    check((2320, 10) in needs_a and (2589, 20 - owned_cloth) in needs_a,
          "pour 10 chemises : 10 Fil grossier et %d Étoffe de lin (20 moins les %d déjà dans tes sacs)" % (20 - owned_cloth, owned_cloth))
    check(all("10 × Chemise en lin brune" in (n.n or "") for n in a.ns.db.needs[a.full].l.values()), "note automatique « pour 10 × Chemise en lin brune »")
    pump(ab, 4)
    combined = [t for t in b.ns.Toasts.active.values() if t.spec.kind == "need" and t.spec.who == a.full]
    check(len(combined) == 1 and "a besoin des composants de Chemise en lin brune ×10" in combined[0].spec.title
          and "Fil grossier ×10" in (combined[0].spec.body or "") and "tu as : " in (combined[0].spec.body or ""),
          "une seule notification chez Kevin pour toute la liste, avec ce qu'il a déjà")
    # quantité ajustée avec +/−, puis une deuxième demande ne réduit pas les quantités
    a.ns.Craft.SetNeedQty(a.ns.Craft, 2320, 12)
    view_a.RequestReagents(view_a, "Chemise en lin brune", 1)
    fil = [n for n in a.ns.db.needs[a.full].l.values() if n.i == 2320][0]
    check(fil.q == 12, "boutons +/− et nouvelle demande : la quantité la plus grande est gardée")
    sugg = a.ns.Craft.Suggest(a.ns.Craft, "chemise en lin b", 8)
    check(any(e.recipe == "Chemise en lin brune" for e in sugg.values()), "suggestion « Composants : Chemise en lin brune » pendant la frappe")
    a.run("""
      local ns = Mock.ns
      ns.Window:Open("craft"); ns.db.ui.craftTab = "needs"; ns.Window:Refresh()
      local view = ns.Window.byId.craft
      view:SetRecipeDraft("Chemise en lin brune")
      view.qtyInput:SetText("2")
      view:SubmitDraft()
      ns.db.ui.craftTab = "recipes"; ns.Window:Refresh()
      Mock.advance(0.3)
      for _, k in ipairs({ 2589, 2320, 2568 }) do ns.Craft:RemoveNeed(k) end
    """)
    check(lua_len(a.ns.db.needs[a.full].l) == 0, "demande par la zone de saisie (« Composants : … » ×2), puis retrait")
    pump(ab, 4)

    print("Notifications de démonstration")
    a.lua.globals().SlashCmdList.KEK("test")
    a.M.advance(2.5)
    check(lua_len(a.ns.Toasts.active) == 4, "4 notifications visibles au maximum (%d)" % lua_len(a.ns.Toasts.active))
    a.M.advance(20)
    check(lua_len(a.ns.Toasts.active) == 0, "les notifications disparaissent seules")
    a.ns.Toasts.Unlock(a.ns.Toasts)
    a.ns.Toasts.Lock(a.ns.Toasts)
    for cmd in ["", "fil", "morts", "soiree", "course", "atelier", "options", "aide", ""]:
        a.lua.globals().SlashCmdList.KEK(cmd)
    a.M.advance(1)

    print("Couverture complémentaire")
    pump(ab, 25)  # fin de la période de chauffe des alertes de connexion
    # boss tué par les deux membres du groupe : une seule notification fusionnée chez un tiers
    a.M.fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
    b.M.fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
    pump(ab, 3)
    boss_toasts = [t for t in a.ns.Toasts.active.values() if t.spec.key == "boss:Edwin VanCleef"]
    check(len(boss_toasts) == 1 and lua_len(boss_toasts[0].spec.names) == 1, "boss : notification unique chez A")
    check(any(f.k == "boss" and f.w == a.full for f in b.ns.db.feed.values()), "boss partagé dans le fil")
    # palier de métier
    a.M.fire("CHAT_MSG_SKILL", "Votre compétence en Couture est maintenant de 75.")
    pump(ab, 3)
    check(b.ns.db.feed[1].k == "skill" and b.ns.db.feed[1].r == 75, "palier de métier (Couture 75) partagé")
    # banque : les objets en banque comptent aussi
    a.run("Mock.bags[-1] = { [2] = { id = 2589, count = 6 } }")
    a.run("""
      local orig = C_Container.GetContainerNumSlots
      C_Container.GetContainerNumSlots = function(bag) if bag == -1 then return 24 end return orig(bag) end
    """)
    a.M.fire("BANKFRAME_OPENED")
    pump(ab, 12)
    holders = b.ns.Craft.Holders(b.ns.Craft, b.full, 2589)
    check(holders[1] is not None and holders[1].count == 20, "sacs + banque : A a maintenant 20 étoffes chez B (%s)" % (holders[1].count if holders[1] else "?"))
    a.M.fire("BANKFRAME_CLOSED")
    # chute mortelle : B tombait juste avant de mourir
    b.M.falling = True
    b.M.advance(0.5)
    b.M.falling = False
    b.M.fire("PLAYER_DEAD")
    pump(ab, 4)
    # noyade : la jauge de respiration est vide
    a.M.fire("MIRROR_TIMER_START", "BREATH", 0, 60000, -1, False, "Respiration")
    a.M.fire("PLAYER_DEAD")
    pump(ab, 4)
    titles = b.ns.Deaths.Titles(b.ns.Deaths)
    check(any(t.title == "Poisson rouge" and t.name == a.full for t in titles.values()), "titre « Poisson rouge » après une noyade")
    titles = a.ns.Deaths.Titles(a.ns.Deaths)
    check(any(t.title == "Kamikaze" and t.name == b.full for t in titles.values()), "titre « Kamikaze » après une chute")
    # connexion d'un ami après la période de chauffe
    b.run("Mock.ns.Comm:Send('H', {}, 1)")
    pump(ab, 2)
    # contrôles de l'interface
    a.run("""
      local ns, UI = Mock.ns, Mock.ns.UI
      ns.Window:Select("roster")
      local rv = ns.RosterView
      assert(rv.addButton:IsShown(), "bouton + visible avec un code")
      rv:ShowAddPopover(rv.addButton)
      assert(rv.addPopover:IsShown() and rv.addPopover.catcher:IsShown(), "fenêtre d'ajout ouverte")
      Mock.advance(0.3)
      rv.addPopover.catcher._scripts.OnClick(rv.addPopover.catcher, "LeftButton")
      assert(not rv.addPopover:IsShown(), "un clic à côté la referme")
      rv:ShowAddPopover(rv.addButton)
      ns.Window:Select("settings")
      assert(not rv.addPopover:IsShown() or not rv.addPopover:IsVisible(), "elle se ferme en changeant de vue")
      local view = ns.Window.byId.settings
      for _, f in ipairs(Mock.frames) do
        if f:IsVisible() and f._type == "Button" and f.value ~= nil and f._scripts.OnClick and f:GetParent() and f:GetParent().SetValue then
          f._scripts.OnClick(f, "LeftButton")
        end
      end
      for _, f in ipairs(Mock.frames) do
        if f:IsVisible() and f.knob and f.track and f._scripts.OnClick then f._scripts.OnClick(f, "LeftButton"); f._scripts.OnClick(f, "LeftButton") end
      end
      ns.Window:Select("craft"); ns.db.ui.craftTab = "recipes"; ns.Window:Refresh()
      local craft = ns.Window.byId.craft
      craft.profDropdown._scripts.OnClick(craft.profDropdown, "LeftButton")
      Mock.advance(0.3)
      ns.UI.CloseMenu()
      for _, f in ipairs(Mock.frames) do
        if f:IsVisible() and f.knob and f.fillF then
          f.knob._scripts.OnMouseDown(f.knob); Mock.advance(0.2); f.knob._scripts.OnMouseUp(f.knob)
        end
      end
      ns.Window.byId.race:Refresh()
      local plot = ns.Window.byId.race.plot
      Mock.mouseOver = plot
      ns.Window:Select("race")
      Mock.advance(0.3)
      Mock.mouseOver = nil
      plot._scripts.OnLeave(plot)
    """)
    a.M.advance(1)
    check(len(a.errors()) == 0 and len(b.errors()) == 0, "interrupteurs, sélecteurs, liste déroulante, curseur, graphique")

    print("Rechargement de l'interface (pas de fausse déconnexion)")
    a.run("""
      local A = Mock.ns.Alerts
      Mock.presence = {}
      local orig = A.Receive
      A.Receive = function(self, who, data, ...)
        if type(data) == "table" and data.k == "presence" then Mock.presence[#Mock.presence + 1] = who end
        return orig(self, who, data, ...)
      end
    """)
    b.M.fire("PLAYER_LOGOUT")
    pump(ab, 2)
    check(not a.ns.Store.IsOnline(a.ns.Store, b.full), "B annonce son départ")
    b.run("wipe(Mock.ns.Comm.discovered); Mock.ns.Comm:Discover()")  # ce que fait KEK au retour
    pump(ab, 30)
    check(lua_len(a.M.presence) == 0 and a.ns.Store.IsOnline(a.ns.Store, b.full), "un /reload ne déclenche pas d'alerte de déconnexion")

    print("Un groupe : un seul message pour tout le groupe")
    a.M.group = a.lua.table("Kevin")
    b.M.group = b.lua.table("Nans")
    a.M.fire("GROUP_ROSTER_UPDATE")
    b.M.fire("GROUP_ROSTER_UPDATE")
    pump(ab, 4)
    del SENT[:]
    a.ns.Alerts.Emit(a.ns.Alerts, "boss", a.lua.table_from({"b": "Hogger"}))
    pump(ab, 3)
    mine = [(d, t) for (n, d, t) in SENT if n == "Nans"]
    check(("PARTY", None) in mine and not any(d == "WHISPER" for d, _ in mine), "l'alerte passe par le groupe, sans chuchotement")
    check(any(f.k == "boss" and f.b == "Hogger" for f in b.ns.db.feed.values()), "B la reçoit")
    a.M.group = None
    b.M.group = None

    print("Troisième ami, ajouté à la main")
    c = Client("Lucie", "PRIEST", "Player-1-0003", 8)
    abc = [a, b, c]
    pump(abc, 8)
    c.lua.globals().SlashCmdList.KEK("code loutres")
    pump(abc, 4)
    check(c.ns.Store.OnlineCount(c.ns.Store) == 0, "sans ami commun, C ne trouve encore personne")
    c.lua.globals().SlashCmdList.KEK("ajouter nans")
    pump(abc, 25)
    check(c.ns.db.members[a.full] is not None and c.ns.Store.IsOnline(c.ns.Store, a.full), "C trouve A par son nom")
    check(c.ns.db.members[b.full] is not None and c.ns.Store.IsOnline(c.ns.Store, b.full), "C trouve aussi B grâce à la liste de A")
    check(a.ns.Store.IsOnline(a.ns.Store, c.full) and b.ns.Store.IsOnline(b.ns.Store, c.full), "A et B voient C")
    check(any("fait partie de ta bande" in p for p in c.M.printed.values()), "C est prévenu que A fait partie de la bande")
    check(c.ns.db.members[a.full].level == 11, "C reçoit l'état complet de A")

    print("Ami hors ligne")
    c.lua.globals().SlashCmdList.KEK("ajouter Fantome")
    pump(abc, 3)
    check(lua_len(c.M.systemShown) == 0, "le « joueur introuvable » provoqué par KEK est masqué")
    check(any("Fantome n'est pas connecté" in p for p in c.M.printed.values()), "KEK dit clairement que Fantome n'est pas connecté")
    c.M.system("Aucun joueur nommé 'Bob' n'est connecté.")
    check(lua_len(c.M.systemShown) == 1, "un « joueur introuvable » qui ne vient pas de KEK reste affiché")

    print("Une autre bande dans la même guilde")
    d = Client("Dora", "MAGE", "Player-1-0004", 20)
    d.M.player.guild = "Les Loutres"
    a.M.player.guild = "Les Loutres"
    d.M.friends = d.lua.table(d.lua.table_from({"name": "Nans", "connected": True}))
    d.lua.globals().SlashCmdList.KEK("code castors")
    abcd = [a, b, c, d]
    pump(abcd, 15)
    check(a.ns.db.members[d.full] is None and d.ns.db.members[a.full] is None, "un code différent : les deux bandes s'ignorent")
    d.ns.Autotest.Run(d.ns.Autotest)
    pump(abcd, 7)
    dtext = d.ns.Autotest.last.text
    check("Liaison avec Nans : aller-retour" in dtext,
          "sans membre en ligne, l'autotest teste quand même la liaison avec les amis qui ont KEK")
    d.lua.globals().KEKAutotest.Hide(d.lua.globals().KEKAutotest)
    a.M.player.guild = None

    print("Bande de guilde (sans code)")
    e = Client("Elfie", "WARRIOR", "Player-1-0005", 30)
    f = Client("Fred", "PRIEST", "Player-1-0006", 31)
    for x in (e, f):
        x.M.player.guild = "Les Castors"
    pump([e, f], 15)
    check(e.ns.Comm.IsGuildBand(e.ns.Comm) and f.ns.Comm.IsGuildBand(f.ns.Comm), "sans code, la guilde fait office de bande")
    check(e.ns.Store.IsOnline(e.ns.Store, f.full) and f.ns.db.members[e.full].level == 30, "les membres de la guilde se voient")
    gsent = [d for (n, d, _) in SENT if n in ("Elfie", "Fred")]
    check(len(gsent) > 0 and all(d == "GUILD" for d in gsent), "tout passe par la guilde")

    print("Messages refusés par le jeu")
    a.M.sendResult = 9
    for boss in ("Test 1", "Test 2", "Test 3", "Test 4", "Test 5", "Test 6"):
        a.ns.Alerts.Emit(a.ns.Alerts, "boss", a.lua.table_from({"b": boss}))
    pump(abc, 20)
    check(any("refuse les messages" in p for p in a.M.printed.values()), "un avertissement clair dans le chat")
    a.M.sendResult = None
    clients = [a, b, c, d, e, f]

    print("Restrictions de WoW Forever")
    before_errors = len(a.errors())
    a.M.fire("CHAT_MSG_SKILL", a.M.secret())
    a.M.fire("CHAT_MSG_ADDON", "KEK", a.M.secret(), "WHISPER", "Kevin-Forever")
    a.M.system(a.M.secret())
    check(len(a.errors()) == before_errors, "données secrètes (chat en donjon) ignorées sans erreur")
    a.M.inInstance = True
    a.M.lockdown = True
    del SENT[:]
    a.M.fire("ENCOUNTER_END", 2, a.M.secret(), 1, 5, 1)
    pump(abc, 6)
    check(not any(n == "Nans" for (n, _, _) in SENT) and (a.M.lockedSends or 0) == 0,
          "en donjon, KEK n'envoie rien (le jeu l'interdit) : les messages attendent")
    a.M.inInstance = False
    a.M.lockdown = False
    pump(abc, 15)
    check(any(f.k == "boss" and f.b == "Les Mortemines" for f in b.ns.db.feed.values()),
          "à la sortie, l'alerte part ; boss au nom caché : nom du donjon")
    a.M.fire("ADDON_ACTION_FORBIDDEN", "KEK", "UneFonction()")
    a.M.fire("ADDON_ACTION_FORBIDDEN", "AutreAddon", "Autre()")
    a.M.advance(1.5)
    check(any("UneFonction()" in p for p in a.M.printed.values()) and lua_len(a.ns.db.diag) == 1,
          "si le jeu bloque quand même une action, KEK la nomme dans le chat")
    a.lua.globals().SlashCmdList.KEK("diag")
    a.run("""
      KEK_OnAddonCompartmentEnter("KEK", UIParent)
      KEK_OnAddonCompartmentLeave("KEK", UIParent)
      KEK_OnAddonCompartmentClick("KEK", "LeftButton")
      KEK_OnAddonCompartmentClick("KEK", "RightButton")
    """)
    g = a.lua.globals()
    icon = g.LibDBIcon10_KEK
    check(icon is not None and icon.IsShown(icon), "bouton standard LibDBIcon sur la minicarte (reconnu par Forever)")
    a.run("""
      local b = LibDBIcon10_KEK
      b._scripts.OnEnter(b)
      assert(LibDBIconTooltip:IsShown(), "infobulle LibDBIcon")
      b._scripts.OnLeave(b)
      b._scripts.OnClick(b, "LeftButton")
      b._scripts.OnDragStart(b); Mock.advance(0.2); b._scripts.OnDragStop(b)
    """)
    check(a.ns.db.ui.minimap.minimapPos is not None, "position du bouton mémorisée après un glisser")
    mb = a.ns.MinimapButton
    mb.SetWanted(mb, False)
    check(not icon.IsShown(icon), "le bouton se masque depuis les réglages")
    mb.SetWanted(mb, True)
    check(icon.IsShown(icon), "et revient")
    check(a.ns.MinimapButton.object.text != "KEK", "la barre d'infos affiche le nombre d'amis en ligne")

    print("Menu Options du jeu (onglet AddOns)")
    g = a.lua.globals()
    st = a.M.settings
    addon = list(st.addon.values())
    check(len(addon) == 1 and addon[0].name == "KEK" and addon[0].layout is not None,
          "page « KEK » dans Options > AddOns, avec les contrôles natifs du jeu")
    kinds = [c.kind for c in st.controls.values()]
    check(kinds.count("checkbox") == 10 and kinds.count("dropdown") == 1 and kinds.count("slider") == 1 and lua_len(st.buttons) == 5,
          "10 cases à cocher, 1 liste, 1 curseur, 5 boutons")
    byvar = st.byVar
    a.run('Mock.ns.Window:Open("settings")')
    loot = byvar["KEK_alert_loot"]
    loot.SetValue(loot, False)
    a.M.advance(0.5)
    view = a.ns.Window.byId.settings
    check(a.ns.db.alerts.loot is False and loot.GetValue(loot) is False, "décocher « Butin » dans le menu du jeu coupe les alertes de butin")
    check(view.toggles.loot.value is False, "la fenêtre de KEK affiche aussitôt le même réglage")
    loot.SetValue(loot, True)
    dd = [c for c in st.controls.values() if c.kind == "dropdown"][0]
    check([o.value for o in dd.extra().values()] == [3, 4], "liste « Butin à partager » : Rare et +, Épique et +")
    byvar["KEK_lootQuality"].SetValue(byvar["KEK_lootQuality"], 3)
    byvar["KEK_scale"].SetValue(byvar["KEK_scale"], 1.1)
    a.M.advance(0.5)
    check(a.ns.db.alerts.lootQuality == 3 and abs(a.ns.db.ui.scale - 1.1) < 1e-9 and view.lootSegmented.value == 3,
          "qualité du butin et taille de la fenêtre appliquées et synchronisées")
    sl = [c for c in st.controls.values() if c.kind == "slider"][0]
    check(sl.extra.formatter(1.1) == "110 %", "curseur de taille affiché en pourcentage")
    byvar["KEK_minimap"].SetValue(byvar["KEK_minimap"], False)
    check(not g.LibDBIcon10_KEK.IsShown(g.LibDBIcon10_KEK), "la case « Bouton sur la minicarte » masque le bouton")
    byvar["KEK_minimap"].SetValue(byvar["KEK_minimap"], True)
    byvar["KEK_lootQuality"].SetValue(byvar["KEK_lootQuality"], 4)
    a.run("Mock.ns.Window:Close()")
    for btn in st.buttons.values():
        btn.onClick()
    a.M.advance(2.5)
    check(a.ns.Window.frame.IsShown(a.ns.Window.frame), "les boutons ouvrent KEK, testent et déplacent les notifications")
    a.ns.Toasts.Lock(a.ns.Toasts)
    a.ns.Window.SetScale(a.ns.Window, 1)

    print("Morts en champ de bataille")
    deaths_before = lua_len(a.ns.db.deaths[a.full])
    de_before = a.ns.Session.cur.de
    a.M.inInstance, a.M.instanceType = True, "pvp"
    a.M.fire("PLAYER_DEAD")
    a.M.instanceType = "arena"
    a.M.fire("PLAYER_DEAD")
    a.M.inInstance, a.M.instanceType = False, None
    pump(abc, 3)
    check(lua_len(a.ns.db.deaths[a.full]) == deaths_before and a.ns.Session.cur.de == de_before
          and lua_len(b.ns.db.deaths[a.full]) == deaths_before,
          "les morts en champ de bataille et en arène ne comptent pas (ni Hall of Shame, ni soirée)")

    print("Autotest")
    # A et B sont aussi amis Battle.net
    a.M.gameAccountID, b.M.gameAccountID = 101, 102
    a.M.bnFriends = a.lua.table(a.lua.table_from({"characterName": "Kevin", "realmName": "Forever", "gameAccountID": 102,
                                                   "isOnline": True, "clientProgram": "WoW"}))
    b.M.bnFriends = b.lua.table(b.lua.table_from({"characterName": "Nans", "realmName": "Forever", "gameAccountID": 101,
                                                   "isOnline": True, "clientProgram": "WoW"}))
    a.lua.globals().SlashCmdList.KEK("autotest")
    pump(abc, 7)
    rep = a.ns.Autotest.last
    text = rep.text if rep is not None else ""
    for line in text.split("\n"):
        print("       |", line)
    fails = [l for l in text.split("\n") if l.startswith("[X]")]
    check(rep is not None and "Chuchotement à soi-même : reçu via WHISPER" in text, "autotest : le message envoyé à soi-même revient")
    check("Liaison avec Kevin : aller-retour" in text and "Liaison avec Lucie : aller-retour" in text,
          "autotest : aller-retour avec chaque ami connecté (ping, réponse automatique)")
    check("Liaison Battle.net avec Kevin : aller-retour" in text, "autotest : liaison Battle.net testée avec les amis Battle.net")
    check("Amis sondés :" in text and "Dora-Forever (a KEK avec un autre code)" in text,
          "autotest : un ami qui a KEK avec un autre code est signalé")
    check("Messages de KEK : envoyés : " in text and "WHISPER" in text, "autotest : compteurs de messages envoyés et reçus")
    check("Talents : GetNumTalentTabs = 3 · Feu" in text and "Métiers : lignes de compétence (5) · Couture 75" in text,
          "autotest : talents et métiers détaillés avec l'API utilisée")
    check(len(fails) == 1 and "Actions bloquées" in fails[0], "seul problème signalé : l'action bloquée simulée plus haut")
    check("page native" in text and "interface 16001 bien déclarée" in text and "LibDBIcon v55" in text, "rapport : menu Options, .toc, bouton de minicarte")
    g = a.lua.globals()
    check(g.KEKAutotest.IsShown(g.KEKAutotest) and a.ns.Autotest.frame.eb._highlight, "fenêtre du rapport ouverte, texte sélectionné pour Ctrl+C")
    g.KEKAutotest.Hide(g.KEKAutotest)
    a.lua.globals().SlashCmdList.KEK("rapport")
    check(g.KEKAutotest.IsShown(g.KEKAutotest), "/kek rapport rouvre le dernier rapport")
    a.M.player.guild = "Les Loutres"
    a.M.lockdown = True
    a.ns.Autotest.Run(a.ns.Autotest)
    a.M.lockdown = False
    check("impossible en donjon" in a.ns.Autotest.last.text, "en donjon, l'autotest saute le test des messages au lieu d'échouer")
    a.ns.Autotest.Run(a.ns.Autotest)
    pump(abc, 7)
    check("Message de guilde : reçu via GUILD" in a.ns.Autotest.last.text, "dans une guilde, le message de guilde est testé aussi")
    a.M.player.guild = None
    g.KEKAutotest.Hide(g.KEKAutotest)

    print("Talents et métiers avec l'API récente (spécialisations, GetProfessions)")
    y = Client("Yann", "MAGE", "Player-1-0009", 24, pre="""
      -- fenêtre de métier de l'interface récente (C_TradeSkillUI)
      GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo = nil, nil, nil
      C_TradeSkillUI = {}
      -- comme sur certains clients récents : le « sous-métier » renvoie un rang de 0
      function C_TradeSkillUI.GetChildProfessionInfo() return { professionName = "Cuisine", parentProfessionName = "", skillLevel = 0, maxSkillLevel = 0 } end
      function C_TradeSkillUI.GetAllRecipeIDs() return { 2541, 2542 } end
      function C_TradeSkillUI.GetRecipeInfo(id)
        if id == 2541 then return { name = "Ragoût de coyote", learned = true } end
        return { name = "Recette pas apprise", learned = false }
      end
      function C_TradeSkillUI.GetRecipeOutputItemData(id) return { itemID = 2684 } end
      function C_TradeSkillUI.GetRecipeSchematic(id, recraft)
        return { reagentSlotSchematics = {
          { reagents = { { itemID = 2673 } }, quantityRequired = 2, required = true },
          { reagents = { { itemID = 2320 } }, quantityRequired = 1, required = false },   -- facultatif : ignoré
        } }
      end

      GetNumTalentTabs = nil
      GetNumSkillLines = nil
      function GetSpecialization() return 2 end
      function GetSpecializationInfo(i) if i == 2 then return 63, "Feu", "Brûle tout.", 135810, "DAMAGER" end end
      function GetProfessions() return 1, nil, nil, 4, 5 end
      function GetProfessionInfo(i)
        local t = { [1] = { "Couture", 136249, 80, 150 }, [4] = { "Pêche", 136245, 30, 75 }, [5] = { "Cuisine", 133971, 12, 75 } }
        local p = t[i]
        return p[1], p[2], p[3], p[4]
      end
    """)
    pump([y], 14)
    me_y = y.ns.Store.Me(y.ns.Store)
    spec_name = y.ns.Profile.SpecSummary(me_y.spec)[0]  # plusieurs valeurs de retour
    profs_y = [p.n for p in me_y.profs.values()] if me_y.profs is not None else []
    check(spec_name == "Feu" and profs_y[:1] == ["Couture"] and len(profs_y) == 3,
          "spécialisation « Feu » et 3 métiers lus avec l'API récente (%s, %s)" % (spec_name, profs_y))
    y.ns.Autotest.Run(y.ns.Autotest)
    pump([y], 7)
    ytext = y.ns.Autotest.last.text
    check("Talents : spécialisations (interface récente) · Feu" in ytext and "Métiers : GetProfessions · Couture 80" in ytext,
          "autotest : API récente reconnue")
    check("Liaison avec un ami : aucun ami en ligne" in ytext and "entre le même code" in ytext,
          "autotest sans bande : conseil clair plutôt qu'une erreur")
    y.M.fire("TRADE_SKILL_SHOW")
    y.M.advance(1)
    yrec = y.ns.db.recipes[y.full]
    check(yrec is not None and yrec.p["Cuisine"] is not None and yrec.p["Cuisine"].l["Ragoût de coyote"] == 2684
          and yrec.p["Cuisine"].l["Recette pas apprise"] is None,
          "fenêtre de métier récente (C_TradeSkillUI) : recettes apprises mémorisées")
    check(yrec.p["Cuisine"].r == 12, "rang 0 renvoyé par le jeu : rang repris de la fiche du perso (12)")
    yre = y.ns.Craft.ReagentsFor(y.ns.Craft, "Ragoût de coyote")
    check(yre is not None and lua_len(yre) == 1 and yre[1].i == 2673 and yre[1].q == 2,
          "composants obligatoires lus (2 × Viande de coyote), facultatifs ignorés")
    y.lua.globals().SlashCmdList.KEK("besoin 3 composants ragout de coyote")
    yneed = y.ns.db.needs[y.full].l[1]
    check(yneed.i == 2673 and yneed.q == 6 and "3 × Ragoût de coyote" in (yneed.n or ""),
          "/kek besoin 3 composants ragout de coyote -> 6 Viande de coyote (sans accent ni majuscule)")
    y.ns.Autotest.Run(y.ns.Autotest)
    pump([y], 7)
    check("Recettes : C_TradeSkillUI · 1 recette(s) (Cuisine 1) · composants connus pour 1" in y.ns.Autotest.last.text,
          "autotest : ligne Recettes (API récente)")
    check("dernière lecture" in y.ns.Autotest.last.text and "Cuisine 12/75, 2 recette(s), 1 apprise(s), composants pour 1" in y.ns.Autotest.last.text,
          "autotest : détail de la dernière lecture de la fenêtre de métier")
    y.ns.Window.Open(y.ns.Window)
    y.ns.Window.Select(y.ns.Window, "roster")
    y.M.advance(0.5)
    clients += [y]

    print("Noms à la WoW Forever : prénom + nom de famille, royaumes internes différents")
    old_db = """KEKDB = { band = { code = "kek" }, members = {
        ["Nokie-Jenkins"] = { level = 18, class = "MAGE", deaths = 14 },
        ["Nokie Jenkins-CAMWOWEU5Realm6PvP"] = { level = 18, class = "MAGE", deaths = 14 },
        ["Philipon Dugard-CAMWOWEU5Realm6PvP"] = { level = 16, class = "WARRIOR" } },
      deaths = { ["Nokie-Jenkins"] = { { t = 1, l = 10 } }, ["Nokie Jenkins-CAMWOWEU5Realm6PvP"] = { { t = 1, l = 10 } } },
      inv = { ["Nokie-Jenkins"] = { bags = {}, bank = {} } } }"""
    n1 = Client("Nokie", "MAGE", "Player-6-0001", 18, pre=old_db, surname="Jenkins", realm="CAMWOWEU5Realm6PvP")
    n2 = Client("Philipon", "WARRIOR", "Player-8-0002", 16, surname="Dugard", realm="CAMWOWEU5Realm8PvP")
    nn = [n1, n2]
    n1.M.gameAccountID, n2.M.gameAccountID = 601, 802
    n1.M.bnFriends = n1.lua.table(n1.lua.table_from({"characterName": "Philipon Dugard", "realmName": "CAMWOWEU5Realm8PvP",
                                                     "gameAccountID": 802, "isOnline": True, "clientProgram": "WoW"}))
    n2.M.bnFriends = n2.lua.table(n2.lua.table_from({"characterName": "Nokie Jenkins", "realmName": "CAMWOWEU5Realm6PvP",
                                                     "gameAccountID": 601, "isOnline": True, "clientProgram": "WoW"}))
    pump(nn, 7)
    n2.lua.globals().SlashCmdList.KEK("code kek")   # Philipon entre le code après Nokie
    pump(nn, 15)
    check(n1.ns.me == "Nokie Jenkins" and n2.ns.me == "Philipon Dugard", "identité « Prénom Nom », comme dans le jeu")
    keys = sorted(n1.ns.db.members.keys())
    check(keys == ["Nokie Jenkins", "Philipon Dugard"], "anciens doublons fusionnés au démarrage (%s)" % keys)
    check(n1.ns.db.inv["Nokie Jenkins"] is not None and n1.ns.db.inv["Nokie-Jenkins"] is None, "inventaires rattachés au bon nom")
    check(n1.ns.Store.IsOnline(n1.ns.Store, "Philipon Dugard") and n2.ns.Store.IsOnline(n2.ns.Store, "Nokie Jenkins"),
          "Nokie et Philipon se voient sans être groupés")
    check(lua_len(n1.M.systemShown) == 0 and lua_len(n2.M.systemShown) == 0, "aucun « joueur introuvable »")
    check(sorted(n2.ns.db.members.keys()) == ["Nokie Jenkins", "Philipon Dugard"], "pas de doublon chez Philipon non plus")
    n1.ns.Autotest.Run(n1.ns.Autotest)
    pump(nn, 7)
    ntext = n1.ns.Autotest.last.text
    for line in ntext.split("\n"):
        if "Liaison" in line or "soi-même" in line or "double" in line or "Amis sondés" in line:
            print("       |", line)
    check("Chuchotement à soi-même : reçu via WHISPER" in ntext, "le message à soi-même arrive (nom complet « Nokie Jenkins »)")
    check("Liaison avec Philipon Dugard : aller-retour" in ntext and "Liaison Battle.net avec Philipon Dugard : aller-retour" in ntext,
          "liaison par chuchotement et par Battle.net avec Philipon")
    check("Noms en double : aucun (" in ntext, "autotest : noms réparés signalés, plus aucun doublon")
    n1.lua.globals().SlashCmdList.KEK("ajouter Philipon")
    check(any("nom de famille" in p for p in n1.M.printed.values()), "ajout sans nom de famille : KEK demande « Prénom Nom »")
    clients += nn

    print("Menu Options : repli si l'API du jeu diffère")
    z = Client("Zoe", "MAGE", "Player-1-0007", 5, pre="function Settings.RegisterProxySetting() error('signature différente') end")
    z.M.advance(1)
    zaddon = list(z.M.settings.addon.values())
    check(len(zaddon) == 1 and zaddon[0].frame is not None and z.ns.Options.simple is not None,
          "page simple avec un bouton « Ouvrir les réglages de KEK », sans doublon")
    w = Client("Will", "WARRIOR", "Player-1-0008", 5, pre="Settings = nil; function InterfaceOptions_AddCategory(p) Mock.oldPanel = p end")
    check(w.M.oldPanel is not None, "ancienne interface : page ajoutée par InterfaceOptions_AddCategory")
    clients += [z, w]

    print("Sérialisation (fuzz)")
    a.run("""
      local Ser = Mock.ns.Ser
      local function deepEq(x, y)
        if type(x) ~= type(y) then return false end
        if type(x) == "number" then return math.abs(x - y) <= 1e-6 * math.max(1, math.abs(x)) end
        if type(x) ~= "table" then return x == y end
        for k, v in pairs(x) do if not deepEq(v, y[k]) then return false end end
        for k in pairs(y) do if x[k] == nil then return false end end
        return true
      end
      math.randomseed(42)
      local function rstr()
        local t = {}
        for i = 1, math.random(0, 40) do t[i] = string.char(math.random(1, 255)) end
        return table.concat(t)
      end
      local function rval(d)
        local k = math.random(1, d > 3 and 4 or 5)
        if k == 1 then return rstr() elseif k == 2 then return math.random(-1e6, 1e6) / (math.random(1, 2) == 1 and 1 or 7)
        elseif k == 3 then return math.random(1, 2) == 1 elseif k == 4 then return math.floor(math.random() * 4e9)
        else local t = {} for i = 1, math.random(0, 6) do t[math.random(1, 2) == 1 and rstr() .. "k" or i] = rval(d + 1) end return t end
      end
      for i = 1, 400 do
        local v = { x = rval(0), y = rval(0) }
        local s = Ser.Encode(v)
        assert(not s:find("|", 1, true) and not s:find("%c"), "caractère interdit dans le flux")
        local back = Ser.Decode(s)
        for key, val in pairs(v) do
          if type(val) == "number" and val ~= math.floor(val) then
            assert(math.abs(back[key] - val) < 1e-3 * math.max(1, math.abs(val)), "nombre")
          else
            assert(deepEq(val, back[key]), "aller-retour #" .. i)
          end
        end
      end
      assert(Ser.Decode("^T^Sx") == nil, "flux tronqué rejeté")
      assert(Ser.Decode("n'importe quoi") == nil, "flux invalide rejeté")
    """)
    check(True, "400 allers-retours de sérialisation sans perte")

    print("Erreurs Lua et actions interdites")
    for x in clients:
        errs = x.errors()
        check(len(errs) == 0, "%s : aucune erreur Lua (%d)" % (x.full, len(errs)))
        for err in errs[:15]:
            print("       ", err)
    check(all(x.M.forbidden == 0 for x in clients), "aucune action interdite par Forever (journal de combat, canal personnalisé)")
    check(not any(d == "CHANNEL" for (_, d, _) in SENT), "aucun message sur un canal personnalisé")
    undefined = sorted(set(k for x in clients for k in x.M.undefined.keys()))
    print("  globales absentes consultées (optionnelles) :", ", ".join(undefined))

    print()
    if FAILS:
        print("%d vérification(s) en échec" % len(FAILS))
        sys.exit(1)
    print("Tous les tests passent.")


if __name__ == "__main__":
    main()
