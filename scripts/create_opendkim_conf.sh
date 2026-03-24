#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

# Script to create opendkim configuration using environment variable expansion

# Files used in script
readonly OPENDKIM_CONF="/etc/opendkim.conf"
readonly SIGNING_TABLE="/etc/opendkim/SigningTable"
readonly KEY_TABLE="/etc/opendkim/KeyTable"

# Clean old files
#rm -rf /etc/opendkim/*

# Create /etc/opendkim.conf
cat <<EOF > "${OPENDKIM_CONF}"
Syslog			yes
SyslogSuccess		yes
#LogWhy			no

# Common signing and verification parameters. In Debian, the "From" header is
# oversigned, because it is often the identity key used by reputation systems
# and thus somewhat security sensitive.
Canonicalization	relaxed/simple
#Mode			sv
#SubDomains		no
OversignHeaders		From

KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable

# Keep in sync with postfix uid
UserID			syslog
UMask			007

Socket			local:/var/spool/postfix/${DKIM_SOCKET_PATH}

PidFile			/run/opendkim/opendkim.pid

# The trust anchor enables DNSSEC. In Debian, the trust anchor file is provided
# by the package dns-root-data.
TrustAnchorFile		/usr/share/dns/root.key
#Nameservers		127.0.0.1

# If enabled, log verification stats here
Statistics              /dev/stdout

# KeyList is a file containing tuples of key information. Requires
# KeyFile to be unset. Each line of the file should be of the format:
#    sender glob:signing domain:signing key file
# Blank lines and lines beginning with # are ignored. Selector will be
# derived from the key's filename.
#KeyList                /etc/dkim-keys.conf
#
# If true, when a signature verification fails and the signature included
# a reporting request ("r=y") and the signing domain advertises a
# reporting address (i.e. ra=user) in a reporting record in the DNS, the
# filter will send a structured report to that address containing details
# needed to reproduce the problem.
# See RFC6651 for a complete description of this mechanism.
SendReports             yes
#
# If enabled, will issue a Sendmail QUARANTINE for any messages that fail
# signature verification, allowing them to be inspected later.
#Quarantine             yes
#
# If enabled, will check for required headers when processing messages.
# At a minimum, that means From: and Date: will be required. Messages not
# containing the required headers will not be signed or verified, but will
# be passed through
RequiredHeaders        yes
EOF

# Clear KeyTable
rm -rf "${KEY_TABLE}"
# Fill KeyTable
for domain in ${DKIM_DOMAINS//,/ }; do
  echo "${DKIM_SELECTOR}._domainkey.${domain} ${domain}:${DKIM_SELECTOR}:${DKIM_KEY_PATH}" >> "${KEY_TABLE}"
done

# Clear SigningTable
rm -rf "${SIGNING_TABLE}"
# Fill SigningTable
for domain in ${DKIM_DOMAINS//,/ }; do
  echo "*@${domain} ${DKIM_SELECTOR}._domainkey.${domain}" >> "${SIGNING_TABLE}"
done
