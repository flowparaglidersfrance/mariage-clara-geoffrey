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
