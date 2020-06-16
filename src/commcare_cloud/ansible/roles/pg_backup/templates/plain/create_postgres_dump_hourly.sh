#!/bin/bash
BACKUP_TYPE=$1
HOURS_TO_RETAIN_BACKUPS=$2
ENV="{{ deploy_env }}"
HOSTNAME=$(hostname)
TODAY=$(date +"%Y_%m_%d_%H")
FILENAME="postgres_${ENV}_${BACKUP_TYPE}_${TODAY}"
DIRECTORY="{{ postgresql_backup_dir }}/${FILENAME}"

{% if not aws_versioning_enabled%}
UPLOAD_NAME="${FILENAME}"
{% else %}
UPLOAD_NAME="postgres_${BACKUP_TYPE}_${HOSTNAME}"
{% endif %}


ARGS=""

{% if backup_postgres=='plain' %}
CMD="pg_basebackup"
ARGS="-Fp -Xs -D $DIRECTORY"
{% if pg_backup_from %}
ARGS="$ARGS -h {{ pg_backup_from }} -w -U{{ postgres_users['replication']['username'] }}"
{% endif %}

{% elif backup_postgres=='dump' %}
CMD="pg_dumpall"
{% if pg_backup_from %}
ARGS="$ARGS -h {{ pg_backup_from }} -w -U{{ postgres_users['backup']['username'] }}"
{% endif %}
ARGS="$ARGS | gzip > $DIRECTORY.gz"
{% endif %}

sh -c "$CMD $ARGS"

if [[ $? -ne 0 ]] ; then
    echo "Postgres Backup : pg_basebackup Failed"
    exit 1
fi

if [ -d "$DIRECTORY" ]; then
    tar -czf "${DIRECTORY}.tar.gz" "${DIRECTORY}" && rm -rf "${DIRECTORY}"
fi

if [[ $? -ne 0 ]] ; then
    echo "Postgres Backup : Tar Failed"
    exit 2
else
    find {{ postgresql_backup_dir }} -mmin "+$HOURS_TO_RETAIN_BACKUPS" -name "postgres_${ENV}_${BACKUP_TYPE}_*" -delete
    find {{ postgresql_backup_dir }} -mmin "+$HOURS_TO_RETAIN_BACKUPS" -name "postgres_${BACKUP_TYPE}_*" -delete
fi

# Remove old backups of this backup type, if backup succeded


{% if postgres_s3 %}
if [ -f "${DIRECTORY}.gz" ]; then
    ( cd {{ postgresql_backup_dir }} && /usr/local/sbin/backup_snapshots.py "${FILENAME}.gz" "${UPLOAD_NAME}.gz" {{ postgres_snapshot_bucket }} {{aws_endpoint}}  )
fi
if [ -f "${DIRECTORY}.tar.gz" ]; then
    ( cd {{ postgresql_backup_dir }} && /usr/local/sbin/backup_snapshots.py "${FILENAME}.tar.gz" "${UPLOAD_NAME}.tar.gz" {{ postgres_snapshot_bucket }} {{aws_endpoint}}  )
fi
{% endif %}

if [[ $? -ne 0 ]] ; then
    echo "Postgres Backup : /usr/local/sbin/backup_snapshots.py Failed"
    exit 3
fi

exit 0
