# Тестовый образ для amnezia.sh: базовое тестовое окружение Debian 13 плюс
# пакет console-setup, который настраивает скрипт.

ARG BASE_IMAGE=scripts-test:debian
FROM ${BASE_IMAGE}

RUN apt-get update \
 && apt-get install --yes --no-install-recommends console-setup \
 && rm -rf /var/lib/apt/lists/*

# Копии /etc/default/console-setup (в том виде, в каком его ставит пакет
# console-setup) и /etc/os-release (в том виде, в каком его ставит базовый
# образ): тесты восстанавливают из них исходное состояние перед каждым
# сценарием.
RUN mkdir --parents /usr/share/amnezia-test \
 && cp /etc/default/console-setup /usr/share/amnezia-test/console-setup.pristine \
 && cp /etc/os-release /usr/share/amnezia-test/os-release.pristine
