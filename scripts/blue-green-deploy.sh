#!/usr/bin/env bash
# Bascule blue-green du backend SamaFile derrière le proxy Nginx.
# Usage : bash scripts/blue-green-deploy.sh [deploy|rollback]
# REQUIRE_PULL=1 force le téléchargement des images (pipeline CD).
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION="${1:-deploy}"
COMPOSE=(docker compose --profile blue --profile green)
ACTIVE_DIR=nginx/active
COLOR_FILE="$ACTIVE_DIR/color"
UPSTREAM_FILE="$ACTIVE_DIR/upstream.conf"

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker est introuvable." >&2
    exit 1
fi
if [[ ! -f .env ]]; then
    echo "Copiez .env.example vers .env et remplacez les mots de passe." >&2
    exit 1
fi

mkdir -p "$ACTIVE_DIR"
if [[ ! -f "$COLOR_FILE" ]]; then
    printf 'blue\n' > "$COLOR_FILE"
fi

CURRENT="$(tr -d '[:space:]' < "$COLOR_FILE")"
if [[ "$CURRENT" != "blue" && "$CURRENT" != "green" ]]; then
    echo "Couleur inconnue : $CURRENT" >&2
    exit 1
fi
if [[ "$CURRENT" == "blue" ]]; then
    OTHER=green
else
    OTHER=blue
fi

APP_PORT=8888
if [[ -f .env ]]; then
    found="$(grep -E '^APP_PORT=' .env | tail -n 1 | cut -d= -f2- | tr -d '\r"' || true)"
    if [[ -n "${found:-}" ]]; then
        APP_PORT="$found"
    fi
fi

write_upstream() {
    local color="$1"
    cat > "$UPSTREAM_FILE" <<EOF
upstream samafile_api {
    server backend-${color}:8000;
}
EOF
}

container_id() {
    "${COMPOSE[@]}" ps -aq "$1" | tr -d '[:space:]'
}

health_of() {
    local id
    id="$(container_id "$1")"
    if [[ -z "$id" ]]; then
        echo missing
        return
    fi
    docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id"
}

wait_healthy() {
    local service="$1"
    local status
    local _
    for _ in $(seq 1 36); do
        status="$(health_of "$service")"
        echo "  $service : $status"
        if [[ "$status" == "healthy" ]]; then
            return 0
        fi
        sleep 5
    done
    echo "Le service $service n'est pas devenu healthy." >&2
    "${COMPOSE[@]}" logs --tail 80 "$service" || true
    return 1
}

reload_proxy() {
    "${COMPOSE[@]}" up -d proxy frontend
    local _
    for _ in $(seq 1 15); do
        if docker exec samafile-proxy mkdir -p /etc/nginx/active \
            && docker cp nginx/nginx.conf samafile-proxy:/etc/nginx/nginx.conf \
            && docker cp "$UPSTREAM_FILE" samafile-proxy:/etc/nginx/active/upstream.conf \
            && docker exec samafile-proxy nginx -t \
            && docker exec samafile-proxy nginx -s reload; then
            return 0
        fi
        sleep 2
    done
    echo "Impossible de recharger Nginx." >&2
    return 1
}

smoke() {
    local url="http://127.0.0.1:${APP_PORT}/health"
    local _
    for _ in $(seq 1 15); do
        if curl -fsS "$url" | grep -q '"status"'; then
            echo "Santé OK : $url"
            return 0
        fi
        sleep 2
    done
    echo "Contrôle de santé échoué : $url" >&2
    return 1
}

pull_images() {
    local color="$1"
    if [[ "${REQUIRE_PULL:-0}" == "1" ]]; then
        "${COMPOSE[@]}" pull "backend-${color}" frontend
    fi
}

start_color() {
    local color="$1"
    pull_images "$color"
    "${COMPOSE[@]}" up -d db
    wait_healthy db
    "${COMPOSE[@]}" up -d --force-recreate --no-deps "backend-${color}"
    wait_healthy "backend-${color}"
    write_upstream "$color"
    "${COMPOSE[@]}" up -d --force-recreate --no-deps frontend
    reload_proxy
    smoke
    printf '%s\n' "$color" > "$COLOR_FILE"
}

if [[ "$ACTION" == "rollback" ]]; then
    echo "Retour vers backend-${OTHER}."
    if [[ "$(health_of "backend-${OTHER}")" == "missing" ]]; then
        echo "Aucun conteneur backend-${OTHER} à redémarrer." >&2
        exit 1
    fi
    "${COMPOSE[@]}" start "backend-${OTHER}"
    wait_healthy "backend-${OTHER}"
    write_upstream "$OTHER"
    reload_proxy
    printf '%s\n' "$OTHER" > "$COLOR_FILE"
    "${COMPOSE[@]}" stop "backend-${CURRENT}" || true
    smoke
    exit 0
fi

if [[ "$ACTION" != "deploy" ]]; then
    echo "Usage : $0 [deploy|rollback]" >&2
    exit 1
fi

if [[ "$(health_of "backend-${CURRENT}")" != "healthy" ]]; then
    echo "Premier démarrage sur backend-${CURRENT}."
    start_color "$CURRENT"
    exit 0
fi

echo "Couleur active : ${CURRENT}. Nouvelle version sur backend-${OTHER}."
pull_images "$OTHER"
"${COMPOSE[@]}" up -d db
wait_healthy db
"${COMPOSE[@]}" up -d --force-recreate --no-deps "backend-${OTHER}" frontend
if ! wait_healthy "backend-${OTHER}"; then
    echo "Basculement annulé. backend-${CURRENT} reste en service." >&2
    exit 1
fi
write_upstream "$OTHER"
reload_proxy
if ! smoke; then
    echo "Contrôle échoué. Retour immédiat sur backend-${CURRENT}." >&2
    write_upstream "$CURRENT"
    reload_proxy || true
    exit 1
fi
printf '%s\n' "$OTHER" > "$COLOR_FILE"
"${COMPOSE[@]}" stop "backend-${CURRENT}"
echo "Trafic basculé vers backend-${OTHER}."
