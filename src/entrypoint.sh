#!/bin/sh
set -eu

APP_DIR=${APP_DIR:-/var/www/html}
STATE_DIR=${SUITECRM_STATE_DIR:-/var/lib/suitecrm}
PHP_BIN=${PHP_BIN:-/usr/local/bin/php}
WEB_USER=${WEB_USER:-www-data}
WEB_GROUP=${WEB_GROUP:-www-data}

log() {
    printf '[entrypoint] %s\n' "$*"
}

ensure_dir() {
    mkdir -p "$1"
}

link_dir() {
    relative_path="$1"
    app_path="$APP_DIR/$relative_path"
    state_path="$STATE_DIR/$relative_path"

    ensure_dir "$(dirname "$state_path")"
    ensure_dir "$state_path"

    if [ -L "$app_path" ]; then
        chown -h "$WEB_USER:$WEB_GROUP" "$app_path" 2>/dev/null || true
        return
    fi

    if [ -d "$app_path" ]; then
        if [ -z "$(find "$state_path" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
            cp -a "$app_path/." "$state_path/" 2>/dev/null || true
        fi
        rm -rf "$app_path"
    elif [ -e "$app_path" ]; then
        rm -rf "$app_path"
    fi

    ln -s "$state_path" "$app_path"
    chown -h "$WEB_USER:$WEB_GROUP" "$app_path" 2>/dev/null || true
}

link_file() {
    relative_path="$1"
    app_path="$APP_DIR/$relative_path"
    state_path="$STATE_DIR/$relative_path"

    ensure_dir "$(dirname "$state_path")"

    if [ -L "$app_path" ]; then
        chown -h "$WEB_USER:$WEB_GROUP" "$app_path" 2>/dev/null || true
        return
    fi

    if [ -f "$app_path" ] && [ ! -f "$state_path" ]; then
        cp -a "$app_path" "$state_path"
    fi

    rm -f "$app_path"
    ln -s "$state_path" "$app_path"
    chown -h "$WEB_USER:$WEB_GROUP" "$app_path" 2>/dev/null || true
}

prepare_state() {
    ensure_dir "$STATE_DIR"
    ensure_dir "$STATE_DIR/php-sessions"

    for path in \
        Api/V8/OAuth2 \
        cache \
        custom \
	logs \
        upload
    do
        link_dir "$path"
    done

    for path in \
	.htaccess \
        config.php \
        config_override.php
    do
        link_file "$path"
    done
}

write_runtime_env() {
    db_user_encoded=$($PHP_BIN -r 'echo rawurlencode(getenv("DB_USER") ?: "suitecrm");')
    db_password_encoded=$($PHP_BIN -r 'echo rawurlencode(getenv("DB_PASSWORD") ?: "suitecrm");')
    db_name_encoded=$($PHP_BIN -r 'echo rawurlencode(getenv("DB_NAME") ?: "suitecrm");')
    database_url="mysql://${db_user_encoded}:${db_password_encoded}@${DB_HOST:-mariadb}:${DB_PORT:-3306}/${db_name_encoded}?serverVersion=${DATABASE_SERVER_VERSION:-10.11-MariaDB}&charset=utf8mb4"

    cat > "$APP_DIR/.env.local" <<EOF
APP_ENV=${APP_ENV:-prod}
DATABASE_URL=${database_url}
TEMPORARY_FILE_BASE_DIR=${TEMPORARY_FILE_BASE_DIR:-tmp}
MESSENGER_LOG_LEVEL=${MESSENGER_LOG_LEVEL:-error}
EOF

    if [ -n "${MESSENGER_LOG_FILE_NAME:-}" ]; then
        printf 'MESSENGER_LOG_FILE_NAME=%s\n' "$MESSENGER_LOG_FILE_NAME" >> "$APP_DIR/.env.local"
    fi

    if [ -n "${MESSENGER_INTERNAL_ASYNC_TRANSPORT_DSN:-}" ]; then
        printf 'MESSENGER_INTERNAL_ASYNC_TRANSPORT_DSN=%s\n' "$MESSENGER_INTERNAL_ASYNC_TRANSPORT_DSN" >> "$APP_DIR/.env.local"
    fi

    if [ -n "${MESSENGER_INTERNAL_FAILURE_TRANSPORT_DSN:-}" ]; then
        printf 'MESSENGER_INTERNAL_FAILURE_TRANSPORT_DSN=%s\n' "$MESSENGER_INTERNAL_FAILURE_TRANSPORT_DSN" >> "$APP_DIR/.env.local"
    fi
}

fix_permissions() {
    chown -R "$WEB_USER:$WEB_GROUP" "$STATE_DIR"
    find "$STATE_DIR" -type d -exec chmod 2775 {} +
    find "$STATE_DIR" -type f -exec chmod 0664 {} +
    # chmod +x "$APP_DIR/bin/console"
}

generate_oauth_keys() {
    oauth_dir="$STATE_DIR/Api/V8/OAuth2"
    private_key="$oauth_dir/private.key"
    public_key="$oauth_dir/public.key"

    if [ -f "$private_key" ] && [ -f "$public_key" ]; then
        return
    fi

    log "Generating OAuth2 RSA private/public key pair"
    openssl genrsa -out "$private_key" 2048
    openssl rsa -in "$private_key" -pubout -out "$public_key"
    chmod 600 "$private_key" "$public_key"
    chown "$WEB_USER:$WEB_GROUP" "$private_key" "$public_key"
}

prepare_state
write_runtime_env
fix_permissions
generate_oauth_keys

exec "$@"
