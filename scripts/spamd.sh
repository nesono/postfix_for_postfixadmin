#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

test -f /etc/default/spamassassin && . /etc/default/spamassassin | while read -r line; do echo "spamd: $line"; done

noop() {
    while true; do
        # 2147483647 = max signed 32-bit integer
        # 2147483647 s ≅ 70 years
        sleep infinity || sleep 2147483647
    done
}

if [[ -n "${SPAMASS_SOCKET_PATH:-}" ]]; then
  # Taken from /etc/init.d/spamassassin, including the comment below
  export TMPDIR=/tmp
  # Apparently people have trouble if this isn't explicitly set...
  /usr/sbin/spamd --max-children=5 -u debian-spamd --virtual-config-dir=/vhome/users/%u/spamassassin  | \
    while read -r line; do echo "spamd: $line"; done
else
  echo "INFO: Not running Spamd, since no socket path for spamass is set"
  noop
fi