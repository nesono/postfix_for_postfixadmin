#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

noop() {
    while true; do
        sleep infinity || sleep 2147483647
    done
}

if [[ "${POSTFIX_EXPORTER_ENABLE:-}" == "1" ]]; then
  exec /usr/local/bin/postfix_exporter \
    --postfix.logfile_path=/var/log/mail.log \
    --postfix.showq_path=/var/spool/postfix/public/showq
else
  echo "INFO: Not running postfix_exporter, since POSTFIX_EXPORTER_ENABLE is not set"
  noop
fi
