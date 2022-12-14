#!/usr/bin/env bash

echo_start_banner() {
  echo "**** Starting Postfix ****"
}

echo_exec_banner() {
  echo "**** Service Setup Done ****"
}

# function to set postfix configuration (taken from bokysan/docker-postfix)
# Two modes:
# 1. Forwarding to postconf -e <key>=<value> - just call it as do_postconf -e <key>=<value>
# 2. Commenting out given key - call it with the option '-#', e.g. do_postconf -# <key>
do_postconf() {
	local has_commented_key
	local has_key
	local key
	if [[ "$1" == "-#" ]]; then
		shift
		key="$1"
		shift
		if grep -q -E "^${key}\s*=" /etc/postfix/main.cf; then
			has_key="1"
		fi
		if grep -q -E "^#\s*${key}\s*=" /etc/postfix/main.cf; then
			has_commented_key="1"
		fi
		if [[ "${has_key}" == "1" ]] && [[ "${has_commented_key}" == "1" ]]; then
			# The key appears in the comment as well as outside the comment.
			# Delete the key which is outside of the comment
			sed -i -e "/^${key}\s*=/ { :a; N; /^\s/ba; N; d }" /etc/postfix/main.cf
		elif [[ "${has_key}" == "1" ]]; then
			# Comment out the key with postconf
			postconf -# "${key}" > /dev/null
		else
			# No key or only commented key, do nothing
			:
		fi
	else
		# Add the line normally
		shift
		postconf -e "$@"
	fi
}

postfix_open_submission_port() {
	# Use 587 (submission)
	sed -i -r -e 's/^#submission/submission/' /etc/postfix/master.cf
}