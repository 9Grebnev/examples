#!/usr/bin/env bash

# Ubuntu 16.04.6 LTS
# Makes backups of Postgres database in Docker

export PATH=/bin:/usr/bin:/usr/local/bin

BACKUP_PATH="/home/user/backup/db"
BACKUP_DATE=`date +"%Y.%m.%d-%H.%M.%S"`
DOCKER_PATH="/home/user/project"
DATABASE_NAME="dbname"
DATABASE_USER="dbuser"
PERIOD=30

function log
{
    echo -e `date +"%d.%m.%Y %k:%M:%S "`"$1";
}

if [[ ! -d "${BACKUP_PATH}/${DATABASE_NAME}" ]]; then
    mkdir -p "${BACKUP_PATH}/${DATABASE_NAME}"
fi

log "Backup started for database - ${DATABASE_NAME}"
cd "${DOCKER_PATH}"

docker-compose exec -T postgres pg_dump --clean --if-exists -U "${DATABASE_USER}" "${DATABASE_NAME}" \
	| gzip > "${BACKUP_PATH}/${DATABASE_NAME}/${BACKUP_DATE}.pgsql.gz"

if [[ $? -eq 0 ]]; then
  log "Database backup successfully completed"
else
  log "Error found during backup"
  exit 1
fi

find "${BACKUP_PATH}/${DATABASE_NAME}" -name "*.sql.gz" -type f -mtime +"${PERIOD}" -exec rm -f {} \;

exit 0