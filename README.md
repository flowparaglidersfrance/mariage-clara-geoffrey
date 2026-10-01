# Clara & Geoffrey, le quiz des tables

Jeu de mariage : un téléphone par table, 15 questions sur les mariés en trois services, classement des tables en direct.

- `index.html` : le jeu complet (hébergé sur GitHub Pages). Les questions et la configuration Supabase sont en tête du script.
- `supabase/migrations/` : le schéma de la base (équipes, réponses, droits anonymes, temps réel).

## Les trois espaces

- `#/jouer` : les tables (un téléphone par table). Inscription, attente, questions, révélation, classement.
- `#/animateur` : l'animateur, protégé par un code PIN (`#/connexion`). Onglets Partie (pilotage), Questions (éditeur), Tables, Réglages (code, remise à zéro).
- `#/ecran` : grand écran à projeter, suit l'état de la partie (QR code, question, réponse, classement, podium).

## Déroulé

L'animateur lance chaque question ; les tables ont le temps imparti (30 à 90 s) pour répondre ; il révèle la réponse et l'anecdote ; à la fin de chaque service (Entrée, Plat, Dessert) il affiche le classement. Points : 100 par bonne réponse + jusqu'à 50 de bonus de rapidité, calculés côté serveur.

## Remise à zéro

Depuis l'espace animateur, onglet Réglages. Efface les tables et les scores, conserve les questions.

## Hébergement

- Site : https://flowparaglidersfrance.github.io/mariage-clara-geoffrey/ (GitHub Pages, branche `main`).
- Base : projet Supabase dédié « mariage-clara-geoffrey » (`hjwnztxsalikcfzsrjds`), tables `teams` et `answers`. Le mot de passe de la base est dans `.env.local` (non versionné).
- Les deux fichiers `*_existant_referenciel.sql` sont vides et sans effet : ils restent uniquement parce qu'ils figurent déjà dans l'historique des migrations du projet.
- Appliquer une nouvelle migration : `supabase db push` (projet lié via `supabase/.temp`).
