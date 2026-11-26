# Héberger son propre serveur BetterCast

Par défaut, l'app utilise le serveur officiel (`https://bettercast.gameanddev.cloud`). Tu peux héberger ton propre serveur pour garder chez toi tes abonnements, tes positions de lecture et tes liens Patreon privés. Dans l'app, sur l'écran de connexion, active **« Utiliser mon propre serveur »** et saisis son adresse.

## Ce qu'il faut

- Une machine Linux toujours allumée (VPS, NAS, mini-PC) avec **Docker** et **Docker Compose**.
- Un **nom de domaine** (ou un sous-domaine) qui pointe vers elle, pour le HTTPS.
- Les ports **80 et 443** ouverts, sauf si un reverse proxy est déjà en place (voir plus bas).

Le serveur est léger : environ 100 Mo de RAM pour l'API et le worker, plus PostgreSQL.

## Installation

```bash
git clone https://github.com/polo5922/BetterCast.git
cd BetterCast
cp .env.example .env
```

Remplis ensuite `.env` :

| Variable | Rôle |
|---|---|
| `DOMAIN` | Le domaine, par ex. `podcasts.mondomaine.fr` |
| `PUBLIC_URL` | `https://` + le domaine |
| `POSTGRES_PASSWORD` | Mot de passe de la base (`openssl rand -base64 24`) |
| `JWT_SECRET` | Signature des sessions (`openssl rand -base64 48`) |
| `ENCRYPTION_KEY` | Chiffre les flux RSS privés (`openssl rand -base64 32`). **Garde-la précieusement** : la perdre rend les liens Patreon enregistrés illisibles. |
| `ALLOW_REGISTRATION` | `true` pour ouvrir les inscriptions, `false` une fois tes comptes créés |
| `REFRESH_INTERVAL_MINUTES` | Fréquence de vérification des nouveaux épisodes (20 par défaut) |
| `PODCAST_INDEX_KEY` / `PODCAST_INDEX_SECRET` | Facultatif. Clés gratuites sur https://api.podcastindex.org : elles enrichissent la recherche. |
| `PATREON_CLIENT_ID` / `PATREON_CLIENT_SECRET` | Facultatif, pour Patreon (voir plus bas). |
| `FCM_SERVICE_ACCOUNT_JSON` | Facultatif. Le compte de service Firebase, sur une seule ligne, pour les notifications push Android quand l'app est fermée. |

Puis lance la stack :

```bash
docker compose up -d --build
curl https://ton-domaine/health   # → {"ok":true}
```

Caddy obtient automatiquement le certificat HTTPS.

### Si tu as déjà un reverse proxy (Nginx Proxy Manager, Traefik…)

Ne démarre pas Caddy. Expose plutôt l'API sur un port local avec un `docker-compose.override.yml` :

```yaml
services:
  api:
    ports: ["8686:8080"]
```

```bash
docker compose up -d db api worker
```

Fais ensuite pointer ton proxy vers `http://<ip-de-la-machine>:8686`, avec HTTPS activé. Le flux temps réel `/events` (SSE) ne doit pas être bufferisé : le serveur envoie déjà `X-Accel-Buffering: no`, ce qui suffit pour Nginx.

Si Docker affiche *« all predefined address pools have been fully subnetted »*, ajoute un sous-réseau dédié dans l'override :

```yaml
networks:
  default:
    ipam:
      config:
        - subnet: 10.88.0.0/24
```

## Patreon

1. Crée un client sur https://www.patreon.com/portal/registration/register-clients.
2. Redirect URI : `https://ton-domaine/patreon/oauth/callback`.
3. Copie le *Client ID* et le *Client Secret* dans `.env`, puis relance `docker compose up -d`.

Dans l'app, va dans **Réglages → Patreon → Connecter Patreon**. Pour chaque créateur, colle ensuite ton lien RSS privé : sur la page du créateur, « Écouter sur d'autres applis ». Ce lien est chiffré sur ton serveur et n'est jamais renvoyé à l'app.

## Mise à jour

```bash
git pull
docker compose up -d --build
```

Les migrations de base de données s'appliquent toutes seules au démarrage.

## Sauvegarde

```bash
docker compose exec db pg_dump -U bettercast bettercast > bettercast.sql
```

Garde aussi une copie de ton `.env`, qui contient `ENCRYPTION_KEY`.
