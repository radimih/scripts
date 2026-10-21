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
      locales \
      openssh-client \
      openssh-server \
      procps \
      qrencode \
      sudo \
      systemd-timesyncd \
      ufw \
      unattended-upgrades \
 && rm -rf /var/lib/apt/lists/*

# Локали для тестов собираются в образе: сценарии подменяют locale-gen заглушкой
# (сборка занимает несколько секунд), а экспортированные скриптом переменные
# должны указывать на существующие локали — иначе bash ругается на setlocale.
# Сценарий, проверяющий саму сборку, убирает заглушку и архив локалей.
RUN localedef --inputfile en_US --charmap UTF-8 en_US.UTF-8 \
 && localedef --inputfile ru_RU --charmap UTF-8 ru_RU.UTF-8

# Копии /etc/default/console-setup (в том виде, в каком его ставит пакет
# console-setup), /etc/os-release (в том виде, в каком его ставит базовый
# образ), /etc/localtime и файла зоны /usr/share/zoneinfo/Asia/Novosibirsk,
# /etc/locale.gen и /etc/locale.conf (в том виде, в каком их ставит пакет
# locales), а также файлов /etc/apt/apt.conf.d/20auto-upgrades и
# /etc/apt/apt.conf.d/50unattended-upgrades (в том виде, в каком их ставит
# пакет unattended-upgrades) и файлов /etc/motd и
# /etc/update-motd.d/10-uname (в том виде, в каком их ставит пакет base-files):
# тесты восстанавливают из них исходное состояние перед каждым сценарием.
RUN mkdir --parents /usr/share/vpn-test \
 && cp /etc/default/console-setup /usr/share/vpn-test/console-setup.pristine \
 && cp /etc/os-release /usr/share/vpn-test/os-release.pristine \
 && cp --no-dereference /etc/localtime /usr/share/vpn-test/localtime.pristine \
 && cp /usr/share/zoneinfo/Asia/Novosibirsk /usr/share/vpn-test/novosibirsk.pristine \
 && cp /etc/locale.gen /usr/share/vpn-test/locale.gen.pristine \
 && cp /etc/locale.conf /usr/share/vpn-test/locale.conf.pristine \
 && cp /etc/apt/apt.conf.d/20auto-upgrades /usr/share/vpn-test/20auto-upgrades.pristine \
 && cp /etc/apt/apt.conf.d/50unattended-upgrades /usr/share/vpn-test/50unattended-upgrades.pristine \
 && cp /etc/motd /usr/share/vpn-test/motd.pristine \
 && cp /etc/update-motd.d/10-uname /usr/share/vpn-test/10-uname.pristine
