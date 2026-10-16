# Démo publique

Copie du Journal des parents avec des **données fictives**, ouverte sans compte, pour la montrer. Les personnages (Mère, Père, Camille, Julien, Sophie) n'existent pas. La vraie dictée par Claude fonctionne, avec des limites. L'outil réel n'est pas exposé.

## Principes

| Sujet | Choix |
|---|---|
| Données | Une base Airtable séparée (mêmes tables), jamais celle de la famille |
| Identité | Un compte partagé « Visiteur », posé par Caddy (`X-Aidant`), jamais éditeur (`X-Admin: 0`) |
| Workflows | Des copies des workflows réels (préfixe `DEMO —`), avec leur propre jeton de webhook |
| Coût | Quota de notes par jour et texte limité à 700 caractères, avant tout appel à Claude |
| Documents | Envoi de fichiers désactivé |
| Remise à zéro | Un workflow de purge nocturne supprime ce que les visiteurs ont ajouté |
| Page | Bandeau « Démo publique », clés `localStorage` préfixées `demo_` pour ne pas se mélanger avec la vraie page |

## Contenu

| Chemin | Rôle |
|---|---|
| `site/index.html` | Page de la démo (servie sous `/demo/`) |
| `caddy/demo.caddy.example` | Routes Caddy : identité imposée, webhooks cachés, page statique |
| `notification/notification-du-jour.json` | Workflow n8n : notification du matin (ntfy) avec les rendez-vous du jour |

## Notification du jour

Chaque matin à 7 h 30 (Europe/Paris), le workflow lit les rendez-vous du jour dans l'Agenda et envoie une notification sur le téléphone avec [ntfy](https://ntfy.sh). Priorité haute s'il en reste à couvrir. Aucun message les jours sans rendez-vous.

Importer le JSON dans n8n, remplacer `<BASE_AIRTABLE>`, `<TABLE_AGENDA>`, `<ID_CREDENTIAL_AIRTABLE>` et `<SUJET_NTFY>` (un nom long et aléatoire : il joue le rôle de mot de passe), puis publier. Le titre et le lieu des rendez-vous ne sont pas mis dans le message.

Les identifiants, jetons et noms de sujet réels ne sont pas dans ce dépôt.
