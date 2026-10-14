#!/usr/bin/env bash

set -euo pipefail

# Скрипт предполагает запуск от имени пользователя root

APT_CONF_DIR=/etc/apt/apt.conf.d

# Устанавливаемые apt-пакеты в алфавитном порядке
APT_PACKAGES=(
  console-setup
  curl
  openssh-server
  ufw
  unattended-upgrades
)

# Файл настройки автоматического обновления: включение обновлений списка
# пакетов и их автоматической установки
APT_AUTO_UPGRADES_FILE=${APT_CONF_DIR}/20auto-upgrades

# Параметры автоматического обновления в форме <параметр>=<значение>, в порядке
# записи в файл
APT_AUTO_UPGRADES_PARAMS=(
  APT::Periodic::Update-Package-Lists=1
  APT::Periodic::Unattended-Upgrade=1
  APT::Periodic::AutocleanInterval=7
)

# Файл настройки автоматической перезагрузки и очистки после установки
# обновлений
APT_UNATTENDED_UPGRADES_FILE=${APT_CONF_DIR}/50unattended-upgrades

# Параметры автоматической перезагрузки и очистки в форме
# <параметр>=<значение>, в порядке записи в файл: удаление неиспользуемых
# зависимостей и старых ядер, перезагрузка в 05:00 даже при залогиненных
# пользователях
APT_UNATTENDED_UPGRADES_PARAMS=(
  Unattended-Upgrade::Remove-Unused-Kernel-Packages=true
  Unattended-Upgrade::Remove-Unused-Dependencies=true
  Unattended-Upgrade::Automatic-Reboot=true
  Unattended-Upgrade::Automatic-Reboot-Time=05:00
  Unattended-Upgrade::Automatic-Reboot-WithUsers=true
)

CL_BOLD='\033[1m'
CL_GREEN='\033[0;32m'
CL_NO='\033[0m'
CL_RED='\033[0;31m'

CONSOLE_SETUP_FILE=/etc/default/console-setup

# Параметры консоли в форме ассоциированного массива [<параметр>]=<значение>
declare -A CONSOLE_SETUP_PARAMS=(
  [CODESET]=FullCyrSlav
  [FONTFACE]=Terminus
  [FONTSIZE]=8x16
)

OS_RELEASE_FILE=/etc/os-release

# Каталог с дополнительными настройками sshd
SSHD_CONFIG_DIR=/etc/ssh/sshd_config.d

# Файл дополнительных настроек sshd: sshd использует первое полученное значение,
# а каталог ${SSHD_CONFIG_DIR} подключается в начале sshd_config, поэтому имя
# файла начинается с 00 — так наши значения перекрывают настройки из других
# файлов каталога (например, 50-cloud-init.conf)
SSHD_CONFIG_FILE=${SSHD_CONFIG_DIR}/00-hardening.conf

# Параметры sshd в форме <параметр>=<значение>, в алфавитном порядке: вход по
# паролю и вход пользователем root запрещены, разрешён только вход по ключу
SSHD_CONFIG_PARAMS=(
  PasswordAuthentication=no
  PermitRootLogin=no
)

SYSCTL_DIR=/etc/sysctl.d
SYSCTL_FILE=${SYSCTL_DIR}/9999-router.conf

# Параметры ядра для работы роутером в форме <параметр>=<значение>, в порядке
# записи в файл
SYSCTL_PARAMS=(
  net.core.default_qdisc=fq
  net.ipv4.ip_forward=1
  net.ipv4.tcp_congestion_control=bbr
  net.ipv4.tcp_keepalive_probes=1
  net.ipv4.tcp_mtu_probing=1
  net.ipv6.conf.all.disable_ipv6=1
)

# Часовой пояс
TIME_ZONE=Asia/Novosibirsk

# Каталог с базой часовых поясов
TIME_ZONE_DIR=/usr/share/zoneinfo

# Символическая ссылка, задающая часовой пояс системы
TIME_ZONE_FILE=/etc/localtime

main() {

  check_debian
  install_apt_packages
  configure_linux_console
  configure_time_zone
  configure_ssh
  configure_automatic_upgrades
  configure_router_sysctl
}

check_debian() {

  local os_id

  print_step_msg "Checking the operating system"

  if [[ ! -f "${OS_RELEASE_FILE}" ]]; then
    print_error_msg "... the file ${OS_RELEASE_FILE} does not exist, cannot detect the operating system"
    return 1
  fi

  os_id="$(sed --quiet --regexp-extended 's/^ID="?([^"]*)"?$/\1/p' "${OS_RELEASE_FILE}")"

  if [[ "${os_id}" != "debian" ]]; then
    print_error_msg "... the script runs on Debian only, the current system is ${os_id:-unknown}"
    return 1
  fi
}

configure_time_zone() {

  local zone_info

  print_step_msg "Configuring the time zone"

  zone_info="${TIME_ZONE_DIR}/${TIME_ZONE}"

  if [[ ! -f "${zone_info}" ]]; then
    print_error_msg "... the file ${zone_info} does not exist, cannot set the time zone"
    return 1
  fi

  print_info_msg "Setting the time zone to ${CL_BOLD}${TIME_ZONE}${CL_NO} in ${TIME_ZONE_FILE}"
  ln --symbolic --force --no-dereference "${zone_info}" "${TIME_ZONE_FILE}"
}

install_apt_packages() {

  print_step_msg "Installing apt packages"

  apt-get update

  DEBIAN_FRONTEND=noninteractive apt-get install --yes "${APT_PACKAGES[@]}"
}

configure_ssh() {

  local key
  local param

  print_step_msg "Configuring SSH access"

  if [[ ! -d "${SSHD_CONFIG_DIR}" ]]; then
    print_error_msg "... the directory ${SSHD_CONFIG_DIR} does not exist, install the openssh-server package first"
    return 1
  fi

  print_info_msg "Updating ${SSHD_CONFIG_FILE}"
  for param in "${SSHD_CONFIG_PARAMS[@]}"; do
    key="${param%%=*}"
    set_sshd_config_param "${SSHD_CONFIG_FILE}" "${key}" "${key} ${param#*=}"
  done

  systemctl reload ssh
}

configure_automatic_upgrades() {

  local key
  local param

  print_step_msg "Configuring automatic upgrades"

  if [[ ! -d "${APT_CONF_DIR}" ]]; then
    print_error_msg "... the directory ${APT_CONF_DIR} does not exist, cannot configure automatic upgrades"
    return 1
  fi

  print_info_msg "Updating ${APT_AUTO_UPGRADES_FILE}"
  for param in "${APT_AUTO_UPGRADES_PARAMS[@]}"; do
    key="${param%%=*}"
    set_apt_conf_param "${APT_AUTO_UPGRADES_FILE}" "${key}" "${key} \"${param#*=}\";"
  done

  print_info_msg "Updating ${APT_UNATTENDED_UPGRADES_FILE}"
  for param in "${APT_UNATTENDED_UPGRADES_PARAMS[@]}"; do
    key="${param%%=*}"
    set_apt_conf_param "${APT_UNATTENDED_UPGRADES_FILE}" "${key}" "${key} \"${param#*=}\";"
  done
}

configure_router_sysctl() {

  local param
  local key

  print_step_msg "Configuring kernel parameters for routing"

  if [[ ! -d "${SYSCTL_DIR}" ]]; then
    print_error_msg "... the directory ${SYSCTL_DIR} does not exist, cannot write ${SYSCTL_FILE}"
    return 1
  fi

  print_info_msg "Updating ${SYSCTL_FILE}"
  for param in "${SYSCTL_PARAMS[@]}"; do
    key="${param%%=*}"
    set_config_param "${SYSCTL_FILE}" "${key}" "${key} = ${param#*=}"
  done

  sysctl --load="${SYSCTL_FILE}"
}

configure_linux_console() {

  local key

  print_step_msg "Configuring the Linux console"

  if [[ ! -f "${CONSOLE_SETUP_FILE}" ]]; then
    print_error_msg "... the file ${CONSOLE_SETUP_FILE} does not exist, install the console-setup package first"
    return 1
  fi

  print_info_msg "Updating ${CONSOLE_SETUP_FILE}"
  for key in "${!CONSOLE_SETUP_PARAMS[@]}"; do
    set_config_param "${CONSOLE_SETUP_FILE}" "${key}" "${key}=\"${CONSOLE_SETUP_PARAMS[${key}]}\""
  done

  setupcon
}

# Задаёт в файле строку <строка>: если она уже есть — ничего не делает; иначе
# заменяет строку, подходящую под шаблон <шаблон> (в том числе
# закомментированную), или добавляет <строка> последней строкой файла
set_config_line() {

  local file="$1"
  local pattern="$2"
  local line="$3"

  if grep --silent --no-messages --fixed-strings --line-regexp -- "${line}" "${file}"; then
    return 0
  fi

  if grep --silent --no-messages --extended-regexp -- "${pattern}" "${file}"; then
    sed --in-place --regexp-extended "s|${pattern}.*|${line}|" "${file}"
  else
    echo "${line}" >> "${file}"
  fi
}

# Задаёт параметр вида <параметр>=<значение> (файлы sysctl и console-setup)
set_config_param() {

  set_config_line "$1" "^[[:space:]]*#?[[:space:]]*$2[[:space:]]*=" "$3"
}

# Задаёт параметр вида <параметр> "<значение>"; (файлы apt.conf)
set_apt_conf_param() {

  set_config_line "$1" "^[[:space:]]*(//)?[[:space:]]*$2[[:space:]]+" "$3"
}

# Задаёт параметр вида <параметр> <значение> (файл sshd_config)
set_sshd_config_param() {

  set_config_line "$1" "^[[:space:]]*#?[[:space:]]*$2[[:space:]]+" "$3"
}

print_error_msg() {

  echo
  echo -e "${CL_RED}$1${CL_NO}"
  echo
}

print_info_msg() {

  echo -e "$1"
}

print_step_msg() {

  local msg="┤ $1 │"
  local width=90

  local len=${#msg}
  local pad=$((width - len))

  local filler=""
  if (( pad > 0 )); then
    filler="─"
    while (( ${#filler} < pad )); do
      filler+="${filler}"
    done
    filler="${filler:0:${pad}}"
  fi

  printf "\\n${CL_GREEN}%s%s${CL_NO}\\n\\n" "${filler}" "${msg}"
}

main
