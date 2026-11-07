# Déployer Vigie sur le NAS (gratuit, sans ouvrir de port)

Adresse publique : `https://vigie.<tailnet>.ts.net`, fournie gratuitement par Tailscale Funnel.
Le NAS ouvre un tunnel **sortant** vers Tailscale : rien à configurer sur la Freebox,
l'IP de la maison n'est pas exposée, et seul le conteneur `web` est joignable.

```
Visiteur ──HTTPS──▶ Tailscale (Funnel) ══tunnel sortant══▶ conteneur tailscale ──▶ web:3310 ──▶ db
                                                            (réseau Docker "vigie", isolé du reste du NAS)
```

Durée : environ 1 h. Les étapes 1 à 4 se font dans le navigateur, la 5 et la suite en SSH sur le NAS.

---

## 0. Préparer le dépôt (sur le PC)

```bash
git checkout main
git pull
git merge dev
git add nas server/src/app.ts   # nas/.gitignore exclut le .env
git commit -m "chore(nas): déploiement sécurisé via Tailscale Funnel"
git push
```

`server/src/app.ts` reçoit 4 lignes (`trust proxy`) : sans elles, tous les visiteurs auraient
la même IP vue du serveur et les limites par IP (inscription…) seraient communes à tout le monde.

## 1. Créer le compte Tailscale (gratuit, sans carte bancaire)

1. Aller sur <https://login.tailscale.com/start> et se connecter avec le compte Google.
2. Quand il propose d'ajouter un appareil, passer cette étape.

## 2. Règles d'accès (Access controls)

Menu **Access controls** → remplacer tout le contenu par :

```json
{
  "tagOwners": {
    "tag:vigie": ["autogroup:admin"]
  },
  "acls": [
    { "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self:*"] }
  ],
  "nodeAttrs": [
    { "target": ["tag:vigie"], "attr": ["funnel"] }
  ]
}
```

- `tag:vigie` : l'étiquette de la machine Vigie.
- Aucune règle ne part de `tag:vigie` : **la machine Vigie ne peut joindre aucun autre appareil**.
- `funnel` : seule la machine Vigie a le droit d'être publiée sur Internet.

Cliquer **Save**.

## 3. Activer le HTTPS et noter le nom du tailnet

Menu **DNS** :

1. Vérifier que **MagicDNS** est activé.
2. Section **HTTPS Certificates** → **Enable HTTPS**.
3. Noter le **Tailnet DNS name**, du type `tail1a2b3c.ts.net`.
   (Facultatif : **Rename tailnet…** pour choisir un nom plus lisible parmi ceux proposés,
   AVANT le premier démarrage.)

L'adresse de Vigie sera : `https://vigie.tail1a2b3c.ts.net`

## 4. Clé d'authentification et mot de passe Gmail

**Clé Tailscale** : **Settings** → **Keys** → **Generate auth key…**

- Reusable : non
- Expiration : 1 jour (elle ne sert qu'au premier démarrage)
- Ephemeral : non
- **Tags** : activer, choisir `tag:vigie`

Copier la clé `tskey-auth-…`.

**Gmail** : <https://myaccount.google.com/apppasswords> (la validation en 2 étapes doit être
active). Nom : `Vigie`. Copier le mot de passe de 16 caractères (sans les espaces).

## 5. Installer sur le NAS

```bash
ssh Julien@192.168.1.200
cd ~
git clone https://github.com/JulienrousselPro/p3-0526-remote-vigie.git vigie
cd vigie/nas
cp .env.example .env
chmod 600 .env
```

Si `git clone` demande un mot de passe, le dépôt est privé : créer sur GitHub un jeton
(**Settings → Developer settings → Fine-grained tokens**, accès en lecture au contenu de ce dépôt
seulement) et le coller comme mot de passe.

Générer les secrets (3 fois la commande, une valeur par ligne du `.env`) :

```bash
openssl rand -hex 32   # → APP_SECRET
openssl rand -hex 24   # → DB_PASSWORD
openssl rand -hex 24   # → DB_ROOT_PASSWORD
```

Générer les clés Web Push (une seule fois, à ne jamais régénérer) :

```bash
docker run --rm node:20-alpine npx -y web-push generate-vapid-keys
```

Remplir le `.env` :

```bash
nano .env
```

| Variable | Valeur |
|---|---|
| `PUBLIC_URL` | `https://vigie.tail1a2b3c.ts.net` (ton tailnet, sans slash final) |
| `APP_SECRET`, `DB_PASSWORD`, `DB_ROOT_PASSWORD` | les valeurs générées |
| `TS_AUTHKEY` | la clé `tskey-auth-…` |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | ton adresse Gmail / le mot de passe d'application |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `METEO_API_KEY` | les mêmes que dans `server/.env` sur le PC |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` | les clés générées |
| `VAPID_SUBJECT` | `mailto:` + ton adresse Gmail |

Enregistrer : `Ctrl+O`, `Entrée`, `Ctrl+X`.

## 6. Construire et créer la base (une seule fois)

```bash
docker compose build web
docker compose up -d db
docker compose ps            # attendre que db soit "healthy" (30 s environ)
docker compose run --rm web npm run db:migrate --workspace=server
```

⚠️ `db:migrate` **supprime puis recrée** la base : ne le lancer qu'ici, jamais après.
Ne jamais lancer `db:seed` (il crée des comptes admin1 à admin4 avec le mot de passe `1234`).

## 7. Démarrer

```bash
docker compose up -d
docker compose ps                  # web et db "healthy", tailscale "running"
docker compose logs -f tailscale   # Ctrl+C pour quitter
```

Tester depuis le téléphone **en 4G** (pas en Wi-Fi) : `https://vigie.tail1a2b3c.ts.net`.
Le premier affichage peut prendre une minute (création du certificat HTTPS).

## 8. Connexion Google

Console Google Cloud → projet « Vigie » → **APIs et services → Identifiants** → client OAuth :

- **Origines JavaScript autorisées** : `https://vigie.tail1a2b3c.ts.net`
- **URI de redirection autorisés** : `https://vigie.tail1a2b3c.ts.net/api/auth/google/callback`

Écran de consentement : s'il est en mode **Test**, seuls les « utilisateurs test » listés peuvent se
connecter avec Google. Pour la démonstration au jury, ajouter les comptes voulus ou publier l'application.

## 9. Vérifier

1. S'inscrire avec ta vraie adresse : l'e-mail de vérification doit arriver (regarder les spams).
2. Ajouter une adresse surveillée, publier un signalement, vérifier l'e-mail d'alerte.
3. Depuis le NAS, vérifier que MySQL n'est pas exposé : `docker compose port db 3306` ne doit rien renvoyer.

---

## Au quotidien

| Besoin | Commande (dans `~/vigie/nas`) |
|---|---|
| Mettre à jour après un `git push` | `git pull && docker compose up -d --build web` |
| Couper l'accès public immédiatement | `docker compose stop tailscale` |
| Tout arrêter (données conservées) | `docker compose down` |
| Voir les erreurs du serveur | `docker compose logs --tail 100 web` |
| Sauvegarder la base | voir ci-dessous |

Sauvegarde :

```bash
docker compose exec db sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction "$MYSQL_DATABASE"' > ~/vigie-$(date +%F).sql
```

Restauration (dans la base existante) :

```bash
docker compose exec -T db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < ~/vigie-AAAA-MM-JJ.sql
```

Ne jamais lancer `docker compose down -v` : le `-v` efface la base et les photos.

## En cas de problème

| Symptôme | Piste |
|---|---|
| Logs tailscale : `funnel not available` ou `not allowed` | Étape 2 (`nodeAttrs` funnel) ou étape 3 (HTTPS non activé) |
| Logs tailscale : `invalid key` / `requires tags` | Clé expirée ou sans le tag `tag:vigie` : en recréer une (étape 4), puis `docker compose rm -sf tailscale && docker volume rm vigie_ts-state && docker compose up -d` |
| Page « 502 » sur l'adresse publique | `docker compose ps` : `web` doit être "healthy" ; sinon `docker compose logs web` |
| L'adresse est `vigie-1.…` au lieu de `vigie.…` | Une ancienne machine « vigie » existe dans la console Tailscale (**Machines**) : la supprimer, puis refaire le point ci-dessus |
| Les e-mails ne partent pas | `SMTP_USERNAME`/`SMTP_PASSWORD` (mot de passe d'application, pas celui du compte) |
