# Тестовый образ для amnezia.sh: базовое тестовое окружение Debian 13 плюс
# пакеты, которые ставит сам скрипт (APT_PACKAGES в amnezia.sh). Сборка образа
# заодно проверяет, что все имена пакетов есть в Debian 13.

ARG BASE_IMAGE=scripts-test:debian
FROM ${BASE_IMAGE}

RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      console-setup \
      curl \
      openssh-server \
      ufw \
      unattended-upgrades \
 && rm -rf /var/lib/apt/lists/*

# Копии /etc/default/console-setup (в том виде, в каком его ставит пакет
# console-setup), /etc/os-release (в том виде, в каком его ставит базовый
# образ), /etc/localtime и файла зоны /usr/share/zoneinfo/Asia/Novosibirsk, а
# также файлов /etc/apt/apt.conf.d/20auto-upgrades и
# /etc/apt/apt.conf.d/50unattended-upgrades (в том виде, в каком их ставит
# пакет unattended-upgrades): тесты восстанавливают из них исходное состояние
# перед каждым сценарием.
RUN mkdir --parents /usr/share/amnezia-test \
 && cp /etc/default/console-setup /usr/share/amnezia-test/console-setup.pristine \
 && cp /etc/os-release /usr/share/amnezia-test/os-release.pristine \
 && cp --no-dereference /etc/localtime /usr/share/amnezia-test/localtime.pristine \
 && cp /usr/share/zoneinfo/Asia/Novosibirsk /usr/share/amnezia-test/novosibirsk.pristine \
 && cp /etc/apt/apt.conf.d/20auto-upgrades /usr/share/amnezia-test/20auto-upgrades.pristine \
 && cp /etc/apt/apt.conf.d/50unattended-upgrades /usr/share/amnezia-test/50unattended-upgrades.pristine
