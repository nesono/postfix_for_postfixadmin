#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

. /scripts/common.sh
. /scripts/sql_document_creators.sh

echo_start_banner

# basic configuration
if [[ -z "${MYHOSTNAME:-}" ]]; then (>&2 echo "Error: env var MYHOSTNAME not set" && exit 1); fi
if [[ -z "${MYNETWORKS:-}" ]]; then (>&2 echo "Error: env var MYNETWORKS not set" && exit 1); fi
do_postconf -e "myhostname=${MYHOSTNAME}"
do_postconf -e "mynetworks=${MYNETWORKS}"
do_postconf -e 'mydestination = $myhostname, localhost.localdomain, localhost'
do_postconf -e 'home_mailbox=Maildir/'
do_postconf -e 'mailbox_command='
do_postconf -e 'maillog_file=/dev/stdout'
do_postconf -e 'smtpd_sender_restrictions=reject_unlisted_sender,reject_sender_login_mismatch,reject_unknown_sender_domain'

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

# Add SPAM control
do_postconf -e 'smtpd_helo_required=yes'
do_postconf -e 'strict_rfc821_envelopes=yes'
do_postconf -e 'disable_vrfy_command=yes'
RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_unauth_pipelining,reject_non_fqdn_sender,reject_non_fqdn_recipient,reject_unknown_sender_domain"
RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_unknown_recipient_domain,reject_rbl_client zen.spamhaus.org"
RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_rhsbl_reverse_client dbl.spamhaus.org,reject_rhsbl_helo dbl.spamhaus.org"
RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_rhsbl_sender dbl.spamhaus.org"

# Accumulate milters
# Add postgrey milter spec
if [[ -n "${POSTGREY_SOCKET_PATH:-}" ]]; then
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}check_policy_service unix:${POSTGREY_SOCKET_PATH}"
fi
# Add spamass milter spec
if [[ -n "${SPAMASS_SOCKET_PATH:-}" ]]; then
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}check_policy_service unix:${SPAMASS_SOCKET_PATH}"
fi


# Add SPF milter spec
if [[ -n "${SPF_ENABLE:-}" ]]; then
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}check_policy_service unix:private/policyd-spf"
  do_postconf -e 'policyd-spf_time_limit=3600'
  cat <<EOF >> /etc/postfix/master.cf
policyd-spf  unix  -       n       n       -       0       spawn
    user=policyd-spf argv=/usr/bin/policyd-spf
EOF
fi

if [[ -n "${SMTPS_ENABLE:-}" ]]; then
  cat <<EOF >> /etc/postfix/master.cf
smtps     inet  n       -       -       -       -       smtpd
  -o smtpd_tls_wrappermode=yes
EOF
fi


# authentication settings - put this behind a switch?
if [[ -n "${DOVECOT_SASL_SOCKET_PATH:-}" ]]; then
  echo "Configuring Dovecot SASL"
  do_postconf -e 'smtpd_sasl_type=dovecot'
  do_postconf -e "smtpd_sasl_path=${DOVECOT_SASL_SOCKET_PATH}"
  do_postconf -e 'smtpd_sasl_auth_enable=yes'
  do_postconf -e 'broken_sasl_auth_clients=yes'
  do_postconf -e 'smtpd_sasl_security_options=noanonymous,noplaintext'
  do_postconf -e 'smtpd_sasl_tls_security_options=noanonymous'
  do_postconf -e 'smtpd_tls_auth_only=yes'
  do_postconf -e 'smtpd_relay_restrictions=permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination'
  # expand the recipient restrictions (accounts for if the restrictions have already been set and adds a comma in such a case)
  RCP_RESTR="permit_mynetworks,permit_sasl_authenticated${RCP_RESTR:+,$RCP_RESTR}"

  # add-ons
  do_postconf -e 'smtpd_delay_reject=yes'
  do_postconf -e 'smtpd_client_restrictions=permit_mynetworks,permit_sasl_authenticated,reject'
  #smtpd_sasl_local_domain =
else
  echo "No Dovecot SASL configured"
fi

RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_unauth_destination"

# Show configured milters / recipient restrictions
if [[ -n "${RCP_RESTR:-}" ]]; then
  echo "Activating smtpd_recipient_restrictions with:"
  echo "   smtpd_recipient_restrictions=${RCP_RESTR}"
  do_postconf -e "smtpd_recipient_restrictions=${RCP_RESTR:-}"
fi

# Add DKIM milter spec
if [[ -n "${DKIM_SOCKET_PATH:-}" ]]; then
  SMTPD_MILTERS="${SMTPD_MILTERS:+$SMTPD_MILTERS,}local:${DKIM_SOCKET_PATH}"
fi

# Add DMARC milter spec
if [[ -n "${DMARC_SOCKET_PATH:-}" ]]; then
  SMTPD_MILTERS="${SMTPD_MILTERS:+$SMTPD_MILTERS,}local:${DMARC_SOCKET_PATH}"
fi

# Configure SMTPD milters
if [[ -n "${SMTPD_MILTERS:-}" ]]; then
  echo "Activating smtpd_milters with:"
  echo "   smtpd_milters=${SMTPD_MILTERS}"
  do_postconf -e "smtpd_milters=${SMTPD_MILTERS}"
  #do_postconf -e 'milter_default_action=accept'
  do_postconf -e 'milter_protocol=6'
  do_postconf -e 'non_smtpd_milters=$smtpd_milters'
fi

if [[ -n "${DOVECOT_LMTP_PATH:-}" ]]; then
  echo "Configure Dovecot LMTP"
  do_postconf -e "local_transport=lmtp:unix:${DOVECOT_LMTP_PATH}"
  do_postconf -e "virtual_transport=lmtp:unix:${DOVECOT_LMTP_PATH}"
else
  echo "No Dovecot LMTP configured"
fi

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
if [[ -n "${TLS_CERT:-}" && -n "${TLS_KEY:-}" ]]; then
  echo "Configuring TLS"
  do_postconf -e "smtpd_tls_cert_file=${TLS_CERT}"
  do_postconf -e "smtpd_tls_key_file=${TLS_KEY}"
  do_postconf -e 'smtpd_tls_security_level=may' # allow non tls on localhost
  do_postconf -e 'smtpd_tls_mandatory_protocols=>=TLSv1.2'
else
  echo "No TLS configured"
fi

# run the postfix instance configuration taken from the /etc/init.d/postfix script
/usr/lib/postfix/configure-instance.sh

echo_exec_banner
exec supervisord -c /etc/supervisord.conf