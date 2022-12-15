# Docker Image with Postfix for Postfixadmin

This repository defines a docker image that can be used to build up a mail server with the postfixadmin docker image.

## Credits

Most ideas and scripts have been taking from [bokysan/docker-postfix](https://github.com/bokysan/docker-postfix).
The actual configuration was taken from my [old work](https://www.nesono.com/node/276) on a Postfix mail server.

## Requirements

Only MySQL is supported for now.

## Integration

### Docker Compose

Example docker-compose.yaml:
```
```

### SQL Adapters

Use the following environment variables for that:
* `SQL_USER`
* `SQL_PASSWORD_FILE`
* `SQL_HOST`
* `SQL_DB_NAME`


(See above note re Concat + PostgreSQL)

### For quota support
