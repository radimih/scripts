#!/usr/bin/env bash

set -euo pipefail

# Скрипт предполагает запуск от имени пользователя root

# Устанавливаемые apt-пакеты в алфавитном порядке
APT_PACKAGES=(
  console-setup
  curl
  ufw
  unattended-upgrades
)

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

main() {

  check_debian
  install_apt_packages
  configure_router_sysctl
  configure_linux_console
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

install_apt_packages() {

  print_step_msg "Installing apt packages"

  apt-get update

  DEBIAN_FRONTEND=noninteractive apt-get install --yes "${APT_PACKAGES[@]}"
}

configure_router_sysctl() {

  local param
  local key

  print_step_msg "Configuring kernel parameters for routing (${SYSCTL_FILE})"

  if [[ ! -d "${SYSCTL_DIR}" ]]; then
    print_error_msg "... the directory ${SYSCTL_DIR} does not exist, cannot write ${SYSCTL_FILE}"
    return 1
  fi

  for param in "${SYSCTL_PARAMS[@]}"; do
    key="${param%%=*}"
    set_config_param "${SYSCTL_FILE}" "${key}" "${key} = ${param#*=}"
  done

  sysctl --load="${SYSCTL_FILE}"
}

configure_linux_console() {

  local key

  print_step_msg "Configuring the Linux console (${CONSOLE_SETUP_FILE})"

  if [[ ! -f "${CONSOLE_SETUP_FILE}" ]]; then
    print_error_msg "... the file ${CONSOLE_SETUP_FILE} does not exist, install the console-setup package first"
    return 1
  fi

  for key in "${!CONSOLE_SETUP_PARAMS[@]}"; do
    set_config_param "${CONSOLE_SETUP_FILE}" "${key}" "${key}=\"${CONSOLE_SETUP_PARAMS[${key}]}\""
  done

  setupcon
}

set_config_param() {

  local file="$1"
  local key="$2"
  local assignment="$3"

  # Если значение параметра уже установлено
  if grep --silent --no-messages --fixed-strings --line-regexp -- "${assignment}" "${file}"; then
    return 0
  fi

  # Заменить существующий параметр, даже если он закомментирован; если параметра
  # нет — добавить его последней строкой файла
  if grep --silent --no-messages --extended-regexp "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=" "${file}"; then
    sed --in-place --regexp-extended "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=.*|${assignment}|" "${file}"
  else
    echo "${assignment}" >> "${file}"
  fi
}

print_error_msg() {

  echo
  echo -e "${CL_RED}$1${CL_NO}"
  echo
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
