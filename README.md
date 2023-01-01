# Docker Image with Postfix for Postfixadmin

This repository defines a docker image that can be used to build up a mail server with the postfixadmin docker image.

## Credits

* Most ideas and scripts have been taking from [bokysan/docker-postfix](https://github.com/bokysan/docker-postfix).  
* The actual configuration was taken from my [old work](https://www.nesono.com/node/276) on a Postfix mail server.  
* What made it actually work for me was this [page](https://www.postfix.org/SASL_README.html)  

## Requirements

Only MySQL is supported for now.

## Integration

### Docker Compose

Example docker-compose.yaml:
```yaml
  postfix:
    depends_on:
      - mysql_mail
      - mail2-nesono-com
    image: nesono/postfix-for-postfixadmin:2022-12-23.3
    environment:
      SQL_USER_FILE: /run/secrets/mysql_mail_user
      SQL_PASSWORD_FILE: /run/secrets/mysql_mail_password
      SQL_HOST: mysql_mail
      SQL_DB_NAME: mailserver
      TLS_CERT: /etc/postfix/certs/example.crt
      TLS_KEY: /etc/postfix/certs/example.key
      DOVECOT_SASL_SOCKET_PATH: "private/auth"
      DOVECOT_LMTP_PATH: "private/dovecot-lmtp"
    secrets:
      - mysql_mail_password
      - mysql_mail_user
    ports:
      - "25:25"
      - "587:587"
    volumes:
      - mail:/var/mail
      - certs:/etc/postfix/certs
    deploy:
      restart_policy:
        condition: on-failure
```

### SQL Adapters

Use the following environment variables for that:
* `SQL_USER`
* `SQL_PASSWORD_FILE`
* `SQL_HOST`
* `SQL_DB_NAME`

### TLS Configuration

Use the following environment variables for that:
* `TLS_CERT`
* `TLS_KEY`

### Dovecot Services

private/postgrey

The following environment variables control the paths of the unix domain sockets below `/var/spool/postfix`.
* `DOVECOT_SASL_SOCKET_PATH`
* `DOVECOT_LMTP_PATH`
* `SPAMASS_SOCKET_PATH`
* `POSTGREY_SOCKET_PATH`
* `DKIM_SOCKET_PATH`
