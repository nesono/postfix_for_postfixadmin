#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

. /scripts/common.sh
. /scripts/sql_document_creators.sh

echo_start_banner

# basic configuration
do_postconf -e 'home_mailbox = Maildir/'
do_postconf -e 'mailbox_command ='
do_postconf -e 'maillog_file=/dev/stdout'
do_postconf -e 'smtpd_sender_restrictions=reject_unknown_sender_domain'

# virtual mailboxes
do_postconf -e 'virtual_mailbox_base=/var/mail/'
do_postconf -e 'virtual_mailbox_domains=proxy:mysql:/etc/postfix/sql/mysql_virtual_domains_maps.cf'
do_postconf -e 'virtual_alias_maps=proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_maps.cf, proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_domain_maps.cf, proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_domain_catchall_maps.cf'
do_postconf -e 'virtual_mailbox_maps=proxy:mysql:/etc/postfix/sql/mysql_virtual_mailbox_maps.cf,proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_domain_mailbox_maps.cf'
do_postconf -e 'relay_domains=proxy:mysql:/etc/postfix/sql/mysql_relay_domains.cf'
do_postconf -e 'transport_maps=proxy:mysql:/etc/postfix/sql/mysql_transport_maps.cf'
do_postconf -e 'virtual_minimum_uid=1000'
do_postconf -e 'virtual_uid_maps=static:1000'
do_postconf -e 'virtual_gid_maps=static:1000'

# authentication settings
do_postconf -e 'smtpd_sasl_type=dovecot'
do_postconf -e 'smtpd_sasl_path=/var/spool/postfix/private/auth'
do_postconf -e 'smtp_sasl_auth_enable=yes'
do_postconf -e 'broken_sasl_auth_clients=yes'
do_postconf -e 'smtpd_sasl_security_options=noanonymous,noplaintext'
do_postconf -e 'smtpd_sasl_tls_security_options=noanonymous'
do_postconf -e 'smtpd_tls_auth_only=yes'
do_postconf -e 'smtpd_relay_restrictions=permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination'

# add-ons
#do_postconf -e 'smtpd_delay_reject=yes'
#do_postconf -e 'smtpd_client_restrictions=permit_sasl_authenticated,reject'
#smtpd_sasl_local_domain =


# opens port 587
postfix_open_submission_port

# create mysql
create_virtual_alias_maps
create_virtual_alias_domain_maps
create_virtual_alias_domain_catchall_maps
create_virtual_domains_maps
create_virtual_mailbox_maps
create_virtual_alias_domain_mailbox_maps
create_relay_domains
create_transport_maps
create_virtual_mailbox_limit_maps

# tls configuration
if [[ -n "${TLS_CERT:-}" && -a "${TLS_KEY:-}" ]]; then
  echo "Configuring TLS"
  do_postconf -e "smtpd_tls_cert_file=${TLS_CERT}"
  do_postconf -e "smtpd_tls_key_file=${TLS_KEY}"
  do_postconf -e 'smtpd_tls_security_level=encrypt'
else
  echo "No TLS configured"
fi

echo_exec_banner
exec /usr/sbin/postfix -c /etc/postfix start-fg