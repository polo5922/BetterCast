# BetterCast

Une app de podcasts pour Android (+ Android Auto) et Windows : podcasts publics, flux premium Patreon, synchronisation sur ton propre serveur, et vidéo avec bascule audio/vidéo à la même position.

```
apps/bettercast/          App Flutter (Android, Windows)
server/                   API Dart (shelf) + worker de rafraîchissement des flux
packages/bettercast_core/ Modèles, DTO et parseurs RSS/OPML partagés
docker-compose.yml        postgres + api + worker + caddy (HTTPS)
```

## 1. Serveur

Par défaut, l'app se connecte au serveur officiel, `https://bettercast.gameanddev.cloud`. Pour héberger le tien, suis **[SELF_HOSTING.md](SELF_HOSTING.md)**. En résumé :

1. Pointe un nom de domaine vers le VPS.
2. Copie `.env.example` en `.env`, puis remplis-le :
   - `DOMAIN`, `PUBLIC_URL` (`https://ton-domaine`) ;
   - `POSTGRES_PASSWORD`, `JWT_SECRET` (`openssl rand -base64 48`) ;
   - `ENCRYPTION_KEY` (`openssl rand -base64 32`). Elle chiffre les URL RSS privées : **ne la perds pas**.
   - `PODCAST_INDEX_KEY` / `PODCAST_INDEX_SECRET` : clés gratuites sur https://api.podcastindex.org ;
   - `PATREON_CLIENT_ID` / `PATREON_CLIENT_SECRET` : crée un client sur https://www.patreon.com/portal/registration/register-clients, avec la redirect URI `https://ton-domaine/patreon/oauth/callback` ;
   - `FCM_SERVICE_ACCOUNT_JSON` : le JSON du compte de service Firebase, sur une seule ligne. Facultatif : sans lui, pas de push Android.
   - `ALLOW_REGISTRATION=false` une fois ton compte créé.
3. Lance la stack :
   ```
   docker compose up -d --build
   ```

En local, sans Docker, il faut un Postgres et `cd server && dart run bin/server.dart --all` (API + worker dans le même processus).

## 2. App

Il faut le Flutter SDK, puis `cd apps/bettercast && flutter pub get`.

### Windows
```
flutter run -d windows
```
Prérequis : Visual Studio avec la charge « Développement Desktop en C++ », et Rust (`rustup`) pour `smtc_windows`. Les notifications arrivent par SSE tant que l'app est ouverte.

### Android
1. Installe les cmdline-tools du SDK Android, puis lance `flutter doctor --android-licenses`.
2. Push FCM (facultatif) : crée une app Android `com.bettercast.bettercast` dans un projet Firebase, puis écris `firebase.json` :
   ```json
   { "FIREBASE_API_KEY": "...", "FIREBASE_APP_ID": "1:...:android:...", "FIREBASE_SENDER_ID": "...", "FIREBASE_PROJECT_ID": "..." }
   ```
3. Lance l'app :
   ```
   flutter run --dart-define-from-file=firebase.json
   ```

Pour Android Auto, active le mode développeur de l'app Android Auto, puis teste avec le Desktop Head Unit (DHU) du SDK.

`--dart-define=BETTERCAST_SERVER=https://ton-domaine` préremplit l'adresse du serveur sur l'écran de connexion.

## 3. Patreon

Dans Réglages → Patreon, clique sur « Connecter Patreon » : l'OAuth passe par ton serveur, et le secret ne quitte jamais le VPS. Tes créateurs s'affichent alors. Pour chacun, colle ton lien RSS privé (page du créateur → « Écouter sur d'autres applis »). Il est chiffré au repos et n'est jamais renvoyé au client.

## Tests
```
cd packages/bettercast_core && dart test
cd server && dart test
cd apps/bettercast && flutter test
```

## Limites connues / V2
- Les exclusivités Spotify sont inaccessibles, faute de flux audio public. Pour le reste, passe par l'import OPML.
- V2 : affichage synchronisé des transcriptions (`podcast:transcript`, déjà parsé et stocké).
