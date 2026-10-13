# Базовый образ тестового окружения: Debian 13 (trixie) — та же среда, что и на
# целевом сервере, плюс инструменты, общие для любых тестов.
#
# Образы конкретных скриптов наследуются от него (см. amnezia.Dockerfile) и
# добавляют только те пакеты, которые нужны этому скрипту.

FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      bats \
      shellcheck \
 && rm -rf /var/lib/apt/lists/*
