#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset
set -x

. /scripts/common.sh
. /scripts/sql_document_creators.sh

echo_start_banner

# basic configuration
if [[ -z "${MYHOSTNAME:-}" ]]; then (>&2 echo "Error: env var MYHOSTNAME not set" && exit 1); fi
if [[ -z "${MYNETWORKS:-}" ]]; then (>&2 echo "Error: env var MYNETWORKS not set" && exit 1); fi

# patch SRS configuration (postsrsd v1 on Ubuntu 24.04 uses /etc/default/postsrsd)
if ! grep -q "^SRS_DOMAIN=" /etc/default/postsrsd; then
  echo "SRS_DOMAIN=${MYHOSTNAME}" >> /etc/default/postsrsd
fi

do_postconf -e "myhostname=${MYHOSTNAME}"
do_postconf -e "mynetworks=${MYNETWORKS}"
do_postconf -e 'mydestination = $myhostname, localhost.localdomain, localhost'
do_postconf -e 'home_mailbox=Maildir/'
do_postconf -e 'mailbox_command='
do_postconf -e 'maillog_file=/dev/stdout'
do_postconf -e 'smtpd_sender_restrictions=reject_unlisted_sender,reject_sender_login_mismatch,reject_unknown_sender_domain'
do_postconf -e 'message_size_limit=104857600'

# configure SRS (Sender Rewriting Scheme)
do_postconf -e "sender_canonical_maps = tcp:127.0.0.1:10001"
do_postconf -e "sender_canonical_classes = envelope_sender"
do_postconf -e "recipient_canonical_maps = tcp:127.0.0.1:10002"
do_postconf -e "recipient_canonical_classes = envelope_recipient"

# virtual mailboxes
do_postconf -e 'virtual_mailbox_base=/var/mail/'
do_postconf -e 'virtual_mailbox_domains=proxy:mysql:/etc/postfix/sql/mysql_virtual_domains_maps.cf'
do_postconf -e 'virtual_alias_maps=proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_maps.cf, proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_domain_maps.cf, proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_domain_catchall_maps.cf'
do_postconf -e 'virtual_mailbox_maps=proxy:mysql:/etc/postfix/sql/mysql_virtual_mailbox_maps.cf,proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_domain_mailbox_maps.cf'
do_postconf -e 'smtpd_sender_login_maps=proxy:mysql:/etc/postfix/sql/mysql_virtual_sender_maps.cf,proxy:mysql:/etc/postfix/sql/mysql_virtual_alias_domain_sender_maps.cf'
do_postconf -e 'relay_domains=proxy:mysql:/etc/postfix/sql/mysql_relay_domains.cf'
do_postconf -e 'transport_maps=proxy:mysql:/etc/postfix/sql/mysql_transport_maps.cf'

# Keep these in sync with the infrastructure repository vmail user id and group
do_postconf -e 'virtual_minimum_uid=3000'
do_postconf -e 'virtual_uid_maps=static:3000'
do_postconf -e 'virtual_gid_maps=static:3000'

# Add SPAM control
do_postconf -e 'smtpd_helo_required=yes'
do_postconf -e 'strict_rfc821_envelopes=yes'
do_postconf -e 'disable_vrfy_command=yes'
do_postconf -e 'smtpd_relay_restrictions=permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination'

RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_unauth_pipelining,reject_non_fqdn_sender"
RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_non_fqdn_recipient,reject_unknown_sender_domain"
RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_unknown_recipient_domain"

# Spamhaus SMTP recipient rejections
if [[ -z "${SPAMHAUS_DISABLE:-}" ]]; then
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_rbl_client zen.spamhaus.org=127.0.0.[2..11]"
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_rhsbl_sender dbl.spamhaus.org=127.0.1.[2..99]"
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_rhsbl_helo dbl.spamhaus.org=127.0.1.[2..99]"
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_rhsbl_reverse_client dbl.spamhaus.org=127.0.1.[2..99]"
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}warn_if_reject reject_rbl_client zen.spamhaus.org=127.255.255.[1..255]"
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}reject_rhsbl_sender dbl.spamhaus.org"
fi

# Add spamass milter spec
if [[ -n "${SPAMASS_SOCKET_PATH:-}" ]]; then
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}check_policy_service unix:${SPAMASS_SOCKET_PATH}"
fi


# Add SPF milter spec
if [[ -n "${SPF_ENABLE:-}" ]]; then
  if [[ ! -x "/usr/bin/policyd-spf" ]]; then
    >&2 echo "Error: Could not find executable /usr/bin/policyd-spf, did you install it?"
    exit 1
  fi
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}check_policy_service unix:private/policyd-spf"
  do_postconf -e 'policyd-spf_time_limit=3600'
  if ! grep -q '^policyd-spf' /etc/postfix/master.cf; then
    cat <<EOF >> /etc/postfix/master.cf
policyd-spf  unix  -       n       n       -       0       spawn
    user=policyd-spf argv=/usr/bin/policyd-spf
EOF
  fi
fi


if [[ -n "${SMTPS_ENABLE:-}" ]]; then
  if ! grep -q '^smtps' /etc/postfix/master.cf; then
    if [[ -n "${AUTHORIZED_SMTPD_XCLIENT_HOSTS:-}" ]]; then
      cat <<EOF >> /etc/postfix/master.cf
smtps     inet  n       -       -       -       -       smtpd
  -o smtpd_tls_wrappermode=yes
  -o smtpd_authorized_xclient_hosts=${AUTHORIZED_SMTPD_XCLIENT_HOSTS}
EOF
    else
      cat <<EOF >> /etc/postfix/master.cf
smtps     inet  n       -       -       -       -       smtpd
  -o smtpd_tls_wrappermode=yes
EOF
    fi
  fi
fi

# authentication settings (SASL)
if [[ -n "${DOVECOT_SASL_SOCKET_PATH:-}" ]]; then
  echo "Configuring Dovecot SASL"
  do_postconf -e 'smtpd_sasl_type=dovecot'
  do_postconf -e "smtpd_sasl_path=${DOVECOT_SASL_SOCKET_PATH}"
  do_postconf -e 'smtpd_sasl_auth_enable=yes'
  do_postconf -e 'broken_sasl_auth_clients=yes'
  if [[ -n "${TLS_CERT:-}" && -n "${TLS_KEY:-}" ]]; then
    do_postconf -e 'smtpd_sasl_security_options=noanonymous,noplaintext'
    do_postconf -e 'smtpd_sasl_tls_security_options=noanonymous'
    do_postconf -e 'smtpd_tls_auth_only=yes'
  else
    do_postconf -e 'smtpd_sasl_security_options=noanonymous'
  fi
  RCP_RESTR="permit_mynetworks,permit_sasl_authenticated${RCP_RESTR:+,$RCP_RESTR,}reject_unknown_helo_hostname"

  # add-ons
  do_postconf -e 'smtpd_delay_reject=yes'
  #do_postconf -e 'smtpd_client_restrictions='
  #do_postconf -e 'smtpd_sasl_local_domain='
else
  echo "No Dovecot SASL configured"
fi

# Fix SMTP smuggling according to https://www.postfix.org/smtp-smuggling.html
# Change this if you ever upgrade to a newer postfix as describe on the page above
do_postconf -e 'smtpd_data_restrictions=reject_unauth_pipelining'
do_postconf -e 'smtpd_discard_ehlo_keywords=chunking,silent-discard'

# Add postgrey milter spec
if [[ -n "${POSTGREY_SOCKET_PATH:-}" ]]; then
  RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}check_policy_service unix:${POSTGREY_SOCKET_PATH}"
fi

RCP_RESTR="${RCP_RESTR:+$RCP_RESTR,}permit_auth_destination,reject_unauth_destination,reject"

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
  do_postconf -e 'milter_default_action=accept'
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
create_virtual_sender_maps
create_virtual_alias_domain_sender_maps
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


# Patch the smtp and submission lines to allow xclient from specific hosts
# This is idempotent: only adds the -o line if not already present after the service line
if [[ -n "${AUTHORIZED_SMTPD_XCLIENT_HOSTS:-}" ]]; then
  XCLIENT_OPT="  -o smtpd_authorized_xclient_hosts=${AUTHORIZED_SMTPD_XCLIENT_HOSTS}"
  # smtp line
  if ! grep -q 'smtpd_authorized_xclient_hosts' <(grep -A1 '^smtp\s\+inet' /etc/postfix/master.cf); then
    sed -i "/^smtp\s\+inet/a\\${XCLIENT_OPT}" /etc/postfix/master.cf
  fi
  # submission line
  if ! grep -q 'smtpd_authorized_xclient_hosts' <(grep -A1 '^submission\s\+inet' /etc/postfix/master.cf); then
    sed -i "/^submission\s\+inet/a\\${XCLIENT_OPT}" /etc/postfix/master.cf
  fi
fi

# Fix spool directory ownership (may be wrong if migrating from a separate milters container
# that ran chown -R on the entire spool volume)
postfix set-permissions

# run the postfix instance configuration taken from the /etc/init.d/postfix script
/usr/lib/postfix/configure-instance.sh

# --- Milter initialization (merged from postfix-milters) ---

# Patch rsyslogd to disable kernel message logging
sed 's/^module(load=\"imklog\".*)/#&/' -i.bak /etc/rsyslog.conf
# If /dev/log is already mounted from the host, disable rsyslog's imuxsock listener
# to avoid "Address already in use"
if [[ -S /dev/log ]]; then
  sed -i 's/^module(load="imuxsock")/#&/' /etc/rsyslog.conf
fi

# Validate and log milter socket paths
if [[ -n "${POSTGREY_SOCKET_PATH:-}" ]]; then
  echo "Postgrey socket path set: ${POSTGREY_SOCKET_PATH}"
fi
if [[ -n "${SPAMASS_SOCKET_PATH:-}" ]]; then
  echo "Spamass socket path set: ${SPAMASS_SOCKET_PATH}"
fi
if [[ -n "${DKIM_SOCKET_PATH:-}" ]]; then
  echo "DKIM socket path set: ${DKIM_SOCKET_PATH}"
  if [[ -z "${DKIM_DOMAINS:-}" ]]; then (>&2 echo "Error: env var DKIM_DOMAINS not set" && exit 1); fi
  if [[ -z "${DKIM_SELECTOR:-}" ]]; then (>&2 echo "Error: env var DKIM_SELECTOR not set" && exit 1); fi
  if [[ -z "${DKIM_KEY_PATH:-}" ]]; then (>&2 echo "Error: env var DKIM_KEY_PATH not set" && exit 1); fi

  # Create opendkim.conf from template
  /scripts/create_opendkim_conf.sh
fi

# Patch /etc/opendmarc.conf
if [[ -n "${DMARC_SOCKET_PATH:-}" ]]; then
  echo "DMARC socket path is set: ${DMARC_SOCKET_PATH}"
  if [[ -z "${MAIL_HOSTNAME:-}" ]]; then (>&2 echo "Error: env var MAIL_HOSTNAME not set" && exit 1); fi

  # Configuration taken from https://www.linuxbabe.com/mail-server/opendmarc-postfix-ubuntu
  sed 's@^Socket local:.*@Socket local:/var/spool/postfix/'"${DMARC_SOCKET_PATH}"'@' -i.bak /etc/opendmarc.conf
  if ! grep -q '^AuthservID OpenDMARC' /etc/opendmarc.conf; then
    cat <<EOF >> /etc/opendmarc.conf
AuthservID OpenDMARC
TrustedAuthservIDs ${MAIL_HOSTNAME}
RejectFailures true
IgnoreAuthenticatedClients true
RequiredHeaders    true
SPFSelfValidate true
EOF
  fi
fi

# Ensure the directories for the milter sockets exist
if [[ -n "${POSTGREY_SOCKET_PATH:-}" ]]; then mkdir -p /var/spool/postfix/"${POSTGREY_SOCKET_PATH%/*}"; fi
if [[ -n "${SPAMASS_SOCKET_PATH:-}" ]]; then mkdir -p /var/spool/postfix/"${SPAMASS_SOCKET_PATH%/*}"; fi
if [[ -n "${DKIM_SOCKET_PATH:-}" ]]; then mkdir -p /var/spool/postfix/"${DKIM_SOCKET_PATH%/*}"; fi
if [[ -n "${DMARC_SOCKET_PATH:-}" ]]; then mkdir -p /var/spool/postfix/"${DMARC_SOCKET_PATH%/*}"; fi

# Fix ownership for milter socket directories and SpamAssassin
# Milter processes (syslog user) create unix sockets inside /var/spool/postfix/private/.
# Postfix requires /var/spool/postfix/private to be owned by postfix.
# We set the group to opendkim and make it group-writable so milter processes can
# create sockets there. Both syslog and postfix are added to opendkim group.
usermod -aG opendkim postfix
usermod -aG opendkim syslog
# Collect unique socket parent directories and fix their permissions
declare -A SOCKET_DIRS
for path in "${POSTGREY_SOCKET_PATH:-}" "${SPAMASS_SOCKET_PATH:-}" "${DKIM_SOCKET_PATH:-}" "${DMARC_SOCKET_PATH:-}"; do
  if [[ -n "${path}" ]]; then
    SOCKET_DIRS["/var/spool/postfix/${path%/*}"]=1
  fi
done
for dir in "${!SOCKET_DIRS[@]}"; do
  chown postfix:opendkim "${dir}"
  chmod 775 "${dir}"
done
chown -R debian-spamd:debian-spamd /var/lib/spamass-milter

echo_exec_banner
exec supervisord -c /etc/supervisord.conf
