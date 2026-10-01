# Clare & Geoffrey, le quiz des tables

Jeu de mariage : un téléphone par table, 15 questions sur les mariés en trois services, classement des tables en direct.

- `index.html` : le jeu complet (hébergé sur GitHub Pages). Les questions et la configuration Supabase sont en tête du script.
- `supabase/migrations/` : le schéma de la base (équipes, réponses, droits anonymes, temps réel).

## Modes

- Lien principal : le jeu, pour les tables.
- `#classement` : classement en direct avec QR code, à projeter sur grand écran.

## Remise à zéro avant le jour J

```sql
truncate public.answers, public.teams;
```

## Hébergement

- Site : https://flowparaglidersfrance.github.io/mariage-clare-geoffrey/ (GitHub Pages, branche `main`).
- Base : projet Supabase dédié « mariage-clare-geoffrey » (`hjwnztxsalikcfzsrjds`), tables `teams` et `answers`. Le mot de passe de la base est dans `.env.local` (non versionné).
- Les deux fichiers `*_existant_referenciel.sql` sont vides et sans effet : ils restent uniquement parce qu'ils figurent déjà dans l'historique des migrations du projet.
- Appliquer une nouvelle migration : `supabase db push` (projet lié via `supabase/.temp`).
