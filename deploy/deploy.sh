#!/bin/bash

STATE_FILE="deploy/active_color"
NGINX_CONF="nginx/default.conf"

ACTIVE=$(cat "$STATE_FILE")

if [ "$ACTIVE" = "blue" ]; then
    INACTIVE="green"
else
    INACTIVE="blue"
fi

echo "Couleur active : $ACTIVE"
echo "Nouvelle couleur : $INACTIVE"

# Démarre uniquement la nouvelle application
docker compose --profile "$INACTIVE" up -d --no-deps "app-$INACTIVE"

# Attend que /health réponde correctement
READY=false

for i in 1 2 3 4 5; do
    if docker compose --profile "$INACTIVE" exec -T "app-$INACTIVE" \
        python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2)" \
        >/dev/null 2>&1
    then
        READY=true
        break
    fi

    echo "Tentative $i/5..."
    sleep 3
done

# Échec : aucune bascule
if [ "$READY" != "true" ]; then
    echo "Echec du déploiement : rollback."
    docker compose --profile "$INACTIVE" stop "app-$INACTIVE"
    exit 1
fi

echo "Smoke test OK."

# Bascule nginx
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;

    location / {
        proxy_pass http://app-$INACTIVE:5000;
    }
}
EOF

docker compose exec -T nginx nginx -s reload

# Mémorise la nouvelle couleur
echo "$INACTIVE" > "$STATE_FILE"

# Arrête l'ancienne application
docker compose --profile "$ACTIVE" stop "app-$ACTIVE"

echo "Déploiement terminé : $INACTIVE"
