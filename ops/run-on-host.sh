#!/bin/bash
# Run one PHP file on the sakanpro.app host and print what it printed.
#
# There is no SSH on this plan, so this is how anything gets executed there:
# upload a file into the web root, fetch it once, delete it. The file never
# outlives the call — an executable script left in a public directory is a
# back door, and its name is only unguessable until someone guesses it.
#
# Usage:  bash sakanpro-run.sh <local-php-file> [query-string]
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT=${1:?usage: sakanpro-run.sh <local-php-file> [query-string]}
QUERY=${2:-}

WORK="${TEMP}/sakanpro-run-$$"; WORK=${WORK//\\//}
mkdir -p "$WORK"

CP_USER=sakanpro
CP_HOST=https://sakanpro.app:2083
CP_PASS=$(sed -n 's/^ *cPanel-password: *//p' /c/server/_secrets/sakanpro-live.txt)

curl -s -m 60 -c "$WORK/cookies" -X POST "$CP_HOST/login/?login_only=1" \
  --data-urlencode "user=$CP_USER" --data-urlencode "pass=$CP_PASS" -o "$WORK/login.json"
TOKEN=$(python -c "import json;print(json.load(open(r'$WORK/login.json')).get('security_token',''))")
[ -n "$TOKEN" ] || { echo "cPanel login failed"; rm -rf "$WORK"; exit 1; }

NAME="_run-$(python -c 'import secrets;print(secrets.token_hex(10))').php"

remove() {
  curl -s -m 60 -b "$WORK/cookies" -G "$CP_HOST$TOKEN/json-api/cpanel" \
    --data-urlencode "cpanel_jsonapi_user=$CP_USER" \
    --data-urlencode "cpanel_jsonapi_apiversion=2" \
    --data-urlencode "cpanel_jsonapi_module=Fileman" \
    --data-urlencode "cpanel_jsonapi_func=fileop" \
    --data-urlencode "op=unlink" \
    --data-urlencode "sourcefiles=/home/$CP_USER/public_html/$NAME" \
    --data-urlencode "doubledecode=0" > /dev/null 2>&1 || true
  rm -rf "$WORK"
}
# Deleted even if the fetch fails, times out, or the shell is interrupted.
trap remove EXIT

curl -s -m 60 -b "$WORK/cookies" -X POST "$CP_HOST$TOKEN/execute/Fileman/save_file_content" \
  --data-urlencode "dir=/home/$CP_USER/public_html" --data-urlencode "file=$NAME" \
  --data-urlencode "content@$SCRIPT" \
  | python -c "import sys,json;d=json.load(sys.stdin);assert d['status']==1,d" \
  || { echo "upload failed"; exit 1; }

curl -s -m 600 "https://sakanpro.app/$NAME${QUERY:+?$QUERY}"
