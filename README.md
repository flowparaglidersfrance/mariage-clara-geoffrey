# Clara & Geoffrey, le quiz des tables

Jeu de mariage : un téléphone par table, 20 questions sur les mariés en trois services (7 à l'entrée, 7 au plat, 6 au dessert), de 2 à 4 réponses chacune, classement des tables en direct.

- `index.html` : le jeu complet (hébergé sur GitHub Pages). Les questions et la configuration Supabase sont en tête du script.
- `supabase/migrations/` : le schéma de la base (équipes, réponses, droits anonymes, temps réel).
- Photos des questions : bucket Storage public `media`, dossier `questions/` (`qNN-k.jpg`, 1600 px max). Plusieurs photos par question = une adresse par ligne dans `media_url`, diaporama à la révélation. Sources : dossier « Mariage Chouchou & Geo » sur le Bureau (tableur de Camille + photos par dossier).

## Les trois espaces

- `#/jouer` : les tables (un téléphone par table). Inscription, attente, questions, révélation, classement. `#/jouer/7` est le lien du carton de la table 7 : la table prévue (nom dans l'onglet Tables) s'inscrit d'un bouton, un seul téléphone par table. Une deuxième inscription est refusée, sauf si l'animateur rouvre la table 10 minutes (« Autre téléphone », points conservés).
- `#/cartons` : cartons à imprimer, un par table prévue avec son nom (A4, 6 par page) ; `#/cartons/16` force un nombre.
- `#/animateur` : l'animateur, protégé par un code PIN (`#/connexion`). Onglets Partie (pilotage), Questions (éditeur), Tables, Réglages (code, remise à zéro).
- `#/ecran` : grand écran à projeter, suit l'état de la partie (QR code, question, réponse, classement, podium).

## Déroulé

L'animateur lance chaque question ; les tables ont le temps imparti (30 à 90 s) pour répondre ; il révèle la réponse et l'anecdote ; à la fin de chaque service (Entrée, Plat, Dessert) il affiche le classement. Points : 100 par bonne réponse + jusqu'à 50 de bonus de rapidité, calculés côté serveur. Une question peut avoir plusieurs bonnes réponses (case « Plusieurs bonnes réponses » dans l'éditeur) : la table coche tout ce qu'elle pense bon puis valide ; points au prorata (bonnes cochées moins mauvaises cochées, sur le nombre de bonnes), bonus de rapidité seulement si la sélection est exacte.

## Lancement

Les tables prévues (nom + numéro) se saisissent dans l'onglet Tables ; le nombre attendu suit. Le lancement de la première question est bloqué tant que les tables attendues (réglable dans l'onglet Partie) ne sont pas toutes inscrites. L'animateur peut lever ce verrou d'une case à cocher.

## Remise à zéro

Depuis l'espace animateur, onglet Réglages. Efface les tables et les scores, conserve les questions.

## Hébergement

- Site : https://flowparaglidersfrance.github.io/mariage-clara-geoffrey/ (GitHub Pages, branche `main`).
- Base : projet Supabase dédié « mariage-clara-geoffrey » (`hjwnztxsalikcfzsrjds`), tables `teams` et `answers`. Le mot de passe de la base est dans `.env.local` (non versionné).
- Les deux fichiers `*_existant_referenciel.sql` sont vides et sans effet : ils restent uniquement parce qu'ils figurent déjà dans l'historique des migrations du projet.
- Appliquer une nouvelle migration : `supabase db push` (projet lié via `supabase/.temp`).
