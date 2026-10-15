#!/usr/bin/env bash

set -euo pipefail

APT_CONF_DIR=/etc/apt/apt.conf.d

# Устанавливаемые apt-пакеты в алфавитном порядке
APT_PACKAGES=(
  console-setup
  curl
  docker-cli
  docker-compose
  docker.io
  iproute2
  openssh-client
  openssh-server
  procps
  qrencode
  sudo
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
CL_CLEAR='\033[H\033[2J'
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

# Минимальная поддерживаемая версия Debian
DEBIAN_MIN_VERSION=13

# Каталог со скриптами, которые pam_motd выполняет при каждом входе
MOTD_DIR=/etc/update-motd.d

# Скрипт формирования сообщения дня: показывает основные характеристики хоста,
# текущее потребление ресурсов и время работы
MOTD_FILE=${MOTD_DIR}/00-motd

# Скрипт пакета base-files, выводящий uname: дублирует сведения о ядре, поэтому
# удаляется
MOTD_UNAME_FILE=${MOTD_DIR}/10-uname

# Статическое сообщение дня: Debian показывает его вместе с динамическим,
# поэтому файл очищается — иначе вместо краткой сводки выводится стандартный
# текст base-files
MOTD_STATIC_FILE=/etc/motd

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

# Каталог с дополнительными настройками sudo
SUDOERS_DIR=/etc/sudoers.d

# Файл дополнительных настроек sudo: полные права без пароля для суперпользователя
SUDOERS_FILE=${SUDOERS_DIR}/00-superuser

# Оболочка суперпользователя
SUPERUSER_SHELL=/bin/bash

# Имя файла SSH-ключа суперпользователя в каталоге ~/.ssh
SUPERUSER_SSH_KEY_NAME=id_ed25519

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

# Каталог с настройками брандмауэра ufw
UFW_DIR=/etc/ufw

main() {

  check_debian
  check_root
  install_apt_packages
  configure_linux_console
  configure_time_zone
  configure_motd
  configure_automatic_upgrades
  configure_router_sysctl
  configure_ssh
  configure_firewall
  configure_docker
  configure_superuser
}

check_debian() {

  local os_id
  local os_version

  print_step_msg "Checking the operating system"

  if [[ ! -f "${OS_RELEASE_FILE}" ]]; then
    print_error_msg "... the file ${OS_RELEASE_FILE} does not exist, cannot detect the operating system"
    return 1
  fi

  os_id="$(os_release_field "${OS_RELEASE_FILE}" ID)"

  if [[ "${os_id}" != "debian" ]]; then
    print_error_msg "... the script runs on Debian only, the current system is ${os_id:-unknown}"
    return 1
  fi

  # В Debian testing и sid поля VERSION_ID нет: это заведомо версии новее
  # минимальной, поэтому проверка версии пропускается
  os_version="$(os_release_field "${OS_RELEASE_FILE}" VERSION_ID)"

  if [[ -n "${os_version}" && "${os_version%%.*}" -lt "${DEBIAN_MIN_VERSION}" ]]; then
    print_error_msg "... the script requires Debian ${CL_BOLD}${DEBIAN_MIN_VERSION}${CL_NO} or newer, the current version is ${os_version}"
    return 1
  fi
}

check_root() {

  print_step_msg "Checking root privileges"

  if (( EUID != 0 )); then
    print_error_msg "... the script must be run as root, the current user is $(id --user --name)"
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

configure_motd() {

  print_step_msg "Configuring the message of the day"

  if [[ ! -d "${MOTD_DIR}" ]]; then
    print_error_msg "... the directory ${MOTD_DIR} does not exist, install the base-files package first"
    return 1
  fi

  print_info_msg "Removing ${MOTD_UNAME_FILE} that duplicates the kernel information"
  rm --force -- "${MOTD_UNAME_FILE}"

  print_info_msg "Updating ${MOTD_FILE}"
  write_motd_script "${MOTD_FILE}"

  print_info_msg "Clearing ${MOTD_STATIC_FILE} to show only the summary"
  : > "${MOTD_STATIC_FILE}"
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

configure_firewall() {

  print_step_msg "Configuring the firewall"

  if [[ ! -d "${UFW_DIR}" ]]; then
    print_error_msg "... the directory ${UFW_DIR} does not exist, install the ufw package first"
    return 1
  fi

  # Перенаправляемые (routed) соединения — транзитный трафик клиентов VPN.
  print_info_msg "Denying incoming connections except ssh and allowing outgoing and routed connections"
  ufw default deny incoming
  ufw default allow outgoing
  ufw default allow routed
  ufw allow ssh

  print_info_msg "Enabling the firewall"
  ufw --force enable
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

configure_docker() {

  print_step_msg "Configuring Docker"

  print_info_msg "Enabling and starting the Docker service"
  systemctl enable --now docker
}

configure_superuser() {

  local home_dir
  local key_dir
  local key_file

  print_step_msg "Configuring the superuser"

  if [[ ! -d "${SUDOERS_DIR}" ]]; then
    print_error_msg "... the directory ${SUDOERS_DIR} does not exist, install the sudo package first"
    return 1
  fi

  ask_superuser_name

  if user_exists "${SUPERUSER_NAME}"; then
    print_info_msg "The user ${CL_BOLD}${SUPERUSER_NAME}${CL_NO} already exists"
  else
    print_info_msg "Creating the user ${CL_BOLD}${SUPERUSER_NAME}${CL_NO}"
    useradd --create-home --shell "${SUPERUSER_SHELL}" "${SUPERUSER_NAME}"
  fi

  print_info_msg "Granting full rights without a password in ${SUDOERS_FILE}"
  printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "${SUPERUSER_NAME}" > "${SUDOERS_FILE}"
  chmod 0440 "${SUDOERS_FILE}"

  home_dir="$(user_home_dir "${SUPERUSER_NAME}")"
  key_dir="${home_dir}/.ssh"
  key_file="${key_dir}/${SUPERUSER_SSH_KEY_NAME}"

  ensure_superuser_ssh_key "${key_dir}" "${key_file}"
  authorize_superuser_ssh_key "${key_dir}" "${key_file}.pub"
  show_superuser_ssh_key "${key_file}"
}

# Значение поля <имя> из файла os-release без кавычек
os_release_field() {

  sed --quiet --regexp-extended "s/^$2=\"?([^\"]*)\"?\$/\1/p" "$1"
}

# Спрашивает имя суперпользователя, пока не введено допустимое, и записывает его в
# SUPERUSER_NAME; кончается неудачей, если ввод закончился (например, скрипт
# запущен без терминала)
ask_superuser_name() {

  local name

  while true; do
    if ! read -r -p "Enter the superuser name: " name; then
      print_error_msg "... no user name was entered"
      return 1
    fi

    if is_valid_superuser_name "${name}"; then
      SUPERUSER_NAME="${name}"
      return 0
    fi

    print_info_msg "... the user name ${CL_BOLD}${name}${CL_NO} is invalid: use up to 32 lowercase latin letters, digits, underscores and hyphens, starting with a letter"
  done
}

# Проверяет, что имя годится для useradd: до 32 символов, начинается со строчной
# латинской буквы, дальше идут строчные латинские буквы, цифры, подчёркивания и
# дефисы (NAME_REGEX из /etc/adduser.conf)
is_valid_superuser_name() {

  [[ ${#1} -le 32 && "$1" =~ ^[a-z][a-z0-9_-]*$ ]]
}

# Проверяет, что пользователь с таким именем есть в базе пользователей
user_exists() {

  id --user "$1" >/dev/null 2>&1
}

# Домашний каталог пользователя
user_home_dir() {

  getent passwd "$1" | cut --delimiter=: --fields=6
}

# Генерирует ключ ed25519 без пароля, если у суперпользователя ещё нет ключа
ensure_superuser_ssh_key() {

  local key_dir="$1"
  local key_file="$2"

  if [[ -f "${key_file}" ]]; then
    print_info_msg "The user ${CL_BOLD}${SUPERUSER_NAME}${CL_NO} already has the SSH key ${key_file}, keeping it"
    return 0
  fi

  print_info_msg "Generating an ed25519 SSH key without a passphrase in ${key_file}"
  install --directory --mode 0700 --owner "${SUPERUSER_NAME}" --group "${SUPERUSER_NAME}" "${key_dir}"
  ssh-keygen -t ed25519 -N '' -C "${SUPERUSER_NAME}@$(hostname)" -f "${key_file}" -q
  chown "${SUPERUSER_NAME}:${SUPERUSER_NAME}" "${key_file}" "${key_file}.pub"
}

# Разрешает вход суперпользователю по его ключу, добавляя публичный ключ в
# authorized_keys (без дубликатов)
authorize_superuser_ssh_key() {

  local key_dir="$1"
  local pub_key_file="$2"
  local authorized_keys_file="${key_dir}/authorized_keys"
  local pub_key

  if [[ ! -f "${pub_key_file}" ]]; then
    print_error_msg "... the file ${pub_key_file} does not exist, cannot authorize the SSH key"
    return 1
  fi

  pub_key="$(< "${pub_key_file}")"

  if grep --silent --no-messages --fixed-strings --line-regexp -- "${pub_key}" \
      "${authorized_keys_file}"; then
    print_info_msg "The key is already authorized in ${authorized_keys_file}"
  else
    print_info_msg "Authorizing the key in ${authorized_keys_file}"
    echo "${pub_key}" >> "${authorized_keys_file}"
  fi

  chmod 0600 "${authorized_keys_file}"
  chown "${SUPERUSER_NAME}:${SUPERUSER_NAME}" "${authorized_keys_file}"
}

# Очищает экран и выводит подпись User name: с именем суперпользователя,
# выделенным жирным, заголовок SSH private key: и QR-код его приватного ключа с
# полем в два символа
show_superuser_ssh_key() {

  printf "${CL_CLEAR}User name: ${CL_BOLD}%s${CL_NO}\\n" "${SUPERUSER_NAME}"
  printf 'SSH private key:\n'
  qrencode -t UTF8 --margin=2 < "$1"
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

# Записывает в файл <файл> скрипт формирования сообщения дня
write_motd_script() {

  local file="$1"

  cat > "${file}" <<'MOTD'
#!/usr/bin/env bash

# Сообщение дня: основные характеристики хоста, текущее потребление ресурсов и
# время работы. Скрипт выполняет pam_motd при каждом входе, поэтому значения в
# нём всегда свежие. Используются утилиты ip, free, uptime и df.

# Разбор вывода утилит опирается на англоязычные подписи
export LC_ALL=C

# Подписи полей выделяются жирным
BOLD=$'\033[1m'
RESET=$'\033[0m'

# Название операционной системы
os_name() {
  sed --quiet --regexp-extended 's/^PRETTY_NAME="(.*)"$/\1/p' /etc/os-release
}

# Основной IP-адрес: адрес, через который хост выходит в сеть
ip_address() {
  ip route get 1.1.1.1 | awk '{ for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1) }'
}

# Время работы
uptime_text() {
  uptime --pretty | sed --regexp-extended 's/^up //'
}

# Средняя загрузка за 1, 5 и 15 минут
load_text() {
  uptime | sed --regexp-extended 's/.*load average: //'
}

# Потребление памяти: <использовано> из <всего> и доля в процентах
memory_usage() {
  free --kibi | awk '/^Mem:/ { printf "%.1f GiB / %.1f GiB (%d%%)", $3 / 1048576, $2 / 1048576, $3 * 100 / $2 }'
}

# Потребление диска: <использовано> из <всего> и доля в процентах
disk_usage() {
  df --portability / | awk 'NR == 2 { printf "%.1f GiB / %.1f GiB (%s)", $3 / 1048576, $2 / 1048576, $5 }'
}

# Наибольшая длина среди аргументов
max_length() {
  local length=0
  local value

  for value in "$@"; do
    if (( ${#value} > length )); then
      length=${#value}
    fi
  done

  printf '%d' "${length}"
}

# Строка таблицы: <подпись> и <значение> левого столбца, затем правого
row() {
  printf '%s%-*s%s  %-*s  %s%-*s%s  %s\n' \
    "${BOLD}" "${LABEL_WIDTH}" "$1" "${RESET}" "${VALUE_WIDTH}" "$2" \
    "${BOLD}" "${LABEL_WIDTH}" "$3" "${RESET}" "$4"
}

left_labels=(OS Kernel Host IP)
left_values=("$(os_name)" "$(uname --kernel-release)" "$(hostname)" "$(ip_address)")

right_labels=(Uptime Load Memory Disk)
right_values=(
  "$(uptime_text)"
  "$(load_text) ($(nproc) cores)"
  "$(memory_usage)"
  "$(disk_usage)"
)

LABEL_WIDTH="$(max_length "${left_labels[@]}" "${right_labels[@]}")"
VALUE_WIDTH="$(max_length "${left_values[@]}")"

for (( index = 0; index < ${#left_labels[@]}; index++ )); do
  row "${left_labels[index]}" "${left_values[index]}" "${right_labels[index]}" "${right_values[index]}"
done
MOTD
  chmod 0755 "${file}"
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
