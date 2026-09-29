#!/bin/bash

set -euo pipefail

STATE_DIR="$HOME/.esiea-devops"
ACTIVE_FILE="$STATE_DIR/active_color"
SHA_FILE="$STATE_DIR/current_sha"
VERSION_FILE="$STATE_DIR/current_version"

NGINX_CONF="nginx/default.conf"

: "${IMAGE_NAME:?IMAGE_NAME manquant}"
: "${IMAGE_TAG:?IMAGE_TAG manquant}"
: "${APP_VERSION:?APP_VERSION manquant}"
: "${COMMIT_SHA:?COMMIT_SHA manquant}"

mkdir -p "$STATE_DIR"


write_nginx_config() {
    COLOR="$1"

    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;

    location / {
        proxy_pass http://app-$COLOR:5000;
    }
}
EOF
}


check_health() {
    for i in 1 2 3; do
        if curl -fsS http://localhost:8080/health >/dev/null; then
            return 0
        fi

        echo "Tentative $i/3..."
        sleep 5
    done

    return 1
}


# Premier déploiement
if [ ! -f "$ACTIVE_FILE" ]; then
    echo "Premier déploiement : initialisation blue."

    export IMAGE_NAME
    export IMAGE_TAG
    export APP_VERSION
    export COMMIT_SHA

    docker compose --profile blue pull app-blue

    docker compose up -d redis

    docker compose --profile blue up \
        -d \
        --no-build \
        app-blue

    write_nginx_config blue

    docker compose up -d nginx prometheus
    docker compose exec -T nginx nginx -s reload

    if ! check_health; then
        echo "Echec du premier déploiement."
        exit 1
    fi

    echo "blue" > "$ACTIVE_FILE"
    echo "$IMAGE_TAG" > "$SHA_FILE"
    echo "$APP_VERSION" > "$VERSION_FILE"

    echo "Déploiement terminé : blue"
    exit 0
fi


ACTIVE=$(cat "$ACTIVE_FILE")
PREVIOUS_SHA=$(cat "$SHA_FILE")
PREVIOUS_VERSION=$(cat "$VERSION_FILE")

if [ "$ACTIVE" = "blue" ]; then
    INACTIVE="green"
else
    INACTIVE="blue"
fi

echo "Couleur active : $ACTIVE"
echo "Nouvelle couleur : $INACTIVE"
echo "SHA précédent : $PREVIOUS_SHA"
echo "Nouveau SHA : $IMAGE_TAG"


# Démarre la nouvelle version
export IMAGE_NAME
export IMAGE_TAG
export APP_VERSION
export COMMIT_SHA

docker compose --profile "$INACTIVE" pull "app-$INACTIVE"

docker compose --profile "$INACTIVE" up \
    -d \
    --no-build \
    --no-deps \
    "app-$INACTIVE"


# Vérification interne avant bascule
READY=false

for i in 1 2 3; do
    if docker compose --profile "$INACTIVE" exec -T "app-$INACTIVE" \
        python -c \
        "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2)" \
        >/dev/null 2>&1
    then
        READY=true
        break
    fi

    echo "Vérification interne $i/3..."
    sleep 5
done


if [ "$READY" != "true" ]; then
    echo "Echec avant bascule."

    docker compose --profile "$INACTIVE" stop "app-$INACTIVE"

    exit 1
fi


# Bascule nginx
write_nginx_config "$INACTIVE"

docker compose exec -T nginx nginx -s reload


# Vérification publique après déploiement
if check_health; then
    echo "$INACTIVE" > "$ACTIVE_FILE"
    echo "$IMAGE_TAG" > "$SHA_FILE"
    echo "$APP_VERSION" > "$VERSION_FILE"

    docker compose --profile "$ACTIVE" stop "app-$ACTIVE"

    echo "Déploiement terminé : $INACTIVE"
    exit 0
fi


# Rollback
echo "Healthcheck en échec : rollback vers $PREVIOUS_SHA."

write_nginx_config "$ACTIVE"

docker compose exec -T nginx nginx -s reload

docker compose --profile "$INACTIVE" stop "app-$INACTIVE"


IMAGE_TAG="$PREVIOUS_SHA" \
APP_VERSION="$PREVIOUS_VERSION" \
COMMIT_SHA="$PREVIOUS_SHA" \
docker compose --profile "$ACTIVE" pull "app-$ACTIVE"


IMAGE_TAG="$PREVIOUS_SHA" \
APP_VERSION="$PREVIOUS_VERSION" \
COMMIT_SHA="$PREVIOUS_SHA" \
docker compose --profile "$ACTIVE" up \
    -d \
    --no-build \
    --no-deps \
    "app-$ACTIVE"


echo "Rollback terminé."

exit 1