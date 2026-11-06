# KEK

L'addon WoW Forever de ta bande d'amis : voir qui joue, fêter les exploits, se moquer des morts, comparer les soirées, faire la course au 60 et s'entraider à l'atelier.

## Ce que fait KEK

| Vue | Ce que tu y trouves |
|---|---|
| **La bande** | Chaque personnage de la bande : niveau et XP, zone, spécialisation (double spé comprise), métiers, statut en ligne, nombre de morts. Clic droit : chuchoter, inviter, retirer. |
| **Fil** | Chronologie des exploits, groupée par jour : niveaux, butin rare/épique, morts, boss, paliers de métier. Filtrable. |
| **Hall of Shame** | Podium des morts, titres honorifiques (Paillasson, Kamikaze, Poisson rouge, Spéléologue, Récidiviste, Habitué, Touriste, Immortel) et détail de chaque mort : où, à quel niveau, contre quelle créature, chute ou noyade, et une épitaphe. |
| **Soirée** | Ton récap en direct (durée, XP et XP par heure, or, ennemis, quêtes, morts, zones, objets, meilleur butin), ta soirée précédente, et le palmarès de la bande ce soir (MVP de l'XP, Boucher, Mécène, Chat noir, Pilleur…). Bouton pour partager ton récap dans le chat. |
| **Course au 60** | Une piste par personnage avec sa position, le temps de jeu restant estimé et une date d'arrivée probable, plus la courbe niveau / temps de jeu de toute la bande. |
| **Atelier** | Annuaire de toutes les recettes de la bande (recherche sans accents, filtre par métier) et liste de besoins : dis à la bande ce qu'il te faut (ex. « 10 Viande de coyote, pour ma cuisine »). Tes amis reçoivent une notification qui leur dit s'ils en ont, et KEK indique qui l'a dans ses sacs ou sa banque (rerolls compris) et qui sait le fabriquer. |

Les notifications apparaissent en direct quand un ami monte de niveau, trouve un objet épique, meurt, tue un boss ou atteint un palier de métier. Elles se mettent en pause au survol et un clic ouvre la vue concernée. Le passage au niveau 60 a droit à une carte dorée.

## Installation

### Avec WowUp (recommandé : mises à jour automatiques)

1. Il faut WowUp 2.24.1 ou plus récent, et le client **World of Warcraft: Forever** sélectionné en haut de WowUp.
2. **Get Addons** → **Install from URL** → colle `https://github.com/NansMM/KEK` → **Install**.
3. C'est tout : à chaque nouvelle version, WowUp propose la mise à jour.

Si tu avais installé KEK à la main, supprime d'abord l'ancien dossier `KEK` dans `Interface\AddOns`.

### À la main

1. Télécharge `KEK-x.y.z-forever.zip` sur la [dernière release](https://github.com/NansMM/KEK/releases/latest).
2. Décompresse-le dans `World of Warcraft\_forever_\Interface\AddOns` (supprime d'abord l'ancien dossier `KEK`).
3. Lance le jeu. Si KEK est marqué « périmé » dans la liste des addons, coche **Charger les addons périmés**.

Toute la bande doit avoir une version récente : les versions trop anciennes ne se comprennent plus.

## Premier lancement

- Tape `/kek` ou clique sur le feu de camp près de la minicarte.
- Entrez tous **le même code secret** (ex. `loutres`). Seuls ceux qui ont le même code font partie de ta bande.
- KEK retrouve tout seul les membres de la bande dans ta **guilde**, ton **groupe** et ta **liste d'amis** (amis du jeu et amis Battle.net). Il leur parle ensuite par des messages d'addon invisibles dans le chat. Tant qu'un ami ne répond pas, KEK le resonde toutes les 3 minutes : peu importe qui entre le code en premier.
- Un ami n'apparaît pas ? Clique sur **+** dans « La bande » (ou tape `/kek ajouter NomDuPerso`) et entre le nom d'un de ses personnages : sur WoW Forever, **prénom et nom de famille** (ex. `Philipon Dugard`). Dès qu'il répond, il te présente aussi le reste de la bande.
- Pas de code ? Si vous êtes dans la même guilde, la bande, c'est la guilde : tous ses membres qui ont KEK apparaissent. Attention : sur WoW Forever, la guilde ne transmet pas toujours les messages d'addon. KEK la teste à la connexion ; si rien ne passe, il l'affiche (« La guilde ne transmet rien ») et il vous faut un code de bande. Avec un code, KEK teste aussi la guilde et, si elle ne transmet rien, passe par les chuchotements : rien à faire.

> Pourquoi pas un canal privé ? WoW Classic interdit aux addons d'envoyer leurs messages sur un canal de discussion personnalisé. C'est ce qui provoquait le message « KEK a été bloqué… » dans la version 1.0.0.

## Commandes

| Commande | Effet |
|---|---|
| `/kek` | Ouvrir ou fermer la fenêtre |
| `/kek code loutres` | Rejoindre une bande (code vide : passer par la guilde) |
| `/kek ajouter Philipon Dugard` | Retrouver un ami qui n'apparaît pas (prénom et nom de famille de son perso) |
| `/kek fil`, `morts`, `soiree`, `course`, `atelier`, `options` | Aller directement à une vue |
| `/kek test` | Afficher des notifications d'exemple |
| `/kek deplacer` | Déplacer les notifications |
| `/kek besoin 10 Viande de coyote : pour ma cuisine` | Dire à la bande ce dont tu as besoin (quantité et note facultatives ; un lien d'objet par Maj+clic marche aussi) |
| `/kek besoin 3 composants Ragoût de coyote` | Demander à la bande ce qui te manque pour fabriquer une recette 3 fois |
| `/kek autotest` | Vérifier KEK dans ton jeu : un rapport s'ouvre, prêt à copier-coller (Ctrl+C) |
| `/kek rapport` | Rouvrir le dernier rapport d'autotest |
| `/kek diag` | Version, état de la connexion et actions bloquées par le jeu |
| `/kek reset` | Tout effacer (avec confirmation) |

## WoW Forever et les addons

Forever applique les règles d'addons de Midnight. KEK les respecte :

- **Pas de journal de combat** : un addon qui l'écoute est bloqué par le jeu (c'était le message « KEK a été bloqué… » des versions 1.0 et 1.1). KEK n'affiche donc ni dégâts ni soins ; les morts sont décrites avec ce qui reste permis (créature combattue, chute, noyade), et les ennemis sont comptés grâce aux messages d'expérience.
- **Silence en donjon** : le jeu interdit aux addons de communiquer en donjon et en champ de bataille. Tes exploits attendent et partent à la sortie. Pendant ce temps, KEK lit ta liste d'amis, tes amis Battle.net, ta guilde et ton groupe : les amis en donjon restent affichés « En donjon », avec leur niveau et leur zone à jour, et un ami qui se déconnecte passe hors ligne tout de suite.
- **Butin** : KEK le repère dans tes sacs, ce qui marche aussi en donjon (où les messages du chat sont cachés aux addons).
- **Bouton de la minicarte** : KEK utilise la bibliothèque standard LibDBIcon, comme le demande Forever : le bouton est reconnu par le jeu et peut être rangé avec ceux des autres addons. Il affiche le nombre d'amis en ligne, se déplace en le faisant glisser et se masque dans les réglages. KEK apparaît aussi dans le menu des addons du jeu et dans les barres d'infos (Titan Panel, etc.).
- **Si le jeu bloque encore quelque chose** : KEK écrit dans le chat le nom exact de l'action bloquée. Fais une capture de cette ligne (ou tape `/kek diag`) : c'est ce qu'il faut pour corriger.
- **Autotest** : `/kek autotest` (ou le bouton Autotest dans les réglages) vérifie en quelques secondes tout ce qui dépend du jeu : messages entre joueurs (dont un aller-retour avec chaque ami de la bande connecté), menu Options, bouton de la minicarte, textes du chat lus par KEK, temps de jeu, talents et métiers, actions bloquées, erreurs. Le rapport s'ouvre déjà sélectionné : Ctrl+C, puis colle-le pour le partager. Lance-le hors donjon : le jeu y coupe les messages.

## Bon à savoir

- **Besoins** : dans Atelier > Besoins, tape simplement le nom de l'objet (des suggestions apparaissent), même si tu ne l'as jamais eu. Tu peux aussi le glisser depuis tes sacs, ou faire Maj+clic sur n'importe quel objet pendant que la liste des besoins est affichée : sacs, lien dans le chat, fenêtre de métier, butin. Le curseur passe alors à la quantité : tape le nombre puis Entrée. Tes amis sont prévenus, et la notification leur dit s'ils en ont. Les boutons − et + à côté de la quantité l'ajustent (Maj : par 10).
- **Composants d'une recette** : ouvre une fois ta fenêtre de métier, KEK mémorise les composants de tes recettes. Ensuite, clic droit sur une recette dans Atelier > Recettes, « Demander les composants qui me manquent », ou tape le nom de la recette dans Besoins et choisis « Composants : … » (la quantité = nombre de fabrications). KEK ne demande que ce qui manque, en comptant tes sacs et tes banques, et la bande reçoit une seule notification pour toute la liste.
- **Champs de bataille** : les morts en champ de bataille et en arène ne comptent pas (ni Hall of Shame, ni soirée).
- **Recettes** : ouvre une fois la fenêtre de chaque métier. KEK mémorise tes recettes et les partage.
- **Banque** : ouvre ta banque une fois par personnage. Son contenu compte ensuite dans les besoins de la bande.
- **Sons** : tu peux mettre tes propres sons dans `KEK\Sounds`. Les noms attendus sont dans `LISEZMOI.txt`.
- **Réglages** : tu les trouves à deux endroits qui restent synchronisés. Dans **Options > AddOns > KEK** (menu du jeu) : notifications, sons, butin à partager, bouton de la minicarte et taille de la fenêtre. Dans la fenêtre de KEK (Réglages) : tout cela plus le code de la bande, ton pseudo et l'ajout d'un ami.
- **Fenêtre** : elle est déplaçable, redimensionnable (coin en bas à droite) et se ferme avec Échap.
- **Ce qui est partagé avec la bande** : niveau, zone, spécialisation, métiers et recettes, besoins et quantités possédées, morts, temps de jeu et statistiques de soirée (dont l'or gagné). Ces infos ne partent que vers les membres de ta bande. Pour les trouver, KEK envoie à tes amis en ligne un simple « bonjour » invisible, sans aucune de ces infos ; un ami qui n'a pas KEK ou pas le même code l'ignore.

## Pour les curieux (développement)

- **Publier une version** : ajoute une section `## X.Y.Z` dans `CHANGELOG.md`, puis lance `python tools/release.py X.Y.Z`. Le script met le numéro à jour, lance le banc de test, crée l'étiquette `vX.Y.Z` et pousse. GitHub Actions publie alors la release (`KEK-X.Y.Z-forever.zip` + `release.json` pour WowUp), sauf si un test échoue.
- `tools/package.py X.Y.Z` fabrique les mêmes fichiers dans `dist/`, sans rien publier.

- `KEK/Libs` contient quatre bibliothèques standard de la communauté (LibStub, CallbackHandler, LibDataBroker, LibDBIcon), livrées telles quelles ; leurs sources et licences sont dans `KEK/Libs/LISEZMOI.txt`.

- `tools/make_media.py` régénère toutes les textures (logo, icônes, coins arrondis, ombres) sans dépendance.
- `tools/test/run_tests.py` lance six clients WoW Forever simulés qui se parlent comme en jeu (guilde, groupe, chuchotements d'addon). Le jeu simulé applique les règles de Forever : canaux personnalisés et journal de combat interdits, données secrètes et silence en donjon. Il vérifie la découverte de la bande, la synchro, les alertes, les morts, les besoins, les recettes, la course, la soirée et chaque écran. Il faut d'abord installer le module : `pip install lupa`.
