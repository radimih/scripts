# Тестовый образ для vpn.sh: базовое тестовое окружение Debian 13 плюс
# пакеты, которые ставит сам скрипт (APT_PACKAGES в vpn.sh). Сборка образа
# заодно проверяет, что все имена пакетов есть в Debian 13.

ARG BASE_IMAGE=scripts-test:debian
FROM ${BASE_IMAGE}

RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      console-setup \
      curl \
      docker-cli \
      docker-compose \
      docker.io \
      iproute2 \
      openssh-client \
      openssh-server \
      procps \
      qrencode \
      sudo \
      systemd-timesyncd \
      ufw \
      unattended-upgrades \
 && rm -rf /var/lib/apt/lists/*

# Копии /etc/default/console-setup (в том виде, в каком его ставит пакет
# console-setup), /etc/os-release (в том виде, в каком его ставит базовый
# образ), /etc/localtime и файла зоны /usr/share/zoneinfo/Asia/Novosibirsk, а
# также файлов /etc/apt/apt.conf.d/20auto-upgrades и
# /etc/apt/apt.conf.d/50unattended-upgrades (в том виде, в каком их ставит
# пакет unattended-upgrades) и файлов /etc/motd и
# /etc/update-motd.d/10-uname (в том виде, в каком их ставит пакет base-files):
# тесты восстанавливают из них исходное состояние перед каждым сценарием.
RUN mkdir --parents /usr/share/vpn-test \
 && cp /etc/default/console-setup /usr/share/vpn-test/console-setup.pristine \
 && cp /etc/os-release /usr/share/vpn-test/os-release.pristine \
 && cp --no-dereference /etc/localtime /usr/share/vpn-test/localtime.pristine \
 && cp /usr/share/zoneinfo/Asia/Novosibirsk /usr/share/vpn-test/novosibirsk.pristine \
 && cp /etc/apt/apt.conf.d/20auto-upgrades /usr/share/vpn-test/20auto-upgrades.pristine \
 && cp /etc/apt/apt.conf.d/50unattended-upgrades /usr/share/vpn-test/50unattended-upgrades.pristine \
 && cp /etc/motd /usr/share/vpn-test/motd.pristine \
 && cp /etc/update-motd.d/10-uname /usr/share/vpn-test/10-uname.pristine
