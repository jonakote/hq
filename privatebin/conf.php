; PrivateBin config — Database (PostgreSQL) backend, pointed at the shared
; ../postgres/ instance. STORAGE_HOST/LOGIN/PASSWORD/CONTAINER are the
; image's documented env-var passthrough for this exact purpose (see
; https://github.com/PrivateBin/docker-nginx-fpm-alpine, "Custom backend
; settings") — this file just wires them into the Database model.
; Role/db provisioned by ../postgres/init/10-app-databases.sh.
[model]
class = Database
[model_options]
dsn = "pgsql:host=${STORAGE_HOST};dbname=${STORAGE_CONTAINER}"
tbl = "privatebin_" ; table prefix
usr = ${STORAGE_LOGIN}
pwd = ${STORAGE_PASSWORD}
opt[12] = true ; PDO::ATTR_PERSISTENT

[traffic]
; time limit between calls from the same IP address in seconds
limit = 10

[purge]
limit = 300
batchsize = 10
