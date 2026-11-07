#!/bin/sh
# Construit l'image vigie-web utilisée par docker-compose.yml.
# Usage (dans ~/vigie/nas) :  sh build.sh
# --network host : le DNS du NAS (systemd-resolved, 127.0.0.53) n'est pas joignable
# depuis les conteneurs de build ; on passe par le réseau de l'hôte pour npm et apk.
set -e
cd "$(dirname "$0")"
PUBLIC_URL=$(grep '^PUBLIC_URL=' .env | cut -d= -f2-)
if [ -z "$PUBLIC_URL" ]; then
	echo "PUBLIC_URL manquant dans .env" >&2
	exit 1
fi
docker build --network host -f Dockerfile --build-arg VITE_PUBLIC_URL="$PUBLIC_URL" -t vigie-web ..
echo "Image vigie-web prête pour $PUBLIC_URL"
