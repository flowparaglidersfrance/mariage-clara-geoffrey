# Clara & Geoffrey, le quiz des tables

Jeu de mariage : un téléphone par table, 20 questions sur les mariés en trois services (7 à l'entrée, 7 au plat, 6 au dessert), de 2 à 4 réponses chacune, classement des tables en direct.

- `index.html` : le jeu complet (hébergé sur GitHub Pages). Les questions et la configuration Supabase sont en tête du script.
- `supabase/migrations/` : le schéma de la base (équipes, réponses, droits anonymes, temps réel).
- Photos des questions : bucket Storage public `media`, dossier `questions/` (`qNN-k.jpg`, 1600 px max). Plusieurs photos par question = une adresse par ligne dans `media_url`, diaporama à la révélation. Sources : dossier « Mariage Chouchou & Geo » sur le Bureau (tableur de Camille + photos par dossier).

## Les trois espaces

- `#/jouer` : les tables (un téléphone par table). Inscription, attente, questions, révélation, classement. `#/jouer/7` fixe le numéro de table (c'est le lien de chaque carton QR) ; une table déjà inscrite peut être reprise depuis un autre téléphone.
- `#/cartons/12` : cartons de table à imprimer (un QR code par table, A4, 6 par page).
- `#/animateur` : l'animateur, protégé par un code PIN (`#/connexion`). Onglets Partie (pilotage), Questions (éditeur), Tables, Réglages (code, remise à zéro).
- `#/ecran` : grand écran à projeter, suit l'état de la partie (QR code, question, réponse, classement, podium).

## Déroulé

L'animateur lance chaque question ; les tables ont le temps imparti (30 à 90 s) pour répondre ; il révèle la réponse et l'anecdote ; à la fin de chaque service (Entrée, Plat, Dessert) il affiche le classement. Points : 100 par bonne réponse + jusqu'à 50 de bonus de rapidité, calculés côté serveur.

## Lancement

Le lancement de la première question est bloqué tant que les tables attendues (10 par défaut, réglable dans l'onglet Partie) ne sont pas toutes inscrites. L'animateur peut lever ce verrou d'une case à cocher.

## Remise à zéro

Depuis l'espace animateur, onglet Réglages. Efface les tables et les scores, conserve les questions.

## Hébergement

- Site : https://flowparaglidersfrance.github.io/mariage-clara-geoffrey/ (GitHub Pages, branche `main`).
- Base : projet Supabase dédié « mariage-clara-geoffrey » (`hjwnztxsalikcfzsrjds`), tables `teams` et `answers`. Le mot de passe de la base est dans `.env.local` (non versionné).
- Les deux fichiers `*_existant_referenciel.sql` sont vides et sans effet : ils restent uniquement parce qu'ils figurent déjà dans l'historique des migrations du projet.
- Appliquer une nouvelle migration : `supabase db push` (projet lié via `supabase/.temp`).
