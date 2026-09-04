#!/bin/bash
# Install the backup + health jobs onto the sakanpro.app cPanel host.
#
# They live in /home/sakanpro/ops, OUTSIDE public_html: the backup reads the
# database password, and a file that reads a password must not be fetchable
# over HTTP. Cron is the only scheduler this plan has, and the only way to run
# anything on a schedule without SSH.
set -euo pipefail
export MSYS_NO_PATHCONV=1

SP=$(dirname "$0")
SRC=${1:?usage: install-sakanpro-ops.sh <dir holding ops-backup.php and ops-health.php>}

WORK="${TEMP}/sakanpro-ops-$$"; WORK=${WORK//\\//}
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

CP_USER=sakanpro
CP_HOST=https://sakanpro.app:2083
CP_PASS=$(sed -n 's/^ *cPanel-password: *//p' /c/server/_secrets/sakanpro-live.txt)

curl -s -m 60 -c "$WORK/cookies" -X POST "$CP_HOST/login/?login_only=1" \
  --data-urlencode "user=$CP_USER" --data-urlencode "pass=$CP_PASS" -o "$WORK/login.json"
TOKEN=$(python -c "import json;print(json.load(open(r'$WORK/login.json')).get('security_token',''))")
[ -n "$TOKEN" ] || { echo "cPanel login failed"; exit 1; }

uapi() { curl -s -m 120 -b "$WORK/cookies" -G "$CP_HOST$TOKEN/execute/$1" "${@:2}"; }
api2() { curl -s -m 120 -b "$WORK/cookies" -G "$CP_HOST$TOKEN/json-api/cpanel" \
           --data-urlencode "cpanel_jsonapi_user=$CP_USER" \
           --data-urlencode "cpanel_jsonapi_apiversion=2" "$@"; }

# ── directories, outside the web root ─────────────────────────────────────
# mkdir lives in API 2 only — UAPI has no create_directory, and calling the
# name that does not exist failed silently. The result is CHECKED now: printing
# "ready" whatever the API answered is how a broken install reports success.
for d in ops backups; do
  api2 --data-urlencode "cpanel_jsonapi_module=Fileman" \
       --data-urlencode "cpanel_jsonapi_func=mkdir" \
       --data-urlencode "path=/home/$CP_USER" --data-urlencode "name=$d" \
    > "$WORK/mkdir.json"
  python - "$WORK/mkdir.json" "$d" "/home/$CP_USER" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))['cpanelresult']
rows = result.get('data') or []
made = rows and rows[0].get('name') == sys.argv[2]
# An existing directory is success too - this script has to be safe to re-run.
if not made and 'exist' not in json.dumps(result).lower():
    raise SystemExit('could not create %s/%s: %s' % (sys.argv[3], sys.argv[2], result))
print('  %s/%s' % (sys.argv[3], sys.argv[2]))
PY
done

# ── the scripts ───────────────────────────────────────────────────────────
put() {  # put <local file> <remote name>
  curl -s -m 120 -b "$WORK/cookies" -X POST "$CP_HOST$TOKEN/execute/Fileman/save_file_content" \
    --data-urlencode "dir=/home/$CP_USER/ops" --data-urlencode "file=$2" \
    --data-urlencode "content@$1" \
    | python -c "import sys,json;d=json.load(sys.stdin);assert d['status']==1,d;print('  installed $2')"
}
put "$SRC/ops-backup.php" backup.php
put "$SRC/ops-health.php" health.php
put "$SRC/ops-rehearse.php" rehearse.php
put "$SRC/ops-README.txt" README.txt

# ── schedule ──────────────────────────────────────────────────────────────
# Existing sakanpro cron lines are replaced rather than duplicated: running this
# twice must not give the database two backups a night.
existing=$(api2 --data-urlencode "cpanel_jsonapi_module=Cron" \
                --data-urlencode "cpanel_jsonapi_func=listcron")
python - "$existing" <<'PY'
import json, sys
rows = json.loads(sys.argv[1])['cpanelresult'].get('data') or []
for r in rows:
    cmd = r.get('command', '')
    if 'ops/backup.php' in cmd or 'ops/health.php' in cmd:
        print('  removing an earlier line:', r.get('linekey'))
PY
for key in $(python - "$existing" <<'PY'
import json, sys
rows = json.loads(sys.argv[1])['cpanelresult'].get('data') or []
print(' '.join(str(r['linekey']) for r in rows
               if any(j in r.get('command', '')
                      for j in ('ops/backup.php', 'ops/health.php', 'ops/rehearse.php'))))
PY
); do
  api2 --data-urlencode "cpanel_jsonapi_module=Cron" --data-urlencode "cpanel_jsonapi_func=remove_line" \
       --data-urlencode "linekey=$key" > /dev/null
done

add_cron() {  # add_cron <minute> <hour> <weekday> <command>
  api2 --data-urlencode "cpanel_jsonapi_module=Cron" --data-urlencode "cpanel_jsonapi_func=add_line" \
       --data-urlencode "command=$4" --data-urlencode "minute=$1" --data-urlencode "hour=$2" \
       --data-urlencode "day=*" --data-urlencode "month=*" --data-urlencode "weekday=$3" \
    | python -c "import sys,json;d=json.load(sys.stdin)['cpanelresult']['data'][0];assert d.get('status'),d;print('  scheduled: $1 $2 * * $3')"
}
PHP=/usr/local/bin/ea-php83
add_cron 30 2 '*' "$PHP /home/$CP_USER/ops/backup.php >> /home/$CP_USER/logs/backup.log 2>&1"
add_cron 17 '*' '*' "$PHP /home/$CP_USER/ops/health.php >> /home/$CP_USER/logs/health-run.log 2>&1"
# An hour after Sunday's backup: prove the thing can actually be restored.
add_cron 50 3 0 "$PHP /home/$CP_USER/ops/rehearse.php >> /home/$CP_USER/logs/rehearse-run.log 2>&1"

echo
echo "  crontab now:"
api2 --data-urlencode "cpanel_jsonapi_module=Cron" --data-urlencode "cpanel_jsonapi_func=listcron" \
  | python -c "
import sys, json
for r in json.load(sys.stdin)['cpanelresult'].get('data') or []:
    if 'command' in r:
        print('    %s %s %s %s %s  %s' % (r['minute'], r['hour'], r['day'], r['month'], r['weekday'], r['command']))"
