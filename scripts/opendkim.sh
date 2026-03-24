#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

cleanup() {
  if [[ -n "${DKIM_SOCKET_PATH:-}" ]]; then rm -rf "/var/spool/postfix/${DKIM_SOCKET_PATH}"; fi
}
trap cleanup EXIT

noop() {
    while true; do
        # 2147483647 = max signed 32-bit integer
        # 2147483647 s ≅ 70 years
        sleep infinity || sleep 2147483647
    done
}

if [[ -n "${DKIM_SOCKET_PATH:-}" ]]; then
  /usr/sbin/opendkim -f -x /etc/opendkim.conf  | \
    while read -r line; do echo "opendkim: $line"; done
else
  echo "INFO: Not running opendkim, since no socket path is set"
  noop
fi