#!/bin/bash
# عمارتي — container entrypoint: prepare the app, then serve.
set -e

cd /var/www/html

# APP_KEY is normally injected as a stable env var; generate one only if absent
# (it would otherwise change every boot and invalidate encrypted payloads).
if [ -z "$APP_KEY" ]; then
    echo "[entrypoint] APP_KEY empty — generating an ephemeral key"
    php artisan key:generate --force
fi

# Wait for the database to accept connections before migrating (the db is a
# separate container and may still be starting).
echo "[entrypoint] waiting for database..."
for i in $(seq 1 30); do
    if php artisan db:show >/dev/null 2>&1; then
        echo "[entrypoint] database is up"
        break
    fi
    echo "[entrypoint] db not ready yet ($i/30)"; sleep 2
done

# Schema + seed. The seeder is guarded to run only on an empty database, so it
# is safe to invoke on every boot.
php artisan migrate --force
php artisan db:seed --force || true

# Cache config for production speed. Routes are NOT cached because web.php uses
# a closure route (route:cache would abort on it).
php artisan config:clear
php artisan config:cache
php artisan view:cache || true

chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

exec apache2-foreground
