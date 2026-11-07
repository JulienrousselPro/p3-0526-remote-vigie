# Déployer Vigie sur le NAS

**Adresse publique : <https://vigie.ibis-heptatonic.ts.net>**

Gratuit, sans nom de domaine à acheter, sans port ouvert sur la Freebox. Le NAS ouvre un tunnel
**sortant** vers Tailscale (Funnel) ; seul le conteneur `web` de Vigie est joignable depuis Internet.

```
Visiteur ──HTTPS──▶ Tailscale Funnel ══tunnel sortant══▶ conteneur tailscale ──▶ web:3310 ──▶ db
                                                          (réseau Docker « vigie », isolé du reste du NAS)
```

| Étape | Où | État |
|---|---|---|
| 1. Dépôt à jour (`dev` fusionnée dans `main`) | PC | ✅ fait |
| 2. Compte Tailscale | navigateur | ✅ fait |
| 3. Règles d'accès | navigateur | ✅ fait |
| 4. HTTPS activé | navigateur | à vérifier |
| 5. Clé Tailscale + mot de passe Gmail | navigateur | à faire |
| 6. Installation | NAS (SSH) | à faire |
| 7. Base de données | NAS (SSH) | à faire |
| 8. Démarrage et test | NAS + téléphone | à faire |
| 9. Connexion Google | navigateur | à faire |

---

## 1 à 3. Déjà faits

- `main` contient le dossier `nas/` (commit `dfbf391`).
- Compte Tailscale : `julienrousselpro13@gmail.com`, tailnet **`ibis-heptatonic.ts.net`**.
- Règles d'accès (**Contrôles d'accès → JSON editor**) :

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

La machine Vigie (`tag:vigie`) ne peut joindre aucun autre appareil ; elle seule peut être publiée.

## 4. Vérifier le HTTPS

**Réseau → DNS** :

- **MagicDNS** : activé
- **HTTPS Certificates** : activé (bouton **Enable HTTPS**)

## 5. Clé Tailscale et mot de passe Gmail

**Clé Tailscale** : **Paramètres → Keys → Generate auth key…**

| Option | Valeur |
|---|---|
| Reusable | non |
| Expiration | 1 jour (elle ne sert qu'au premier démarrage) |
| Ephemeral | non |
| Tags | activé → `tag:vigie` |

Copier la clé `tskey-auth-…` (elle ne s'affiche qu'une fois).

**Gmail** : <https://myaccount.google.com/apppasswords> (validation en 2 étapes obligatoire),
nom `Vigie`. Copier le mot de passe de 16 caractères, **sans les espaces**.

Ces deux valeurs sont secrètes : elles ne vont que dans le `.env` du NAS.

## 6. Installation sur le NAS

```bash
ssh Julien@192.168.1.200
cd ~
git clone https://github.com/JulienrousselPro/p3-0526-remote-vigie.git vigie
cd vigie/nas
touch .env
chmod 600 .env
```

Si `git clone` demande un mot de passe, le dépôt est privé : sur GitHub, **Settings → Developer
settings → Fine-grained tokens**, jeton en lecture seule sur ce dépôt, à coller comme mot de passe.

Préparer les secrets (noter chaque résultat) :

```bash
openssl rand -hex 32                                           # APP_SECRET
openssl rand -hex 24                                           # DB_PASSWORD
openssl rand -hex 24                                           # DB_ROOT_PASSWORD
docker run --rm node:20-alpine npx -y web-push generate-vapid-keys   # VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY
```

Ouvrir le fichier vide avec `nano .env`, coller ce modèle (clic droit dans le terminal) et remplacer
chaque `…` :

```ini
PUBLIC_URL=https://vigie.ibis-heptatonic.ts.net
WEB_PORT=3310

APP_SECRET=…

DB_NAME=vigie
DB_USER=vigie
DB_PASSWORD=…
DB_ROOT_PASSWORD=…

TS_AUTHKEY=tskey-auth-…

SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=…@gmail.com
SMTP_PASSWORD=…

# mêmes valeurs que dans server/.env sur le PC
GOOGLE_CLIENT_ID=…
GOOGLE_CLIENT_SECRET=…
METEO_API_KEY=…

VAPID_PUBLIC_KEY=…
VAPID_PRIVATE_KEY=…
VAPID_SUBJECT=mailto:…@gmail.com
```

Enregistrer : `Ctrl+O`, `Entrée`, `Ctrl+X`.

## 7. Construire l'image et créer la base (une seule fois)

```bash
docker compose build web
docker compose up -d db
docker compose ps
```

Attendre que `db` affiche `healthy` (relancer `docker compose ps` toutes les 10 s), puis :

```bash
docker compose run --rm web npm run db:migrate --workspace=server
```

> ⚠️ `db:migrate` **supprime puis recrée** la base : ne le lancer qu'ici, jamais ensuite.
> Ne jamais lancer `db:seed` en production (comptes admin1 à admin4, mot de passe `1234`).

## 8. Démarrer et tester

```bash
docker compose up -d
docker compose ps
docker compose logs -f tailscale      # Ctrl+C pour quitter
```

Attendu : `web` et `db` en `healthy`, `tailscale` en `running`, sans erreur dans les logs.

Sur le téléphone **en 4G** (pas en Wi-Fi) : <https://vigie.ibis-heptatonic.ts.net>.
Le premier affichage peut prendre une minute (création du certificat HTTPS).

Vérifications :

1. S'inscrire avec une vraie adresse : l'e-mail de vérification arrive (regarder les spams).
2. Ajouter une adresse surveillée, publier un signalement, recevoir l'e-mail d'alerte.
3. Sur le NAS : `docker compose port db 3306` ne renvoie rien (MySQL n'est pas exposé).

## 9. Connexion Google

Console Google Cloud → projet « Vigie » → **APIs et services → Identifiants** → client OAuth :

- Origines JavaScript autorisées : `https://vigie.ibis-heptatonic.ts.net`
- URI de redirection autorisés : `https://vigie.ibis-heptatonic.ts.net/api/auth/google/callback`

Écran de consentement en mode **Test** : seuls les « utilisateurs test » listés peuvent se connecter
avec Google. Pour le jury, ajouter leurs adresses ou publier l'application.

Si Google refuse l'adresse en `.ts.net`, le bouton Google ne fonctionnera pas en ligne ;
le reste de Vigie n'est pas concerné.

---

## Au quotidien (dans `~/vigie/nas`)

| Besoin | Commande |
|---|---|
| Mettre à jour après un `git push` | `git pull && docker compose up -d --build web` |
| Couper l'accès public immédiatement | `docker compose stop tailscale` |
| Rouvrir l'accès public | `docker compose start tailscale` |
| Tout arrêter (données conservées) | `docker compose down` |
| Voir les erreurs du serveur | `docker compose logs --tail 100 web` |

**Sauvegarde de la base :**

```bash
docker compose exec db sh -c 'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction "$MYSQL_DATABASE"' > ~/vigie-$(date +%F).sql
```

**Restauration :**

```bash
docker compose exec -T db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < ~/vigie-AAAA-MM-JJ.sql
```

Ne jamais lancer `docker compose down -v` : le `-v` efface la base et les photos.

## En cas de problème

| Symptôme | Piste |
|---|---|
| Logs tailscale : `funnel not available` / `not allowed` | Règles d'accès (`nodeAttrs` funnel) ou HTTPS non activé (étape 4) |
| Logs tailscale : `invalid key` / `requires tags` | Clé expirée ou sans `tag:vigie` : en recréer une, la mettre dans `.env`, puis `docker compose rm -sf tailscale && docker volume rm vigie_ts-state && docker compose up -d` |
| Erreur 502 sur l'adresse publique | `docker compose ps` : `web` doit être `healthy` ; sinon `docker compose logs web` |
| L'adresse devient `vigie-1.…` | Une ancienne machine « vigie » existe (**Réseau → Machines**) : la supprimer, puis refaire la ligne `invalid key` ci-dessus |
| Les e-mails ne partent pas | `SMTP_USERNAME` / `SMTP_PASSWORD` : mot de passe d'application, pas celui du compte |
| `db` ne devient jamais `healthy` | `docker compose logs db` ; vérifier `DB_PASSWORD` et `DB_ROOT_PASSWORD` dans `.env` |
