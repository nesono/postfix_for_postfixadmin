#!/usr/bin/env bash

# make sure that all env variables are set
if [[ -z "${SQL_USER_FILE:-}" ]]; then (>&2 echo "Error: env var SQL_USER_FILE not set" && exit 1); fi
if [[ -z "${SQL_PASSWORD_FILE:-}" ]]; then (>&2 echo "Error: env var SQL_PASSWORD_FILE not set" && exit 1); fi
if [[ -z "${SQL_HOST:-}" ]]; then (>&2 echo "Error: env var SQL_HOST not set" && exit 1); fi
if [[ -z "${SQL_DB_NAME:-}" ]]; then (>&2 echo "Error: env var SQL_DB_NAME not set" && exit 1); fi

SQL_PASSWORD=$(head -1 $SQL_PASSWORD_FILE)
SQL_USER=$(head -1 $SQL_USER_FILE)

mkdir -p /etc/postfix/sql/

create_virtual_alias_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_alias_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query = SELECT goto FROM alias WHERE address='%s' AND active = '1'
#expansion_limit = 100
EOF
}

create_virtual_alias_domain_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_alias_domain_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query = SELECT goto FROM alias,alias_domain WHERE alias_domain.alias_domain = '%d' and alias.address = CONCAT('%u', '@', alias_domain.target_domain) AND alias.active='1' AND alias_domain.active='1'
EOF
}

create_virtual_alias_domain_catchall_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_alias_domain_catchall_maps.cf
# handles catch-all settings of target-domain
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query  = SELECT goto FROM alias,alias_domain WHERE alias_domain.alias_domain = '%d' and alias.address = CONCAT('@', alias_domain.target_domain) AND alias.active='1' AND alias_domain.active='1'
EOF
}

create_virtual_domains_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_domains_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query          = SELECT domain FROM domain WHERE domain='%s' AND active = '1'
#query          = SELECT domain FROM domain WHERE domain='%s'
#optional query to use when relaying for backup MX
#query           = SELECT domain FROM domain WHERE domain='%s' AND backupmx = '0' AND active = '1'
#optional query to use for transport map support
#query           = SELECT domain FROM domain WHERE domain='%s' AND active = '1' AND NOT (transport LIKE 'smtp%%' OR transport LIKE 'relay%%')
#expansion_limit = 100
EOF
}

create_virtual_mailbox_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_mailbox_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query           = SELECT maildir FROM mailbox WHERE username='%s' AND active = '1'
#expansion_limit = 100
EOF
}

create_virtual_alias_domain_mailbox_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_alias_domain_mailbox_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query = SELECT maildir FROM mailbox,alias_domain WHERE alias_domain.alias_domain = '%d' and mailbox.username = CONCAT('%u', '@', alias_domain.target_domain) AND mailbox.active='1' AND alias_domain.active='1'
EOF
}

# Adding (custom) to be able use smtpd_sender_login_maps in Postfix
create_virtual_sender_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_sender_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query           = SELECT username FROM mailbox WHERE username='%s' AND active = '1'
#expansion_limit = 100
EOF
}

# Adding (custom) to be able use smtpd_sender_login_maps in Postfix
create_virtual_alias_domain_sender_maps() {
  cat << EOF > /etc/postfix/sql/mysql_virtual_alias_domain_sender_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query = SELECT goto FROM alias WHERE alias.address = '%s'
EOF
}

create_relay_domains() {
  cat << EOF > /etc/postfix/sql/mysql_relay_domains.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query = SELECT domain FROM domain WHERE domain='%s' AND active = '1' AND (transport LIKE 'smtp%%' OR transport LIKE 'relay%%')
EOF
}

create_transport_maps() {
  cat << EOF > /etc/postfix/sql/mysql_transport_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
#query = SELECT transport FROM domain WHERE domain='%s' AND active = '1' AND transport != 'virtual'
# Enforce virtual transport (catches internal virtual domains and avoid mails being lost in other transport maps)
query = SELECT REPLACE(transport, 'virtual', ':') AS transport FROM domain WHERE domain='%s' AND active = '1'
EOF
}

create_virtual_mailbox_limit_maps() {
 cat << EOF > /etc/postfix/sql/mysql_virtual_mailbox_limit_maps.cf
user = $SQL_USER
password = $SQL_PASSWORD
hosts = $SQL_HOST
dbname = $SQL_DB_NAME
query = SELECT quota FROM mailbox WHERE username='%s' AND active = '1'
EOF
}