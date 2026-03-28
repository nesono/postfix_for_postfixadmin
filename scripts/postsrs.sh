#!/usr/bin/env bash
# Source the postsrsd defaults and launch in foreground with explicit args
. /etc/default/postsrsd
exec /usr/sbin/postsrsd \
  -d"${SRS_DOMAIN}" \
  -s"${SRS_SECRET}" \
  -f"${SRS_FORWARD_PORT:-10001}" \
  -r"${SRS_REVERSE_PORT:-10002}" \
  -u"${RUN_AS:-postsrsd}" \
  ${SRS_EXCLUDE_DOMAINS:+-X"${SRS_EXCLUDE_DOMAINS}"}
