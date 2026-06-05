# عمارتي — Backend API (Laravel + MySQL)

REST API for the عمارتي building-management app. Laravel 13 + Sanctum token
auth + MySQL. Seeded with the same sample data the Flutter app ships, so the app
looks identical but is now backed by a real database.

## Run it

```bash
# 1. Start MySQL (from the repo root, one level up)
cd ..
docker compose up -d db

# 2. Backend deps + migrate + seed
cd backend
php ../composer.phar install          # first time only
php artisan migrate:fresh --seed
php artisan serve --host=127.0.0.1 --port=8000
```

API base: `http://127.0.0.1:8000/api`.
DB: MySQL on `127.0.0.1:3307` (db `amarati`, user `amarati`, pass `secret`) — see
`../docker-compose.yml` and `.env`.

## Demo accounts (password = `password`)

| Role | Email | Phone |
|---|---|---|
| Admin | `admin@amarati.app` | `+966500000001` |
| Resident | `resident@amarati.app` | `+966500000002` |

OTP login works for any phone: `POST /api/auth/request-otp` returns a `dev_code`
in local env (no SMS provider needed), then `POST /api/auth/verify-otp`.

## Endpoints

Auth (public): `POST /auth/register`, `/auth/login`, `/auth/request-otp`,
`/auth/verify-otp`.
Public (guest): `GET /building`, `/summary`, `/pay-types`, `/wa-templates`.
Protected (`Authorization: Bearer <token>`): `GET /me`, `POST /auth/logout`,
`GET /units`, `GET|POST /payments`, `GET|POST /expenses`, `GET|POST /workers`,
`GET /parking`, `GET /guard`, `GET|POST /craftsmen`, `GET /alerts`,
`GET /year-summary`.

All list endpoints are scoped by `?btype=residential|commercial`.

## Notes

- `php artisan serve` is single-threaded; the Flutter repository loads the data
  bundle sequentially to avoid stalling it. A real fpm/nginx deployment handles
  concurrency fine.
- CORS is permissive (`config/cors.php`) for local web review; auth is
  Bearer-token (no cookies).
