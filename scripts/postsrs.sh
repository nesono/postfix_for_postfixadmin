#!/usr/bin/env bash
# Source the postsrsd defaults and launch in foreground
# postsrsd v1 requires -e to read config from environment variables
set -a
. /etc/default/postsrsd
set +a
exec /usr/sbin/postsrsd -e
