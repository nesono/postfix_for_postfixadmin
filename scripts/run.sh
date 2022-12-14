#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

. /scripts/common.sh

echo_start_banner
do_postconf -e 'home_mailbox = Maildir/'
do_postconf -e 'mailbox_command ='
do_postconf -e 'maillog_file=/dev/stdout'

postfix_open_submission_port

echo_exec_banner
exec /usr/sbin/postfix -c /etc/postfix start-fg