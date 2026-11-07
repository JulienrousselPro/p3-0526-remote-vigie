#syntax=docker/dockerfile:1.4

# Image de production Vigie pour le NAS.
# Contexte de build = racine du repo (voir docker-compose.yml : context: ..).
# Le serveur Express sert lui-même le front buildé (client/dist) : un seul conteneur "web".
FROM node:20-alpine

# libc6-compat : compatibilité de certains paquets natifs (argon2, sharp) sur Alpine
# python3, make, g++ : argon2 n'a pas de binaire précompilé pour Alpine, npm le compile
RUN apk add --no-cache libc6-compat python3 make g++

WORKDIR /usr/src/app

# 1) Dépendances d'abord (cache Docker : ne se réinstalle que si les package*.json changent)
COPY package.json package-lock.json ./
COPY client/package.json client/
COPY server/package.json server/
RUN npm ci

# 2) Code source (les .env et node_modules sont exclus par Dockerfile.dockerignore)
COPY . .

# 3) Build du front uniquement.
# ⚠️ Ne PAS lancer `npm run build` à la racine : il enchaîne `db:migrate` qui EFFACE la base.
# VITE_API_URL vide = le front appelle l'API sur le même domaine.
# VITE_PUBLIC_URL est figée dans le bundle : changer de domaine impose de rebuilder.
ARG VITE_API_URL=""
ARG VITE_PUBLIC_URL="http://localhost:3310"
ENV VITE_API_URL=$VITE_API_URL \
    VITE_PUBLIC_URL=$VITE_PUBLIC_URL
RUN npm run build --workspace=client

# 4) Dossier des photos (US27), monté en volume, et exécution sans root
RUN mkdir -p server/uploads && chown -R node:node /usr/src/app/server/uploads
USER node

EXPOSE 3310

# `start` = tsx ./src/main (le serveur lit APP_PORT, DB_*, etc. depuis l'environnement)
CMD ["npm", "run", "start", "--workspace=server"]
