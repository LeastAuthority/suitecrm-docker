# SuiteCRM Docker

This repository is largely inspired from https://github.com/guercheLE/SuiteCRM but contains the files required to build a docker image based on [SuiteCRM v7](https://github.com/SuiteCRM/SuiteCRM) (instead of [v8 - a.k.a. Core](https://github.com/SuiteCRM/SuiteCRM-Core)), while only supporting `linux/amd64` (to start with).

The resulting image is meant to be deployed as a drop-in replacement for the one once provided by [Bitnami](https://community.broadcom.com/tanzu/blogs/beltran-rueda-borrego/2025/08/18/how-to-prepare-for-the-bitnami-changes-coming-soon).

## Prerequisites

To build and use this image, you need the following:

- Docker (engine or an equivallent):
  - `docker` CLI tool (tested with v29)
  - `docker compose` command  or `docker-compose` CLI plugin (tested with v5.4)
- At least 1GB of available vRAM, 2 vCPU and 5GB of free disk space

## Configuration

The environment variables described in the `docker-compose.yml` can be customized in `.env`.

For instance:

```
DB_NAME=my_suitecrm
DB_USER=my_suitecrm
DB_PASSWORD=suitecrm123
SUITECRM_HTTP_PORT=80
```

## Usage

Here are the most useful commands:

* `docker compose build`: build the image for the first time or following changes
  - use `docker-compose` for older versions
  - append `suitecrm` to only (re-)build this image (if there are more)
* `docker compose up`: start the application and its depend services 
  - append `-d` to send in the background
  - append `--compatibility` after `compose` to limit resources (e.g. memory)
  - append `--env-file <your_env>` after `compose` to load variables from elsewhere than `.env`
  - append `-f docker-compose.yml -f .docker-compose.yml` after `compose` to overwrite (e.g. volumes)
* `docker exec -it $(docker ps -q -l -f "name=.+[-_]suitecrm[-_].+") bash`: enter an interactive shell inside the container
  - replace `suitecrm` with `mariadb` to explore the database
