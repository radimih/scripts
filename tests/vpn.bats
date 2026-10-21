#!/usr/bin/env bats

# Тесты для vpn.sh.
#
# Запускаются от имени root внутри контейнера Debian 13, в котором установлены
# пакеты console-setup и openssh-server (см. vpn.Dockerfile и run-tests.sh):
# скрипт читает /etc/os-release, правит реальный /etc/default/console-setup,
# пишет drop-in файл журнала systemd, вызывает setupcon и пишет настройки sshd
# в /etc/ssh/sshd_config.d.
#
# Проверяется:
#
# - на системе, отличной от Debian, скрипт завершается с ошибкой, не трогая
#   настройки консоли и часовой пояс;
# - то же самое, если ID системы не определён или нет /etc/os-release;
# - то же самое, если версия Debian ниже минимальной поддерживаемой (13); в
#   Debian testing и sid поля VERSION_ID нет, поэтому там версия не проверяется;
# - то же самое, если скрипт запущен не от имени root;
# - часовой пояс задаётся символической ссылкой /etc/localtime на файл зоны
#   /usr/share/zoneinfo/Asia/Novosibirsk, а в сообщении шага значение часового
#   пояса выделено жирным;
# - после задания часового пояса синхронизация времени включается принудительно
#   вызовом timedatectl set-ntp true;
# - повторный запуск ссылку не меняет (идемпотентность);
# - при отсутствии файла зоны скрипт завершается с ошибкой и внятным сообщением,
#   не меняя /etc/localtime и не включая синхронизацию времени;
# - шаг настройки времени идёт до настройки автоматического обновления,
#   поэтому уже выполнен, когда тот завершается ошибкой;
# - сообщение дня собирается скриптом /etc/update-motd.d/00-motd: его выполняет
#   pam_motd при каждом входе, поэтому значения всегда свежие. Скрипт выводит две
#   колонки — слева характеристики хоста (система, ядро, имя хоста, основной
#   IP-адрес), справа потребление ресурсов и время работы (нагрузка, память,
#   диск) — с подписями, выделенными жирным (без цвета); скрипт использует
#   утилиты ip, free, uptime и df из пакетов iproute2 и procps; сводка окружена
#   пустыми строками;
# - статическое /etc/motd очищается, а скрипт base-files
#   /etc/update-motd.d/10-uname удаляется: иначе вместе с краткой сводкой
#   выводится стандартный текст и строка uname;
# - повторный запуск не меняет ни скрипт, ни /etc/motd (идемпотентность);
# - при отсутствии каталога /etc/update-motd.d скрипт завершается с ошибкой и
#   внятным сообщением (шаг идёт после настройки часового пояса);
# - скрипт сообщения дня проходит shellcheck;
# - журнал systemd настраивается drop-in файлом
#   /etc/systemd/journald.conf.d/99-storage.conf: в нём секция [Journal] с
#   параметрами Storage=persistent и SystemMaxUse=128M, а файл настройки пакета
#   /etc/systemd/journald.conf остаётся нетронутым; настройки видны в
#   эффективной конфигурации (systemd-analyze cat-config); повторный запуск
#   файл не меняет;
# - журнал применяется перезапуском systemd-journald;
# - настройки sshd записываются в файл ${SSHD_CONFIG_FILE}: вход по паролю и вход
#   пользователем root запрещены, разрешён только вход по ключу;
# - файл дополнительных настроек перекрывает настройки из других файлов каталога
#   (например, 50-cloud-init.conf) — это проверяется по эффективной конфигурации
#   sshd;
# - повторный запуск файл настроек sshd не меняет (идемпотентность);
# - настройки применяются перезагрузкой sshd;
# - при отсутствии каталога /etc/ssh/sshd_config.d скрипт завершается с ошибкой
#   и внятным сообщением (шаг идёт после настройки параметров ядра);
# - брандмауэр настраивается командами ufw: входящие соединения запрещены по
#   умолчанию, разрешён только ssh, исходящие разрешены; перенаправляемые
#   (транзитные, например трафик клиентов VPN) разрешены; ssh разрешается до
#   включения брандмауэра, а включение идёт без вопроса (--force);
# - повторный запуск применяет те же правила;
# - при отсутствии каталога /etc/ufw скрипт завершается с ошибкой и внятным
#   сообщением, не настраивая брандмауэр (шаг идёт после настройки SSH);
# - параметры CODESET, FONTFACE и FONTSIZE получают нужные значения;
# - закомментированные параметры заменяются на месте, без дубликатов;
# - отсутствующие параметры добавляются в конец файла;
# - повторный запуск не меняет файл (идемпотентность);
# - при отсутствии /etc/default/console-setup скрипт завершается с ошибкой
#   и внятным сообщением;
# - в /etc/locale.gen раскомментируются строки локалей en_US.UTF-8 и ru_RU.UTF-8,
#   а остальные строки файла не меняются; локали собираются вызовом locale-gen;
# - в /etc/locale.conf записываются LANG=en_US.UTF-8 (локаль по умолчанию) и
#   русские форматы для LC_ADDRESS, LC_IDENTIFICATION, LC_MEASUREMENT,
#   LC_MONETARY, LC_NAME, LC_NUMERIC, LC_PAPER, LC_TELEPHONE и LC_TIME; у
#   LC_CTYPE, LC_COLLATE и LC_MESSAGES своих строк нет, поэтому они берут значение
#   из LANG;
# - настройки, которые уже есть с другим значением, заменяются на месте; повторный
#   запуск файлы не меняет (идемпотентность);
# - локаль применяется и в текущей сессии: переменные экспортируются, а LC_ALL
#   снимается, иначе он перекрыл бы остальные;
# - настройки из /etc/locale.conf дают русские форматы при английских
#   сообщениях;
# - при отсутствии /etc/locale.gen скрипт завершается с ошибкой и внятным
#   сообщением, не трогая /etc/locale.conf;
# - параметры ядра из SYSCTL_PARAMS записываются в /etc/sysctl.d/9999-router.conf,
#   включая kernel.printk с console_loglevel = 4 (warning): сообщения ufw
#   "[UFW BLOCK] ..." с этим уровнем больше не выводятся в консоль tty и остаются
#   в журнале; нужные строки заменяются на месте, остальное содержимое файла
#   не меняется, повторный запуск файл не меняет;
# - параметры ядра применяются вызовом sysctl --load с этим файлом;
# - при отсутствии каталога /etc/sysctl.d скрипт завершается с ошибкой
#   и внятным сообщением;
# - параметры автоматического обновления записываются в
#   /etc/apt/apt.conf.d/20auto-upgrades, параметры автоматической перезагрузки и
#   очистки — в /etc/apt/apt.conf.d/50unattended-upgrades: удаляются неиспользуемые
#   зависимости и старые ядра, перезагрузка разрешена в 05:00 даже при
#   залогиненных пользователях, старые пакеты из кеша удаляются раз в неделю,
#   закомментированные строки заменяются на месте, повторный запуск файлы не
#   меняет;
# - перед записью каждого файла скрипт сообщает, какой файл обновляет;
# - при отсутствии каталога /etc/apt/apt.conf.d скрипт завершается с ошибкой
#   и внятным сообщением;
# - перед установкой пакетов обновляется база пакетов, а сами пакеты ставятся
#   в алфавитном порядке, включая docker.io, docker-cli, docker-compose и
#   systemd-timesyncd;
# - список пакетов в тестовом образе совпадает с APT_PACKAGES в скрипте;
# - служба Docker включается и запускается последним шагом
#   (systemctl enable --now docker), поэтому установленные Docker и Docker
#   Compose готовы к работе;
# - скрипт вызывает setupcon;
# - перед настройкой скрипт сообщает, что будет добавлен новый суперпользователь
#   или существующий обычный пользователь станет суперпользователем;
# - скрипт спрашивает имя суперпользователя, пока не введено допустимое:
#   недопустимое имя отвергается с внятным сообщением, а при отсутствии ввода
#   скрипт завершается с ошибкой;
# - имя, занятое системным пользователем (UID вне диапазона
#   REGULAR_USER_UID_MIN..REGULAR_USER_UID_MAX), отвергается с внятным сообщением
#   и спрашивается другое: такой учётной записи не выдают ни прав sudo, ни
#   SSH-ключа (иначе, например, имя root или nobody открыло бы полный доступ к
#   серверу);
# - перед вводом имени выводится список обычных пользователей (имена выделены
#   жирным), чтобы не ошибиться при повторном запуске для уже созданного
#   суперпользователя;
# - пользователь создаётся с домашним каталогом и оболочкой bash, если его ещё
#   нет, и не пересоздаётся, если он есть;
# - пользователь добавляется в группу администраторов sudo: членство в группе
#   проверяют программы, которые в sudoers не смотрят;
# - суперпользователю выдаются полные права без пароля (файл
#   /etc/sudoers.d/00-superuser), что проверяется запуском sudo без пароля;
# - если у суперпользователя нет SSH-ключа, генерируется ключ ed25519 без пароля
#   с правами 0600 и владельцем-пользователем; существующий ключ сохраняется;
# - публичный ключ суперпользователя добавляется в ~/.ssh/authorized_keys (без
#   дубликатов) с правами 0600, поэтому ключом можно войти по SSH;
# - при отсутствии каталога /etc/sudoers.d скрипт завершается с ошибкой и внятным
#   сообщением, не создавая пользователя (шаг идёт последним);
# - в конце экран очищается и выводятся подпись User name: с именем
#   суперпользователя, заголовок SSH private key: и QR-код приватного ключа с
#   полем в два символа (qrencode -t UTF8 --margin=2);
# - shellcheck не находит замечаний.

SCRIPT_UNDER_TEST="${BATS_TEST_DIRNAME}/../vpn.sh"
APT_CONF_DIR="/etc/apt/apt.conf.d"
APT_AUTO_UPGRADES_FILE="${APT_CONF_DIR}/20auto-upgrades"
APT_UNATTENDED_UPGRADES_FILE="${APT_CONF_DIR}/50unattended-upgrades"
CONSOLE_SETUP_FILE="/etc/default/console-setup"
JOURNALD_CONFIG_DIR="/etc/systemd/journald.conf.d"
JOURNALD_CONFIG_FILE="${JOURNALD_CONFIG_DIR}/99-storage.conf"
JOURNALD_FILE="/etc/systemd/journald.conf"
LOCALE_CONF_FILE="/etc/locale.conf"
LOCALE_GEN_FILE="/etc/locale.gen"
LOCALE_DEFAULT="en_US.UTF-8"
LOCALE_NAMES=("en_US.UTF-8" "ru_RU.UTF-8")
LOCALE_PARAMS=(
  LC_ADDRESS=ru_RU.UTF-8
  LC_IDENTIFICATION=ru_RU.UTF-8
  LC_MEASUREMENT=ru_RU.UTF-8
  LC_MONETARY=ru_RU.UTF-8
  LC_NAME=ru_RU.UTF-8
  LC_NUMERIC=ru_RU.UTF-8
  LC_PAPER=ru_RU.UTF-8
  LC_TELEPHONE=ru_RU.UTF-8
  LC_TIME=ru_RU.UTF-8
)
MOTD_DIR="/etc/update-motd.d"
MOTD_FILE="${MOTD_DIR}/00-motd"
MOTD_STATIC_FILE="/etc/motd"
MOTD_UNAME_FILE="${MOTD_DIR}/10-uname"
OS_RELEASE_FILE="/etc/os-release"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_CONFIG_FILE="${SSHD_CONFIG_DIR}/00-hardening.conf"
SYSCTL_DIR="/etc/sysctl.d"
SYSCTL_FILE="${SYSCTL_DIR}/9999-router.conf"
TIME_ZONE="Asia/Novosibirsk"
TIME_ZONE_DIR="/usr/share/zoneinfo"
TIME_ZONE_FILE="/etc/localtime"
TIME_ZONE_INFO_FILE="${TIME_ZONE_DIR}/${TIME_ZONE}"
UFW_DIR="/etc/ufw"
SUDOERS_DIR="/etc/sudoers.d"
SUDOERS_FILE="${SUDOERS_DIR}/00-superuser"
SUPERUSER_NAME="vpnuser"
SUPERUSER_GROUP="sudo"
SUPERUSER_SHELL="/bin/bash"
SUPERUSER_HOME="/home/${SUPERUSER_NAME}"
SUPERUSER_KEY_FILE="${SUPERUSER_HOME}/.ssh/id_ed25519"
SUPERUSER_AUTHORIZED_KEYS_FILE="${SUPERUSER_HOME}/.ssh/authorized_keys"
# Последовательность очистки экрана в скрипте (CL_CLEAR).
CLEAR_SCREEN=$'\033[H\033[2J'
# Эталонные копии файлов в том виде, в каком их ставит базовый образ и пакеты
# console-setup и unattended-upgrades: setup() восстанавливает из них исходное
# состояние перед каждым сценарием. Сюда же — /etc/localtime и файл зоны
# /usr/share/zoneinfo/Asia/Novosibirsk, которые правит шаг настройки часового
# пояса.
APT_AUTO_UPGRADES_PRISTINE="/usr/share/vpn-test/20auto-upgrades.pristine"
CONSOLE_SETUP_PRISTINE="/usr/share/vpn-test/console-setup.pristine"
LOCALE_CONF_PRISTINE="/usr/share/vpn-test/locale.conf.pristine"
LOCALE_GEN_PRISTINE="/usr/share/vpn-test/locale.gen.pristine"
OS_RELEASE_PRISTINE="/usr/share/vpn-test/os-release.pristine"
TIME_ZONE_FILE_PRISTINE="/usr/share/vpn-test/localtime.pristine"
TIME_ZONE_INFO_PRISTINE="/usr/share/vpn-test/novosibirsk.pristine"
APT_UNATTENDED_UPGRADES_PRISTINE="/usr/share/vpn-test/50unattended-upgrades.pristine"
MOTD_STATIC_FILE_PRISTINE="/usr/share/vpn-test/motd.pristine"
MOTD_UNAME_FILE_PRISTINE="/usr/share/vpn-test/10-uname.pristine"

setup() {
  mkdir --parents "$APT_CONF_DIR"
  cp -- "$APT_AUTO_UPGRADES_PRISTINE" "$APT_AUTO_UPGRADES_FILE"
  cp -- "$APT_UNATTENDED_UPGRADES_PRISTINE" "$APT_UNATTENDED_UPGRADES_FILE"
  cp -- "$CONSOLE_SETUP_PRISTINE" "$CONSOLE_SETUP_FILE"
  cp -- "$OS_RELEASE_PRISTINE" "$OS_RELEASE_FILE"
  # Локали: скрипт раскомментирует строки в /etc/locale.gen и пишет /etc/locale.conf
  # (через символическую ссылку /etc/default/locale его читает pam_env), поэтому
  # возвращаем исходное состояние. Сгенерированные локали остаются в
  # /usr/lib/locale/locale-archive: они не влияют на содержимое файлов.
  cp -- "$LOCALE_GEN_PRISTINE" "$LOCALE_GEN_FILE"
  cp -- "$LOCALE_CONF_PRISTINE" "$LOCALE_CONF_FILE"
  # /etc/localtime — символическая ссылка, поэтому обычный cp записал бы через
  # неё в файл зоны: нужны --remove-destination и --no-dereference.
  cp --remove-destination --no-dereference "$TIME_ZONE_FILE_PRISTINE" "$TIME_ZONE_FILE"
  cp -- "$TIME_ZONE_INFO_PRISTINE" "$TIME_ZONE_INFO_FILE"
  # Сообщение дня: скрипт очищает /etc/motd и удаляет 10-uname, поэтому
  # возвращаем исходное состояние и убираем скрипт, созданный предыдущим
  # сценарием.
  mkdir --parents "$MOTD_DIR"
  rm --force -- "$MOTD_FILE"
  cp -- "$MOTD_STATIC_FILE_PRISTINE" "$MOTD_STATIC_FILE"
  cp -- "$MOTD_UNAME_FILE_PRISTINE" "$MOTD_UNAME_FILE"
  # Журнал systemd: скрипт пишет свой drop-in файл, поэтому убираем файлы,
  # созданные предыдущим сценарием.
  rm --recursive --force -- "$JOURNALD_CONFIG_DIR"
  mkdir --parents "$SYSCTL_DIR"
  rm --force -- "$SYSCTL_FILE"
  # Каталог с настройками sshd: скрипт только добавляет в него свой файл,
  # поэтому достаточно очистить каталог от файлов, созданных тестами.
  mkdir --parents "$SSHD_CONFIG_DIR"
  rm --force -- "${SSHD_CONFIG_DIR}"/*.conf
  # Каталог с настройками ufw: скрипт только проверяет его наличие и вызывает
  # команду ufw (заглушённую), поэтому достаточно восстановить каталог.
  mkdir --parents "$UFW_DIR"
  # Пользователь-суперпользователь, его домашний каталог и настройка sudo:
  # скрипт их создаёт, поэтому перед каждым сценарием возвращаем систему в
  # исходное состояние.
  if getent passwd "$SUPERUSER_NAME" >/dev/null; then
    userdel --remove --force "$SUPERUSER_NAME" >/dev/null 2>&1 || true
  fi
  rm --recursive --force -- "$SUPERUSER_HOME"
  mkdir --parents "$SUDOERS_DIR"
  rm --force -- "$SUDOERS_FILE"

  # apt-get, sysctl, systemctl, timedatectl и ufw не выполняются по-настоящему:
  # тесты проверяют не установку пакетов и не применение настроек, а то, как
  # скрипт их запускает. Заглушки записывают вызовы в файлы, чтобы тест мог
  # проверить их состав и порядок.
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  local name
  mkdir --parents "$stub_dir"
  for name in apt-get sysctl systemctl timedatectl ufw; do
    cat > "${stub_dir}/${name}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${BATS_TEST_TMPDIR}/${name}.calls"
EOF
    chmod +x "${stub_dir}/${name}"
  done
  # locale-gen собирает локали несколько секунд, а тесты проверяют не сборку, а
  # то, что скрипт его запускает: заглушка только отмечает вызов
  cat > "${stub_dir}/locale-gen" <<EOF
#!/usr/bin/env bash
echo called > "${BATS_TEST_TMPDIR}/locale-gen.called"
EOF
  chmod +x "${stub_dir}/locale-gen"
  export PATH="${stub_dir}:${PATH}"
}

# Перезаписывает строку параметра целиком (строка может быть закомментирована).
write_param() {
  local key="$1"
  local assignment="$2"

  sed --in-place --regexp-extended \
      "s|^[[:space:]]*#?[[:space:]]*${key}=.*|${assignment}|" "$CONSOLE_SETUP_FILE"
}

# Комментирует параметр, оставляя его на месте.
comment_out_param() {
  write_param "$1" "# $2"
}

# Полностью удаляет строку параметра.
drop_param() {
  local key="$1"

  sed --in-place --regexp-extended \
      "/^[[:space:]]*#?[[:space:]]*${key}=/d" "$CONSOLE_SETUP_FILE"
}

# Число строк файла, целиком совпадающих с ожидаемой строкой; первым аргументом
# идёт строка, вторым — файл. При отсутствии совпадений возвращает 0, а не ошибку.
count_exact_lines() {
  grep --fixed-strings --line-regexp --count -- "$1" "$2" || true
}

# Перезаписывает строку параметра apt.conf целиком (строка может быть
# закомментирована через //).
write_apt_conf_param() {
  local file="$1"
  local assignment="$2"
  local key="${assignment%% *}"

  sed --in-place --regexp-extended \
      "s|^[[:space:]]*(//)?[[:space:]]*${key}[[:space:]]+.*|${assignment}|" "$file"
}

# Проверяет, что в файле есть строка, целиком совпадающая с ожидаемой.
assert_has_line() {
  grep --fixed-strings --line-regexp --quiet -- "$1" "$2"
}

# Запускает скрипт, подавая на вход имя суперпользователя.
run_script() {
  run "$SCRIPT_UNDER_TEST" <<< "$SUPERUSER_NAME"
}

# QR-код ключа в том виде, в каком его выводит скрипт: с полем в два символа.
key_qr_code() {
  qrencode -t UTF8 --margin=2 < "$1"
}

# Проверяет, что <путь> — символическая ссылка на <цель>.
assert_symlink_target() {
  [ "$(readlink -- "$1")" = "$2" ]
}

# Пакеты из APT_PACKAGES в скрипте, по одному в строке.
script_apt_packages() {
  sed --quiet --regexp-extended '/^APT_PACKAGES=\(/,/^\)/p' "$SCRIPT_UNDER_TEST" \
    | sed --regexp-extended --expression='1d' --expression='$d' \
    | tr --delete '[:blank:]'
}

# Пакеты, которые ставит тестовый образ (RUN apt-get install ...), по одному
# в строке.
dockerfile_apt_packages() {
  sed --quiet --regexp-extended \
      '/apt-get install/,/rm -rf/p' \
      "${BATS_TEST_DIRNAME}/vpn.Dockerfile" \
    | grep --invert-match --fixed-strings -- '&&' \
    | tr --delete '[:blank:]\\'
}

@test "sets the required values for the three console parameters" {
  write_param CODESET 'CODESET="ASCII-8"'
  write_param FONTFACE 'FONTFACE="LatArCyrHeb-16"'
  write_param FONTSIZE 'FONTSIZE="16x32"'

  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updating ${CONSOLE_SETUP_FILE}"* ]]
  assert_has_line 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE"
  assert_has_line 'FONTFACE="Terminus"' "$CONSOLE_SETUP_FILE"
  assert_has_line 'FONTSIZE="8x16"' "$CONSOLE_SETUP_FILE"

  # Остальные настройки пакета не затронуты, включая закомментированный
  # пример FONT= (ключ FONT — префикс ключа FONTFACE).
  assert_has_line 'ACTIVE_CONSOLES="/dev/tty[1-6]"' "$CONSOLE_SETUP_FILE"
  assert_has_line 'CHARMAP="UTF-8"' "$CONSOLE_SETUP_FILE"
  assert_has_line 'VIDEOMODE=' "$CONSOLE_SETUP_FILE"
  assert_has_line "# FONT='lat9w-08.psf.gz brl-8x8.psf'" "$CONSOLE_SETUP_FILE"
}

@test "replaces commented-out parameters in place without duplicating them" {
  comment_out_param CODESET 'CODESET="guess"'
  comment_out_param FONTFACE 'FONTFACE="Fixed"'
  comment_out_param FONTSIZE 'FONTSIZE="8x16"'
  local lines_before
  lines_before="$(wc --lines < "$CONSOLE_SETUP_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines '# CODESET="guess"' "$CONSOLE_SETUP_FILE")" -eq 0 ]
  # Строки заменены на месте, а не добавлены в конец файла.
  [ "$(wc --lines < "$CONSOLE_SETUP_FILE")" -eq "$lines_before" ]
}

@test "appends parameters that are missing from the file" {
  drop_param CODESET
  drop_param FONTFACE
  drop_param FONTSIZE
  local lines_before
  lines_before="$(wc --lines < "$CONSOLE_SETUP_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(wc --lines < "$CONSOLE_SETUP_FILE")" -eq "$((lines_before + 3))" ]
}

@test "is idempotent: a second run does not change the file" {
  run_script
  [ "$status" -eq 0 ]
  local after_first
  after_first="$(sha256sum "$CONSOLE_SETUP_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$CONSOLE_SETUP_FILE")" = "$after_first" ]
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
}

@test "fails with a clear message when the configuration file is missing" {
  rm -- "$CONSOLE_SETUP_FILE"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$CONSOLE_SETUP_FILE"* ]]
}

@test "enables the required locales and generates them" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Enabling the locales "*" in ${LOCALE_GEN_FILE}"* ]]
  [[ "$output" == *"Generating the locales"* ]]
  assert_has_line 'en_US.UTF-8 UTF-8' "$LOCALE_GEN_FILE"
  assert_has_line 'ru_RU.UTF-8 UTF-8' "$LOCALE_GEN_FILE"
  # Остальные строки файла, включая другие локали, не меняются
  [ "$(count_exact_lines '# en_GB.UTF-8 UTF-8' "$LOCALE_GEN_FILE")" -eq 1 ]
  [ -f "${BATS_TEST_TMPDIR}/locale-gen.called" ]
}

@test "writes the locale settings into the locale configuration file" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updating ${LOCALE_CONF_FILE}"* ]]
  # Локаль по умолчанию — английская, а форматы даты и времени, чисел, денег,
  # адресов, имён и телефонов — русские
  assert_has_line "LANG=${LOCALE_DEFAULT}" "$LOCALE_CONF_FILE"
  local param
  for param in "${LOCALE_PARAMS[@]}"; do
    assert_has_line "$param" "$LOCALE_CONF_FILE"
  done
}

@test "leaves the categories without a value of their own to the default locale" {
  run_script

  [ "$status" -eq 0 ]
  # Своих строк у них нет, поэтому они берут значение из LANG
  local param
  for param in LC_CTYPE LC_COLLATE LC_MESSAGES LC_ALL; do
    run grep --quiet "^${param}=" "$LOCALE_CONF_FILE"
    [ "$status" -ne 0 ]
  done
}

@test "replaces locale settings that already have a different value in place" {
  printf 'LANG=de_DE.UTF-8\nLC_TIME=de_DE.UTF-8\n' > "$LOCALE_CONF_FILE"

  run_script

  [ "$status" -eq 0 ]
  [ "$(count_exact_lines 'LANG=de_DE.UTF-8' "$LOCALE_CONF_FILE")" -eq 0 ]
  [ "$(count_exact_lines 'LC_TIME=de_DE.UTF-8' "$LOCALE_CONF_FILE")" -eq 0 ]
  [ "$(count_exact_lines 'LC_TIME=ru_RU.UTF-8' "$LOCALE_CONF_FILE")" -eq 1 ]
  # Заменённые строки остаются на своих местах, а не дублируются в конце файла
  [ "$(sed --quiet --expression='1p' "$LOCALE_CONF_FILE")" = "LANG=${LOCALE_DEFAULT}" ]
  [ "$(sed --quiet --expression='2p' "$LOCALE_CONF_FILE")" = 'LC_TIME=ru_RU.UTF-8' ]
}

@test "is idempotent for the locale: a second run does not change the files" {
  run_script
  [ "$status" -eq 0 ]
  local gen_after_first
  local conf_after_first
  gen_after_first="$(sha256sum "$LOCALE_GEN_FILE")"
  conf_after_first="$(sha256sum "$LOCALE_CONF_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$LOCALE_GEN_FILE")" = "$gen_after_first" ]
  [ "$(sha256sum "$LOCALE_CONF_FILE")" = "$conf_after_first" ]
}

@test "applies the locale in the current session" {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir --parents "$stub_dir"
  # setupcon вызывается следующим шагом, поэтому по его окружению видно, что
  # локаль применена в текущей сессии скрипта; LC_ALL при этом снимается, иначе
  # он перекрыл бы остальные переменные
  cat > "${stub_dir}/setupcon" <<EOF
#!/usr/bin/env bash
env > "${BATS_TEST_TMPDIR}/setupcon.env"
EOF
  chmod +x "${stub_dir}/setupcon"
  export PATH="${stub_dir}:${PATH}"

  run env LC_ALL=C "$SCRIPT_UNDER_TEST" <<< "$SUPERUSER_NAME"

  [ "$status" -eq 0 ]
  local env_dump="${BATS_TEST_TMPDIR}/setupcon.env"
  assert_has_line "LANG=${LOCALE_DEFAULT}" "$env_dump"
  local param
  for param in "${LOCALE_PARAMS[@]}"; do
    assert_has_line "$param" "$env_dump"
  done
  [ "$(count_exact_lines 'LC_ALL=C' "$env_dump")" -eq 0 ]
}

@test "generates the locale data so that the settings take effect" {
  # Этот сценарий проверяет настоящую сборку локалей, поэтому убирает заглушку
  # locale-gen и собранные в образе локали
  rm --force -- "${BATS_TEST_TMPDIR}/bin/locale-gen"
  rm --force -- /usr/lib/locale/locale-archive

  run_script

  [ "$status" -eq 0 ]
  run locale --all-locales
  [[ "$output" == *"en_US.utf8"* ]]
  [[ "$output" == *"ru_RU.utf8"* ]]
  # Написанные настройки дают русские форматы при английских сообщениях
  run bash -c "set -a; . '$LOCALE_CONF_FILE'; locale"
  [ "$status" -eq 0 ]
  [[ "$output" == *'LC_TIME=ru_RU.UTF-8'* ]]
  [[ "$output" == *'LC_MONETARY=ru_RU.UTF-8'* ]]
  [[ "$output" == *'LC_CTYPE="en_US.UTF-8"'* ]]
  [[ "$output" == *'LC_MESSAGES="en_US.UTF-8"'* ]]
}

@test "fails with a clear message when the locale list is missing" {
  rm -- "$LOCALE_GEN_FILE"
  local conf_before
  conf_before="$(sha256sum "$LOCALE_CONF_FILE")"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$LOCALE_GEN_FILE"* ]]
  # Шаг идёт сразу после установки пакетов, поэтому локаль не настроена
  [ "$(sha256sum "$LOCALE_CONF_FILE")" = "$conf_before" ]
  [ ! -f "${BATS_TEST_TMPDIR}/locale-gen.called" ]
}

@test "fails on a system that is not Debian" {
  printf 'ID=ubuntu\n' > "$OS_RELEASE_FILE"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"the current system is ubuntu"* ]]
  # Настройка консоли не выполняется: проверка ОС идёт первой.
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
  # Часовой пояс тоже не меняется: его шаг идёт сразу после проверки ОС.
  assert_symlink_target "$TIME_ZONE_FILE" "${TIME_ZONE_DIR}/Etc/UTC"
}

@test "fails when the system ID cannot be determined" {
  printf 'NAME="Some OS"\n' > "$OS_RELEASE_FILE"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"the current system is unknown"* ]]
  # Настройка консоли не выполняется: проверка ОС идёт первой.
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
}

@test "fails on Debian older than the minimum version" {
  printf 'ID=debian\nVERSION_ID="11"\n' > "$OS_RELEASE_FILE"

  run_script

  [ "$status" -ne 0 ]
  # Минимальная версия выводится выделенной (жирным).
  local bold=$'\033[1m'
  local reset=$'\033[0m'
  [[ "$output" == *"requires Debian ${bold}13${reset} or newer, the current version is 11"* ]]
  # Настройка консоли не выполняется: проверка ОС идёт первой.
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
  # Часовой пояс тоже не меняется: его шаг идёт сразу после проверки ОС.
  assert_symlink_target "$TIME_ZONE_FILE" "${TIME_ZONE_DIR}/Etc/UTC"
}

@test "accepts the minimum supported Debian version" {
  printf 'ID=debian\nVERSION_ID="13"\n' > "$OS_RELEASE_FILE"

  run_script

  [ "$status" -eq 0 ]
}

@test "skips the version check when the Debian version is not specified" {
  # В Debian testing и sid поля VERSION_ID нет.
  printf 'ID=debian\nVERSION_CODENAME=forky\n' > "$OS_RELEASE_FILE"

  run_script

  [ "$status" -eq 0 ]
}

@test "fails when the OS release file is missing" {
  rm -- "$OS_RELEASE_FILE"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot detect the operating system"* ]]
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
}

@test "fails when the script is not run as root" {
  run setpriv --reuid nobody --regid nogroup --clear-groups \
    "$SCRIPT_UNDER_TEST" <<< "$SUPERUSER_NAME"

  [ "$status" -ne 0 ]
  [[ "$output" == *"must be run as root, the current user is nobody"* ]]
  # Настройка консоли не выполняется: проверка прав идёт сразу после проверки ОС.
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
  # Часовой пояс тоже не меняется.
  assert_symlink_target "$TIME_ZONE_FILE" "${TIME_ZONE_DIR}/Etc/UTC"
}

@test "sets the time zone to Asia/Novosibirsk" {
  run_script

  [ "$status" -eq 0 ]
  # Значение часового пояса выводится выделенным (жирным).
  local bold=$'\033[1m'
  local reset=$'\033[0m'
  [[ "$output" == *"Setting the time zone to ${bold}${TIME_ZONE}${reset} in ${TIME_ZONE_FILE}"* ]]
  assert_symlink_target "$TIME_ZONE_FILE" "$TIME_ZONE_INFO_FILE"
}

@test "is idempotent for the time zone: a second run does not change the link" {
  run_script
  [ "$status" -eq 0 ]
  local target_after_first
  target_after_first="$(readlink -- "$TIME_ZONE_FILE")"

  run_script

  [ "$status" -eq 0 ]
  assert_symlink_target "$TIME_ZONE_FILE" "$target_after_first"
}

@test "enables time synchronization with timedatectl" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Enabling time synchronization"* ]]
  [ "$(cat "${BATS_TEST_TMPDIR}/timedatectl.calls")" = 'set-ntp true' ]
}

@test "fails with a clear message when the time zone data is missing" {
  rm -- "$TIME_ZONE_INFO_FILE"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$TIME_ZONE_INFO_FILE"* ]]
  # Файл зоны проверяется до правки ссылки и до включения синхронизации
  # времени, поэтому /etc/localtime не тронут, а timedatectl не вызывался.
  assert_symlink_target "$TIME_ZONE_FILE" "${TIME_ZONE_DIR}/Etc/UTC"
  [ ! -f "${BATS_TEST_TMPDIR}/timedatectl.calls" ]
}

@test "configures the message of the day" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Configuring the message of the day"* ]]
  [[ "$output" == *"Updating ${MOTD_FILE}"* ]]
  # Скрипт кладётся в каталог, который pam_motd выполняет при каждом входе, и
  # run-parts его отбирает; сводку формирует он, а не стандартные скрипты пакетов.
  [ -x "$MOTD_FILE" ]
  [[ "$(run-parts --list "$MOTD_DIR")" == *"$MOTD_FILE"* ]]
  # Стандартный текст base-files не выводится: статическое сообщение очищено, а
  # скрипт с uname удалён.
  [ ! -s "$MOTD_STATIC_FILE" ]
  [ ! -e "$MOTD_UNAME_FILE" ]
}

@test "shows the host, the resource usage and the uptime in two columns" {
  run_script
  [ "$status" -eq 0 ]

  run "$MOTD_FILE"

  [ "$status" -eq 0 ]
  local os_name
  local host_name
  local kernel
  os_name="$(sed --quiet --regexp-extended 's/^PRETTY_NAME="(.*)"$/\1/p' "$OS_RELEASE_FILE")"
  host_name="$(hostname)"
  kernel="$(uname --kernel-release)"
  # Подписи выделены жирным, цвета нет: цветовые коды содержат «;», например 1;36.
  [[ "$output" == *$'\033[1m'* ]]
  [[ "$output" == *$'\033[0m'* ]]
  [[ "$output" != *';'* ]]
  # Убираем выделение, чтобы проверять текст таблицы.
  local escape=$'\033'
  local plain
  plain="$(sed --regexp-extended "s/${escape}\[[0-9;]*m//g" <<< "$output")"
  # Пустые строки вокруг таблицы проверяет отдельный тест, здесь — только
  # строки таблицы.
  local table
  table="$(sed --regexp-extended '/^$/d' <<< "$plain")"
  # Две колонки по четыре строки: слева характеристики хоста, справа —
  # потребление ресурсов и время работы. Архитектуры процессора в выводе нет.
  [ "$(wc --lines <<< "$table")" -eq 4 ]
  [[ "$(sed --quiet 1p <<< "$table")" == "OS"*"${os_name}"*"Uptime"* ]]
  [[ "$(sed --quiet 2p <<< "$table")" == "Kernel"*"${kernel}"*"Load"* ]]
  [[ "$(sed --quiet 3p <<< "$table")" == "Host"*"${host_name}"*"Memory"* ]]
  [[ "$(sed --quiet 4p <<< "$table")" == "IP"*"Disk"* ]]
  [[ "$table" != *"Arch"* ]]
  # Строка IP содержит основной адрес хоста.
  [[ "$(sed --quiet 4p <<< "$table")" =~ ^IP\ +[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]
  # Правый столбец начинается в одной и той же колонке на всех строках.
  local right_columns
  right_columns="$(awk '{ match($0, /(Uptime|Load|Memory|Disk)/); print RSTART }' <<< "$table" | sort --unique)"
  [ "$(wc --lines <<< "$right_columns")" -eq 1 ]
  # Текущее потребление ресурсов и время работы.
  [[ "$table" == *"$(nproc) cores)"* ]]
  [[ "$table" == *" GiB / "* ]]
  [[ "$table" == *"%)"* ]]
  # Время работы выводится человекочитаемо: единицы измерения, а не секунды.
  [[ "$(sed --quiet 1p <<< "$table")" =~ Uptime\ +[0-9] ]]
}

@test "surrounds the summary with blank lines" {
  run_script
  [ "$status" -eq 0 ]

  # Вывод пишется в файл: в переменной bats и в подстановке команды конечная
  # пустая строка теряется.
  local file
  file="$(mktemp)"
  "$MOTD_FILE" > "$file"

  [ -z "$(sed --quiet 1p "$file")" ]
  [ -z "$(sed --quiet '$p' "$file")" ]
  # Между пустыми строками — только таблица.
  [ "$(grep --count --invert-match --extended-regexp '^$' "$file")" -eq 4 ]
  rm --force -- "$file"
}

@test "is idempotent for the message of the day: a second run does not change it" {
  run_script
  [ "$status" -eq 0 ]
  local script_after_first
  local static_after_first
  script_after_first="$(sha256sum "$MOTD_FILE")"
  static_after_first="$(sha256sum "$MOTD_STATIC_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$MOTD_FILE")" = "$script_after_first" ]
  [ "$(sha256sum "$MOTD_STATIC_FILE")" = "$static_after_first" ]
  [ ! -e "$MOTD_UNAME_FILE" ]
}

@test "the message of the day script passes shellcheck" {
  run_script
  [ "$status" -eq 0 ]

  run shellcheck "$MOTD_FILE"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails with a clear message when the message of the day directory is missing" {
  rm --recursive --force -- "$MOTD_DIR"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$MOTD_DIR"* ]]
  # Шаг идёт после настройки часового пояса, поэтому она уже выполнена.
  assert_symlink_target "$TIME_ZONE_FILE" "$TIME_ZONE_INFO_FILE"
}

@test "writes the journal settings into a drop-in file" {
  run_script

  [ "$status" -eq 0 ]
  # Путь к файлу выделен жирным.
  local bold=$'\033[1m'
  local reset=$'\033[0m'
  [[ "$output" == *"Updating ${bold}${JOURNALD_CONFIG_FILE}${reset}"* ]]
  assert_has_line '[Journal]' "$JOURNALD_CONFIG_FILE"
  assert_has_line 'Storage=persistent' "$JOURNALD_CONFIG_FILE"
  assert_has_line 'SystemMaxUse=128M' "$JOURNALD_CONFIG_FILE"
  # Каждый из параметров задан ровно один раз.
  [ "$(count_exact_lines 'Storage=persistent' "$JOURNALD_CONFIG_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'SystemMaxUse=128M' "$JOURNALD_CONFIG_FILE")" -eq 1 ]
}

@test "keeps the journal configuration file of the package untouched" {
  local before
  before="$(sha256sum "$JOURNALD_FILE")"

  run_script

  [ "$status" -eq 0 ]
  # Значения по умолчанию из файла пакета остаются на месте: правки живут в
  # drop-in файле, а не в conffile.
  [ "$(sha256sum "$JOURNALD_FILE")" = "$before" ]
  assert_has_line '#Storage=auto' "$JOURNALD_FILE"
}

@test "the journal settings take effect" {
  run_script
  [ "$status" -eq 0 ]

  run systemd-analyze cat-config systemd/journald.conf

  [ "$status" -eq 0 ]
  [[ "$output" == *"${JOURNALD_CONFIG_FILE}"* ]]
  # В эффективной конфигурации заданы именно наши значения.
  [ "$(sed --quiet '/^Storage=/p' <<< "$output")" = 'Storage=persistent' ]
  [ "$(sed --quiet '/^SystemMaxUse=/p' <<< "$output")" = 'SystemMaxUse=128M' ]
}

@test "is idempotent for the journal settings: a second run does not change the file" {
  run_script
  [ "$status" -eq 0 ]
  local after_first
  after_first="$(sha256sum "$JOURNALD_CONFIG_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$JOURNALD_CONFIG_FILE")" = "$after_first" ]
}

@test "applies the journal settings by restarting journald" {
  run_script

  [ "$status" -eq 0 ]
  assert_has_line 'restart systemd-journald' "${BATS_TEST_TMPDIR}/systemctl.calls"
}

@test "writes the SSH settings into a drop-in file and they take effect" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updating ${SSHD_CONFIG_FILE}"* ]]
  assert_has_line 'PasswordAuthentication no' "$SSHD_CONFIG_FILE"
  assert_has_line 'PermitRootLogin no' "$SSHD_CONFIG_FILE"
  # sshd использует первое полученное значение, а каталог ${SSHD_CONFIG_DIR}
  # подключается в начале sshd_config, поэтому наши значения действуют:
  # проверяем эффективную конфигурацию (sshd -T).
  local effective
  effective="$(sshd -T)"
  [[ "$effective" == *$'\npermitrootlogin no'* ]]
  [[ "$effective" == *$'\npasswordauthentication no'* ]]
}

@test "the SSH settings override other files in the configuration directory" {
  # 50-cloud-init.conf встречается в облачных образах Debian и включает вход по
  # паролю; наш файл должен перекрывать его.
  printf 'PasswordAuthentication yes\nPermitRootLogin prohibit-password\n' \
      > "${SSHD_CONFIG_DIR}/50-cloud-init.conf"

  run_script

  [ "$status" -eq 0 ]
  local effective
  effective="$(sshd -T)"
  [[ "$effective" == *$'\npermitrootlogin no'* ]]
  [[ "$effective" == *$'\npasswordauthentication no'* ]]
}

@test "is idempotent for the SSH settings: a second run does not change the file" {
  run_script
  [ "$status" -eq 0 ]
  local after_first
  after_first="$(sha256sum "$SSHD_CONFIG_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$SSHD_CONFIG_FILE")" = "$after_first" ]
}

@test "applies the SSH settings by reloading sshd" {
  run_script

  [ "$status" -eq 0 ]
  assert_has_line 'reload ssh' "${BATS_TEST_TMPDIR}/systemctl.calls"
}

@test "fails with a clear message when the sshd configuration directory is missing" {
  rm --recursive --force -- "$SSHD_CONFIG_DIR"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$SSHD_CONFIG_DIR"* ]]
  # Шаг идёт после настройки консоли и параметров ядра, поэтому они уже выполнены.
  assert_has_line 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE"
  assert_has_line 'net.ipv4.ip_forward = 1' "$SYSCTL_FILE"
  # Служба Docker включается последним шагом, до неё дело не дошло; sshd тоже не
  # перезагружался: единственный вызов systemctl — перезапуск journald.
  [ "$(cat "${BATS_TEST_TMPDIR}/systemctl.calls")" = 'restart systemd-journald' ]
}

@test "leaves only ssh open for incoming connections and allows all outgoing ones" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Denying incoming connections except ssh and allowing outgoing and routed connections"* ]]
  [[ "$output" == *"Enabling the firewall"* ]]
  # Входящие соединения запрещены по умолчанию, разрешён только ssh; исходящие и
  # перенаправляемые разрешены. ssh разрешается до включения брандмауэра, поэтому
  # доступ не теряется, а включение идёт без вопроса (--force).
  [ "$(cat "${BATS_TEST_TMPDIR}/ufw.calls")" \
      = $'default deny incoming\ndefault allow outgoing\ndefault allow routed\nallow ssh\n--force enable' ]
}

@test "forwards traffic of vpn clients" {
  run_script

  [ "$status" -eq 0 ]
  # Транзитный трафик клиентов VPN должен проходить: политика по умолчанию для
  # перенаправляемых соединений — allow.
  assert_has_line 'default allow routed' "${BATS_TEST_TMPDIR}/ufw.calls"
}

@test "applies the firewall rules again on a second run without changing them" {
  run_script
  [ "$status" -eq 0 ]
  local first_run
  first_run="$(cat "${BATS_TEST_TMPDIR}/ufw.calls")"

  run_script

  [ "$status" -eq 0 ]
  # Скрипт каждый раз задаёт одни и те же правила, поэтому повторный запуск
  # безопасен: ssh остаётся разрешён.
  [ "$(cat "${BATS_TEST_TMPDIR}/ufw.calls")" = "${first_run}"$'\n'"${first_run}" ]
}

@test "fails with a clear message when the ufw configuration directory is missing" {
  rm --recursive --force -- "$UFW_DIR"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$UFW_DIR"* ]]
  # Шаг идёт после настройки SSH, поэтому она уже выполнена.
  assert_has_line 'PasswordAuthentication no' "$SSHD_CONFIG_FILE"
  # Каталог проверяется до вызовов ufw, поэтому брандмауэр не настраивается.
  [ ! -f "${BATS_TEST_TMPDIR}/ufw.calls" ]
}

@test "updates the package database and installs the packages in alphabetical order" {
  run_script

  [ "$status" -eq 0 ]
  # Сначала обновляется база пакетов, затем ставятся пакеты в алфавитном
  # порядке; ничего лишнего не вызывается.
  [ "$(cat "${BATS_TEST_TMPDIR}/apt-get.calls")" \
      = $'update\ninstall --yes console-setup curl docker-cli docker-compose docker.io iproute2 locales openssh-client openssh-server procps qrencode sudo systemd-timesyncd ufw unattended-upgrades' ]
}

@test "enables and starts the Docker service as the last step" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Configuring Docker"* ]]
  [[ "$output" == *"Enabling and starting the Docker service"* ]]
  # Служба включается последним шагом: вызовы systemctl до него — перезапуск
  # journald и перезагрузка sshd.
  [ "$(cat "${BATS_TEST_TMPDIR}/systemctl.calls")" \
      = $'restart systemd-journald\nreload ssh\nenable --now docker' ]
}

@test "writes the kernel parameters" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updating ${SYSCTL_FILE}"* ]]
  assert_has_line 'kernel.printk = 4 4 1 4' "$SYSCTL_FILE"
  assert_has_line 'net.core.default_qdisc = fq' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.ip_forward = 1' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.tcp_congestion_control = bbr' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.tcp_keepalive_probes = 1' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.tcp_mtu_probing = 1' "$SYSCTL_FILE"
  assert_has_line 'net.ipv6.conf.all.disable_ipv6 = 1' "$SYSCTL_FILE"
  # Записаны только заданные параметры, по одному в строке.
  [ "$(wc --lines < "$SYSCTL_FILE")" -eq 7 ]
}

@test "keeps the rest of the kernel parameters file and rewrites existing lines in place" {
  cat > "$SYSCTL_FILE" <<'EOF'
# Local notes
net.ipv4.tcp_congestion_control = cubic
#net.ipv4.ip_forward=0
vm.swappiness = 10
EOF
  local lines_before
  lines_before="$(wc --lines < "$SYSCTL_FILE")"

  run_script

  [ "$status" -eq 0 ]
  # Строки с нашими ключами заменены на месте, в том числе закомментированная.
  assert_has_line 'net.ipv4.tcp_congestion_control = bbr' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.ip_forward = 1' "$SYSCTL_FILE"
  [ "$(count_exact_lines 'net.ipv4.tcp_congestion_control = bbr' "$SYSCTL_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'net.ipv4.ip_forward = 1' "$SYSCTL_FILE")" -eq 1 ]
  # Чужие строки не тронуты, остальные наши параметры добавлены в конец файла.
  assert_has_line '# Local notes' "$SYSCTL_FILE"
  assert_has_line 'vm.swappiness = 10' "$SYSCTL_FILE"
  assert_has_line 'kernel.printk = 4 4 1 4' "$SYSCTL_FILE"
  [ "$(wc --lines < "$SYSCTL_FILE")" -eq "$((lines_before + 5))" ]
}

@test "is idempotent for the kernel parameters file: a second run does not change it" {
  run_script
  [ "$status" -eq 0 ]
  local after_first
  after_first="$(sha256sum "$SYSCTL_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$SYSCTL_FILE")" = "$after_first" ]
}

@test "applies the kernel parameters by running sysctl --load" {
  run_script

  [ "$status" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/sysctl.calls")" = "--load=${SYSCTL_FILE}" ]
}

@test "fails with a clear message when the kernel parameters directory is missing" {
  rm --recursive --force -- "$SYSCTL_DIR"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$SYSCTL_DIR"* ]]
  # Шаг идёт после настройки консоли, поэтому она уже выполнена.
  assert_has_line 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE"
}

@test "enables upgrades, removal of unused packages and a reboot at 05:00" {
  run_script

  [ "$status" -eq 0 ]
  # Перед записью каждого файла скрипт сообщает, какой файл обновляет.
  [[ "$output" == *"Updating ${APT_AUTO_UPGRADES_FILE}"* ]]
  [[ "$output" == *"Updating ${APT_UNATTENDED_UPGRADES_FILE}"* ]]
  assert_has_line 'APT::Periodic::Update-Package-Lists "1";' "$APT_AUTO_UPGRADES_FILE"
  assert_has_line 'APT::Periodic::Unattended-Upgrade "1";' "$APT_AUTO_UPGRADES_FILE"
  assert_has_line 'APT::Periodic::AutocleanInterval "7";' "$APT_AUTO_UPGRADES_FILE"
  assert_has_line 'Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";' "$APT_UNATTENDED_UPGRADES_FILE"
  assert_has_line 'Unattended-Upgrade::Remove-Unused-Dependencies "true";' "$APT_UNATTENDED_UPGRADES_FILE"
  assert_has_line 'Unattended-Upgrade::Automatic-Reboot "true";' "$APT_UNATTENDED_UPGRADES_FILE"
  assert_has_line 'Unattended-Upgrade::Automatic-Reboot-Time "05:00";' "$APT_UNATTENDED_UPGRADES_FILE"
  assert_has_line 'Unattended-Upgrade::Automatic-Reboot-WithUsers "true";' "$APT_UNATTENDED_UPGRADES_FILE"
  # Каждый из изменённых параметров задан ровно один раз.
  [ "$(count_exact_lines 'APT::Periodic::Update-Package-Lists "1";' "$APT_AUTO_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'APT::Periodic::Unattended-Upgrade "1";' "$APT_AUTO_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'APT::Periodic::AutocleanInterval "7";' "$APT_AUTO_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'Unattended-Upgrade::Remove-Unused-Dependencies "true";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'Unattended-Upgrade::Automatic-Reboot "true";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'Unattended-Upgrade::Automatic-Reboot-Time "05:00";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'Unattended-Upgrade::Automatic-Reboot-WithUsers "true";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 1 ]
}

@test "replaces commented-out automatic upgrade settings in place" {
  # Штатный файл содержит закомментированные настройки перезагрузки и очистки.
  assert_has_line '//Unattended-Upgrade::Automatic-Reboot "false";' "$APT_UNATTENDED_UPGRADES_FILE"
  assert_has_line '//Unattended-Upgrade::Automatic-Reboot-Time "02:00";' "$APT_UNATTENDED_UPGRADES_FILE"
  assert_has_line '//Unattended-Upgrade::Remove-Unused-Dependencies "false";' "$APT_UNATTENDED_UPGRADES_FILE"
  local lines_before
  lines_before="$(wc --lines < "$APT_UNATTENDED_UPGRADES_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(count_exact_lines '//Unattended-Upgrade::Automatic-Reboot "false";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 0 ]
  [ "$(count_exact_lines '//Unattended-Upgrade::Automatic-Reboot-Time "02:00";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 0 ]
  [ "$(count_exact_lines '//Unattended-Upgrade::Remove-Unused-Dependencies "false";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 0 ]
  # Строки заменены на месте, а не добавлены в конец файла.
  [ "$(wc --lines < "$APT_UNATTENDED_UPGRADES_FILE")" -eq "$lines_before" ]
}

@test "rewrites automatic upgrade settings that are already active" {
  write_apt_conf_param "$APT_AUTO_UPGRADES_FILE" 'APT::Periodic::Unattended-Upgrade "0";'
  write_apt_conf_param "$APT_UNATTENDED_UPGRADES_FILE" 'Unattended-Upgrade::Automatic-Reboot-Time "03:00";'

  run_script

  [ "$status" -eq 0 ]
  assert_has_line 'APT::Periodic::Unattended-Upgrade "1";' "$APT_AUTO_UPGRADES_FILE"
  assert_has_line 'Unattended-Upgrade::Automatic-Reboot-Time "05:00";' "$APT_UNATTENDED_UPGRADES_FILE"
  [ "$(count_exact_lines 'APT::Periodic::Unattended-Upgrade "1";' "$APT_AUTO_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'Unattended-Upgrade::Automatic-Reboot-Time "05:00";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 1 ]
}

@test "is idempotent for the automatic upgrade files: a second run does not change them" {
  run_script
  [ "$status" -eq 0 ]
  local auto_upgrades_after
  local unattended_upgrades_after
  auto_upgrades_after="$(sha256sum "$APT_AUTO_UPGRADES_FILE")"
  unattended_upgrades_after="$(sha256sum "$APT_UNATTENDED_UPGRADES_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$APT_AUTO_UPGRADES_FILE")" = "$auto_upgrades_after" ]
  [ "$(sha256sum "$APT_UNATTENDED_UPGRADES_FILE")" = "$unattended_upgrades_after" ]
}

@test "fails with a clear message when the apt configuration directory is missing" {
  rm --recursive --force -- "$APT_CONF_DIR"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$APT_CONF_DIR"* ]]
  # Шаг идёт после настройки консоли, поэтому она уже выполнена.
  assert_has_line 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE"
  # Настройка часового пояса идёт раньше, поэтому уже выполнена.
  assert_symlink_target "$TIME_ZONE_FILE" "$TIME_ZONE_INFO_FILE"
}

@test "installs in the test image the same packages as the script" {
  run diff --unified \
      <(script_apt_packages) \
      <(dockerfile_apt_packages)

  [ "$status" -eq 0 ]
}

@test "applies the configuration by running setupcon" {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir --parents "$stub_dir"
  cat > "${stub_dir}/setupcon" <<EOF
#!/usr/bin/env bash
echo called > "${BATS_TEST_TMPDIR}/setupcon.called"
EOF
  chmod +x "${stub_dir}/setupcon"
  export PATH="${stub_dir}:${PATH}"

  run_script

  [ "$status" -eq 0 ]
  [ -f "${BATS_TEST_TMPDIR}/setupcon.called" ]
}

@test "asks for the superuser name and shows the SSH private key QR on a cleared screen" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Configuring the superuser"* ]]
  [[ "$output" == *"Adding a new superuser or turning an existing regular user into the superuser"* ]]
  # На чистом экране первая строка — подпись User name: с именем, выделенным
  # жирным, вторая — заголовок, дальше — QR-код приватного ключа
  # (qrencode -t UTF8 --margin=2).
  local bold=$'\033[1m'
  local reset=$'\033[0m'
  local key_qr
  key_qr="$(key_qr_code "$SUPERUSER_KEY_FILE")"
  [[ "$output" == *"${CLEAR_SCREEN}User name: ${bold}${SUPERUSER_NAME}${reset}"$'\n'"SSH private key:"$'\n'"${key_qr}"* ]]
}

@test "creates the superuser with a home directory and a bash shell" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Creating the user "*"${SUPERUSER_NAME}"* ]]
  local entry
  entry="$(getent passwd "$SUPERUSER_NAME")"
  [ "$(cut --delimiter=: --fields=6 <<< "$entry")" = "$SUPERUSER_HOME" ]
  [ "$(cut --delimiter=: --fields=7 <<< "$entry")" = "$SUPERUSER_SHELL" ]
  [ -d "$SUPERUSER_HOME" ]
}

@test "adds the superuser to the sudo group" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Adding the user "*"${SUPERUSER_NAME}"*"${SUPERUSER_GROUP}"* ]]
  # Членство в группе администраторов проверяют программы, которые в sudoers не
  # смотрят: они выполняют groups <имя> и ищут в списке групп sudo.
  local group_names
  group_names="$(id --groups --name "$SUPERUSER_NAME")"
  [[ " ${group_names} " == *" ${SUPERUSER_GROUP} "* ]]
}

@test "grants full rights without a password" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Granting full rights without a password in ${SUDOERS_FILE}"* ]]
  assert_has_line "${SUPERUSER_NAME} ALL=(ALL:ALL) NOPASSWD:ALL" "$SUDOERS_FILE"
  [ "$(stat --format='%a' "$SUDOERS_FILE")" = '440' ]
  # Настройка sudo должна быть синтаксически верной.
  run visudo --check --quiet --file "$SUDOERS_FILE"
  [ "$status" -eq 0 ]
  # Полные права без пароля: sudo от имени суперпользователя не спрашивает пароль.
  run runuser --user "$SUPERUSER_NAME" -- sudo --non-interactive true
  [ "$status" -eq 0 ]
}

@test "generates an ed25519 SSH key without a passphrase" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Generating an ed25519 SSH key without a passphrase"* ]]
  [ -f "$SUPERUSER_KEY_FILE" ]
  # Ключ ed25519 и без пароля: ssh-keygen -y читает его, не спрашивая пароль.
  run ssh-keygen -y -f "$SUPERUSER_KEY_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == ssh-ed25519* ]]
  [ "$(stat --format='%a' "${SUPERUSER_HOME}/.ssh")" = '700' ]
  [ "$(stat --format='%a' "$SUPERUSER_KEY_FILE")" = '600' ]
  [ "$(stat --format='%U' "$SUPERUSER_KEY_FILE")" = "$SUPERUSER_NAME" ]
}

@test "is idempotent: a second run keeps the user and the SSH key" {
  run_script
  [ "$status" -eq 0 ]
  local uid_after_first
  local key_after_first
  uid_after_first="$(id --user "$SUPERUSER_NAME")"
  key_after_first="$(sha256sum "$SUPERUSER_KEY_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  [[ "$output" == *"already has the SSH key"* ]]
  [[ "$output" == *"already authorized"* ]]
  [ "$(id --user "$SUPERUSER_NAME")" = "$uid_after_first" ]
  [ "$(sha256sum "$SUPERUSER_KEY_FILE")" = "$key_after_first" ]
  # Публичный ключ добавлен один раз, а не при каждом запуске.
  [ "$(wc --lines < "$SUPERUSER_AUTHORIZED_KEYS_FILE")" -eq 1 ]
}

@test "authorizes the key so the superuser can log in" {
  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"Authorizing the key in ${SUPERUSER_AUTHORIZED_KEYS_FILE}"* ]]
  # В authorized_keys попадает именно публичный ключ сгенерированного ключа:
  # по нему суперпользователь входит, хотя вход по паролю запрещён.
  assert_has_line "$(< "${SUPERUSER_KEY_FILE}.pub")" "$SUPERUSER_AUTHORIZED_KEYS_FILE"
  [ "$(stat --format='%a' "$SUPERUSER_AUTHORIZED_KEYS_FILE")" = '600' ]
  [ "$(stat --format='%U' "$SUPERUSER_AUTHORIZED_KEYS_FILE")" = "$SUPERUSER_NAME" ]
}

@test "keeps an existing SSH key and shows its QR code" {
  useradd --create-home --shell "$SUPERUSER_SHELL" "$SUPERUSER_NAME"
  install --directory --mode 0700 --owner "$SUPERUSER_NAME" --group "$SUPERUSER_NAME" "${SUPERUSER_HOME}/.ssh"
  ssh-keygen -t ed25519 -N '' -C keep@test -f "$SUPERUSER_KEY_FILE" -q
  chown "${SUPERUSER_NAME}:${SUPERUSER_NAME}" "$SUPERUSER_KEY_FILE" "${SUPERUSER_KEY_FILE}.pub"
  local key_before
  key_before="$(sha256sum "$SUPERUSER_KEY_FILE")"

  run_script

  [ "$status" -eq 0 ]
  [[ "$output" == *"already has the SSH key"* ]]
  [ "$(sha256sum "$SUPERUSER_KEY_FILE")" = "$key_before" ]
  # Показывается QR-код именно существующего ключа и он же попадает в authorized_keys.
  [[ "$output" == *"$(key_qr_code "$SUPERUSER_KEY_FILE")"* ]]
  assert_has_line "$(< "${SUPERUSER_KEY_FILE}.pub")" "$SUPERUSER_AUTHORIZED_KEYS_FILE"
}

@test "asks again when the user name is invalid" {
  run "$SCRIPT_UNDER_TEST" <<< $'Bad Name\n'"$SUPERUSER_NAME"

  [ "$status" -eq 0 ]
  [[ "$output" == *"is invalid"* ]]
  getent passwd "$SUPERUSER_NAME"
}

@test "asks again when the user name belongs to a system user" {
  # root — UID 0 (ниже REGULAR_USER_UID_MIN), nobody — UID 65534 (выше
  # REGULAR_USER_UID_MAX): обе системные учётные записи
  run "$SCRIPT_UNDER_TEST" <<< $'root\nnobody\n'"$SUPERUSER_NAME"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the user name "*"root"*"belongs to a system user"* ]]
  [[ "$output" == *"the user name "*"nobody"*"belongs to a system user"* ]]

  # Системные учётные записи не трогаются: им не выдают ни прав sudo, ни ключа,
  # а введённое следом имя принимается
  local groups
  groups="$(id --groups --name root)"
  [[ " ${groups} " != *" ${SUPERUSER_GROUP} "* ]]
  groups="$(id --groups --name nobody)"
  [[ " ${groups} " != *" ${SUPERUSER_GROUP} "* ]]
  [ ! -e /root/.ssh/id_ed25519 ]
  [ ! -e /nonexistent/.ssh ]
  assert_has_line "${SUPERUSER_NAME} ALL=(ALL:ALL) NOPASSWD:ALL" "$SUDOERS_FILE"
  getent passwd "$SUPERUSER_NAME"
}

@test "shows the existing regular users so the name can be chosen" {
  useradd --create-home --shell "$SUPERUSER_SHELL" "$SUPERUSER_NAME"

  run_script

  [ "$status" -eq 0 ]
  # Список выводится перед вводом имени: по нему видно имя уже созданного
  # суперпользователя, имя выделено жирным
  local bold=$'\033[1m'
  local reset=$'\033[0m'
  local users_list
  users_list="$(grep '^Existing regular users: ' <<< "$output" || true)"
  [[ "$users_list" == *"${bold}${SUPERUSER_NAME}${reset}"* ]]
  # В списке только обычные пользователи: системные учётные записи не попадают
  [[ "$users_list" != *"root"* ]]
  [[ "$users_list" != *"daemon"* ]]
  [[ "$users_list" != *"nobody"* ]]
}

@test "fails with a clear message when no user name is entered" {
  run "$SCRIPT_UNDER_TEST" < /dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *"no user name was entered"* ]]
  # Пользователь не создаётся.
  run getent passwd "$SUPERUSER_NAME"
  [ "$status" -ne 0 ]
}

@test "fails with a clear message when the sudoers directory is missing" {
  rm --recursive --force -- "$SUDOERS_DIR"

  run_script

  [ "$status" -ne 0 ]
  [[ "$output" == *"$SUDOERS_DIR"* ]]
  # Шаг идёт последним, поэтому уже выполненные шаги на месте: Docker включён.
  assert_has_line 'enable --now docker' "${BATS_TEST_TMPDIR}/systemctl.calls"
  # Каталог проверяется до создания пользователя.
  run getent passwd "$SUPERUSER_NAME"
  [ "$status" -ne 0 ]
}

@test "passes shellcheck" {
  run shellcheck "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
