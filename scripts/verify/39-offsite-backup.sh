#!/usr/bin/env bash
# verify: the off-site push is configured for real and fails loudly
# tags: fast backup
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$MMDB_ROOT" || exit 1

# SPEC section 18, criterion 7b: backups leave the machine.
#
# This check exists because the setting was present and inert. MMDB_S3_BUCKET
# and its credential files were documented in .env.example, and push_s3 called
# `rclone copy :s3:...` without reading any of them -- so the push ran with no
# credentials, failed, and the failure was swallowed by a log line while
# `backup-all` reported success.
#
# That is the worst shape a backup bug can take: it looks configured. So the
# assertions are about the WIRING, which is checkable without an object store.

need_file "$MMDB_ROOT/scripts/backup"

# 1. The documented settings must actually be read.
for var in MMDB_S3_KEY_ID_FILE MMDB_S3_KEY_SECRET_FILE MMDB_S3_HOST MMDB_S3_REGION; do
    grep -q "$var" "$MMDB_ROOT/scripts/backup" \
        || vfail "$var is documented in .env.example but scripts/backup never reads it"
done
vinfo "every documented S3 setting is read by the backup script"

# 2. rclone must be given credentials, not left to find them.
grep -q 'RCLONE_S3_ACCESS_KEY_ID' "$MMDB_ROOT/scripts/backup" \
    || vfail "scripts/backup does not export rclone credentials; the push would run unauthenticated"
vinfo "rclone is configured from the secret files"

# 3. A failed push must fail the backup. This is the assertion that would have
#    caught the original bug: the code tolerated failure and carried on.
if grep -qE 'rclone copy.*\|\|[[:space:]]*log' "$MMDB_ROOT/scripts/backup"; then
    vfail "a failed off-site push is only logged; backup-all would report success
       having left every backup on the machine it is meant to protect"
fi
grep -q 'the off-site push FAILED' "$MMDB_ROOT/scripts/backup" \
    || vfail "no hard failure path for a failed off-site push"
vinfo "a failed off-site push aborts the backup rather than being logged"

# 4. Credentials travel by the _FILE convention, never in .env.
if grep -qE '^MMDB_S3_(KEY_ID|KEY_SECRET)=' "$MMDB_ROOT/.env.example"; then
    vfail ".env.example carries an S3 credential inline; it must use the _FILE convention"
fi
vinfo "S3 credentials use the _FILE convention"

vinfo "the off-site path is wired, authenticated, and fails loudly"
