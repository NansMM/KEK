# Historique de KEK

## 1.9.1 — 7 novembre 2026

- LQE pour toi : seulement le type d'armure principal de ta classe. Un guerrier ou un paladin n'est plus prévenu pour du tissu ou du cuir : mailles avant le niveau 40, plaques ensuite. Chasseur et chaman : cuir, puis mailles au 40. Voleur et druide : cuir. Prêtre, mage et démoniste : tissu. Les capes, bijoux, colliers et anneaux vont toujours à tout le monde.

## 1.9.0 — 7 novembre 2026

- Objets LQE : quand un ami ramasse un objet « Lié quand équipé » ou un sac, KEK regarde s'il t'intéresse et te prévient (« LQE pour toi »), avec la raison :
  - équipement que ta classe peut porter, utilisable à ton niveau ou dans 3 niveaux au plus, meilleur que ce que tu portes, avec des caractéristiques utiles à ta classe ;
  - recette de ton métier que tu n'as pas encore ;
  - sac plus grand que ton plus petit sac.
- Nouvelle vue « Coffre » : les objets LQE et les sacs de toute la bande (rerolls compris), avec qui les garde et où (sac, banque, banque de guilde). Filtres « Pour moi » et « Mes objets », recherche, bouton « Demander » qui prépare le chuchotement.
- Banque de guilde : lue quand quelqu'un de la bande l'ouvre (si WoW Forever en a une).
- Besoins : quand un ami ramasse un objet de ta liste de besoins, tu es prévenu (« Marc vient de ramasser Viande de coyote ×4 · tu en cherches encore 10 »).
- Réglages : interrupteur « LQE pour moi » (fenêtre de KEK et Options > AddOns). Son personnalisable : `boe.ogg`.
- Autotest : nouvelle ligne « Objets LQE ».

## 1.8.1 — 7 novembre 2026

- Guilde : sur WoW Forever, un message d'addon envoyé à la guilde peut ne jamais arriver. KEK teste maintenant la guilde à la connexion et ne passe par elle que si elle transmet vraiment (son propre message revient, ou un message de guilde arrive d'un autre joueur). Sinon, il parle aux membres de ta guilde par chuchotement, comme aux autres amis.
- Bande de guilde (sans code) : si la guilde ne transmet rien, KEK le dit dans le chat et dans la fenêtre (« La guilde ne transmet rien ») et conseille de choisir un code de bande.
- Autotest : la ligne « Message de guilde » indique par où KEK passe et de qui il a reçu des messages de guilde.

## 1.8.0 — 7 novembre 2026

- Présence lue dans le jeu : KEK se sert aussi de ta liste d'amis, de tes amis Battle.net, de ta guilde et de ton groupe pour savoir qui est connecté.
  - Un ami qui se déconnecte passe hors ligne tout de suite (avant : jusqu'à 6 minutes s'il plantait ou se déconnectait depuis un donjon).
  - En donjon, le jeu coupe les messages des addons : tes amis restent « En donjon » au lieu de passer hors ligne au bout de 5 minutes.
  - Niveau et zone de tes amis tenus à jour même quand leurs messages ne passent pas.
- Autotest : nouvelle ligne « Présence lue dans le jeu ».
- La bande : les barres d'XP ne sautent plus à chaque rafraîchissement (en vol, la zone change souvent). Chaque membre garde sa ligne, et la barre ne s'anime que quand il gagne de l'XP ; quand il gagne un niveau, elle repart de zéro.

## 1.7.2

- Besoins : le Maj+clic sur un objet marche partout (lien dans le chat, fenêtre de métier, butin, sacs), même pour un objet que tu n'as jamais eu. Plus besoin de cliquer d'abord dans le champ : il suffit que la liste des besoins soit affichée.
- Après un Maj+clic, le curseur passe à la quantité : tape le nombre puis Entrée pour ajouter le besoin.
- Atelier > Recettes : Maj+clic et « Ajouter à mes besoins » marchent aussi pour un objet que ton jeu ne connaît pas encore.
- Autotest : la ligne « Fonctions du chat » indique si le Maj+clic est bien suivi.

## 1.7.1 — 6 novembre 2026

- Les fenêtres de métier de WoW Forever sont bien lues (le jeu renvoie un rang de 0 pour le « sous-métier »).
- Autotest : détail de la dernière lecture d'une fenêtre de métier, et nom de l'expéditeur des messages d'une ancienne version.
- Première version publiée sur GitHub, avec mise à jour automatique par WowUp.

## 1.7.0

- Demander les composants qui manquent pour une recette : clic droit dans Atelier > Recettes, « Composants : … » dans Besoins, ou `/kek besoin 3 composants Ragoût de coyote`. Une seule notification pour toute la liste.
- Recettes et composants lus avec la fenêtre de métier récente (C_TradeSkillUI).
- Boutons − / + sur les quantités des besoins.

## 1.6.0

- Besoins tapés au clavier, même pour un objet jamais possédé, avec suggestions pendant la frappe.
- Notification à la bande quand quelqu'un ajoute un besoin (« tu en as 6 »), commande `/kek besoin`.

## 1.5.x

- Noms « Prénom Nom » de WoW Forever : plus de doublon, les amis se trouvent sans être groupés.
- Liaison par chuchotement et par Battle.net, amis resondés toutes les 3 minutes.
- Autotest (`/kek autotest`) avec rapport à copier-coller.
- Les morts en champ de bataille et en arène ne comptent pas.
- Talents et métiers lus avec l'interface récente.

## 1.4.0 et avant

- Page KEK dans Options > AddOns, bouton de minicarte standard (LibDBIcon).
- Compatibilité WoW Forever : plus de journal de combat ni de canal personnalisé (interdits aux addons), silence en donjon.
- Première version : la bande, le fil, le Hall of Shame, la soirée, la course au 60 et l'atelier.
