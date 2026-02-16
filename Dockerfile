FROM ubuntu:24.04
LABEL maintainer="Jochen Issing <c.333+github@nesono.com> (@jochenissing)"

RUN export DEBIAN_FRONTEND=noninteractive && apt-get update &&  \
    apt-get install -y --no-install-recommends  \
    bash  \
    postfix  \
    postfix-mysql  \
    postfix-policyd-spf-python \
	postsrsd \
    supervisor  \
    netcat-traditional  \
    && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 3000 vmail && \
    useradd -u 3000 -g 3000 vmail -d /srv/vmail && \
    passwd -l vmail && \
    mkdir /srv/mail && \
    chown vmail:vmail /srv/mail
# Beware that the vmail user has a dependency to the infrastructure repo
# if you change the id information here, you will have to adapt the
# infrastructure repo, too
# If you change the uid and/or gid above make sure you replace all occurences of it in this repo and in the infrastructure repo
# Also run something like the following command to change all existing files:
# chown <uid>:<gid> -R /svc/volumes/mail

EXPOSE 587
EXPOSE 465
EXPOSE 25

VOLUME [ "/var/mail", "/var/spool/postfix", "/etc/postfix", "/etc/opendkim/keys" ]

COPY scripts/* /scripts/
COPY configs/* /etc/
RUN chmod +x /scripts/*

CMD [ "/bin/bash", "-c", "/scripts/run.sh" ]
