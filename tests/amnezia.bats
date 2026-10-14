#!/usr/bin/env bats

# Тесты для amnezia.sh.
#
# Запускаются от имени root внутри контейнера Debian 13, в котором установлены
# пакеты console-setup и openssh-server (см. amnezia.Dockerfile и run-tests.sh):
# скрипт читает /etc/os-release, правит реальный /etc/default/console-setup,
# вызывает setupcon и пишет настройки sshd в /etc/ssh/sshd_config.d.
#
# Проверяется:
#
# - на системе, отличной от Debian, скрипт завершается с ошибкой, не трогая
#   настройки консоли и часовой пояс;
# - то же самое, если ID системы не определён или нет /etc/os-release;
# - часовой пояс задаётся символической ссылкой /etc/localtime на файл зоны
#   /usr/share/zoneinfo/Asia/Novosibirsk, а в сообщении шага значение часового
#   пояса выделено жирным;
# - повторный запуск ссылку не меняет (идемпотентность);
# - при отсутствии файла зоны скрипт завершается с ошибкой и внятным сообщением,
#   не меняя /etc/localtime;
# - шаг настройки часового пояса идёт до настройки автоматического обновления,
#   поэтому уже выполнен, когда тот завершается ошибкой;
# - настройки sshd записываются в файл ${SSHD_CONFIG_FILE}: вход по паролю и вход
#   пользователем root запрещены, разрешён только вход по ключу;
# - файл дополнительных настроек перекрывает настройки из других файлов каталога
#   (например, 50-cloud-init.conf) — это проверяется по эффективной конфигурации
#   sshd;
# - повторный запуск файл настроек sshd не меняет (идемпотентность);
# - настройки применяются перезагрузкой sshd;
# - при отсутствии каталога /etc/ssh/sshd_config.d скрипт завершается с ошибкой
#   и внятным сообщением;
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
# - параметры ядра из SYSCTL_PARAMS записываются в /etc/sysctl.d/9999-router.conf:
#   нужные строки заменяются на месте, остальное содержимое файла не меняется,
#   повторный запуск файл не меняет;
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
#   в алфавитном порядке;
# - список пакетов в тестовом образе совпадает с APT_PACKAGES в скрипте;
# - скрипт вызывает setupcon;
# - shellcheck не находит замечаний.

SCRIPT_UNDER_TEST="${BATS_TEST_DIRNAME}/../amnezia.sh"
APT_CONF_DIR="/etc/apt/apt.conf.d"
APT_AUTO_UPGRADES_FILE="${APT_CONF_DIR}/20auto-upgrades"
APT_UNATTENDED_UPGRADES_FILE="${APT_CONF_DIR}/50unattended-upgrades"
CONSOLE_SETUP_FILE="/etc/default/console-setup"
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
# Эталонные копии файлов в том виде, в каком их ставит базовый образ и пакеты
# console-setup и unattended-upgrades: setup() восстанавливает из них исходное
# состояние перед каждым сценарием. Сюда же — /etc/localtime и файл зоны
# /usr/share/zoneinfo/Asia/Novosibirsk, которые правит шаг настройки часового
# пояса.
APT_AUTO_UPGRADES_PRISTINE="/usr/share/amnezia-test/20auto-upgrades.pristine"
CONSOLE_SETUP_PRISTINE="/usr/share/amnezia-test/console-setup.pristine"
OS_RELEASE_PRISTINE="/usr/share/amnezia-test/os-release.pristine"
TIME_ZONE_FILE_PRISTINE="/usr/share/amnezia-test/localtime.pristine"
TIME_ZONE_INFO_PRISTINE="/usr/share/amnezia-test/novosibirsk.pristine"
APT_UNATTENDED_UPGRADES_PRISTINE="/usr/share/amnezia-test/50unattended-upgrades.pristine"

setup() {
  mkdir --parents "$APT_CONF_DIR"
  cp -- "$APT_AUTO_UPGRADES_PRISTINE" "$APT_AUTO_UPGRADES_FILE"
  cp -- "$APT_UNATTENDED_UPGRADES_PRISTINE" "$APT_UNATTENDED_UPGRADES_FILE"
  cp -- "$CONSOLE_SETUP_PRISTINE" "$CONSOLE_SETUP_FILE"
  cp -- "$OS_RELEASE_PRISTINE" "$OS_RELEASE_FILE"
  # /etc/localtime — символическая ссылка, поэтому обычный cp записал бы через
  # неё в файл зоны: нужны --remove-destination и --no-dereference.
  cp --remove-destination --no-dereference "$TIME_ZONE_FILE_PRISTINE" "$TIME_ZONE_FILE"
  cp -- "$TIME_ZONE_INFO_PRISTINE" "$TIME_ZONE_INFO_FILE"
  mkdir --parents "$SYSCTL_DIR"
  rm --force -- "$SYSCTL_FILE"
  # Каталог с настройками sshd: скрипт только добавляет в него свой файл,
  # поэтому достаточно очистить каталог от файлов, созданных тестами.
  mkdir --parents "$SSHD_CONFIG_DIR"
  rm --force -- "${SSHD_CONFIG_DIR}"/*.conf
  # Каталог с настройками ufw: скрипт только проверяет его наличие и вызывает
  # команду ufw (заглушённую), поэтому достаточно восстановить каталог.
  mkdir --parents "$UFW_DIR"

  # apt-get, sysctl, systemctl и ufw не выполняются по-настоящему: тесты
  # проверяют не установку пакетов и не применение настроек, а то, как скрипт их
  # запускает. Заглушки записывают вызовы в файлы, чтобы тест мог проверить их
  # состав и порядок.
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  local name
  mkdir --parents "$stub_dir"
  for name in apt-get sysctl systemctl ufw; do
    cat > "${stub_dir}/${name}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${BATS_TEST_TMPDIR}/${name}.calls"
EOF
    chmod +x "${stub_dir}/${name}"
  done
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
      "${BATS_TEST_DIRNAME}/amnezia.Dockerfile" \
    | grep --invert-match --fixed-strings -- '&&' \
    | tr --delete '[:blank:]\\'
}

@test "sets the required values for the three console parameters" {
  write_param CODESET 'CODESET="ASCII-8"'
  write_param FONTFACE 'FONTFACE="LatArCyrHeb-16"'
  write_param FONTSIZE 'FONTSIZE="16x32"'

  run "$SCRIPT_UNDER_TEST"

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

  run "$SCRIPT_UNDER_TEST"

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

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(wc --lines < "$CONSOLE_SETUP_FILE")" -eq "$((lines_before + 3))" ]
}

@test "is idempotent: a second run does not change the file" {
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  local after_first
  after_first="$(sha256sum "$CONSOLE_SETUP_FILE")"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$CONSOLE_SETUP_FILE")" = "$after_first" ]
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"' "$CONSOLE_SETUP_FILE")" -eq 1 ]
}

@test "fails with a clear message when the configuration file is missing" {
  rm -- "$CONSOLE_SETUP_FILE"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"$CONSOLE_SETUP_FILE"* ]]
}

@test "fails on a system that is not Debian" {
  printf 'ID=ubuntu\n' > "$OS_RELEASE_FILE"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"the current system is ubuntu"* ]]
  # Настройка консоли не выполняется: проверка ОС идёт первой.
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
  # Часовой пояс тоже не меняется: его шаг идёт сразу после проверки ОС.
  assert_symlink_target "$TIME_ZONE_FILE" "${TIME_ZONE_DIR}/Etc/UTC"
}

@test "fails when the system ID cannot be determined" {
  printf 'NAME="Some OS"\n' > "$OS_RELEASE_FILE"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"the current system is unknown"* ]]
  # Настройка консоли не выполняется: проверка ОС идёт первой.
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
}

@test "fails when the OS release file is missing" {
  rm -- "$OS_RELEASE_FILE"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot detect the operating system"* ]]
  assert_has_line 'CODESET="guess"' "$CONSOLE_SETUP_FILE"
}

@test "sets the time zone to Asia/Novosibirsk" {
  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  # Значение часового пояса выводится выделенным (жирным).
  local bold=$'\033[1m'
  local reset=$'\033[0m'
  [[ "$output" == *"Setting the time zone to ${bold}${TIME_ZONE}${reset} in ${TIME_ZONE_FILE}"* ]]
  assert_symlink_target "$TIME_ZONE_FILE" "$TIME_ZONE_INFO_FILE"
}

@test "is idempotent for the time zone: a second run does not change the link" {
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  local target_after_first
  target_after_first="$(readlink -- "$TIME_ZONE_FILE")"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  assert_symlink_target "$TIME_ZONE_FILE" "$target_after_first"
}

@test "fails with a clear message when the time zone data is missing" {
  rm -- "$TIME_ZONE_INFO_FILE"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"$TIME_ZONE_INFO_FILE"* ]]
  # Файл зоны проверяется до правки ссылки, поэтому /etc/localtime не тронут.
  assert_symlink_target "$TIME_ZONE_FILE" "${TIME_ZONE_DIR}/Etc/UTC"
}

@test "writes the SSH settings into a drop-in file and they take effect" {
  run "$SCRIPT_UNDER_TEST"

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

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  local effective
  effective="$(sshd -T)"
  [[ "$effective" == *$'\npermitrootlogin no'* ]]
  [[ "$effective" == *$'\npasswordauthentication no'* ]]
}

@test "is idempotent for the SSH settings: a second run does not change the file" {
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  local after_first
  after_first="$(sha256sum "$SSHD_CONFIG_FILE")"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$SSHD_CONFIG_FILE")" = "$after_first" ]
}

@test "applies the SSH settings by reloading sshd" {
  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/systemctl.calls")" = "reload ssh" ]
}

@test "fails with a clear message when the sshd configuration directory is missing" {
  rm --recursive --force -- "$SSHD_CONFIG_DIR"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"$SSHD_CONFIG_DIR"* ]]
  # Шаг идёт после настройки консоли, поэтому она уже выполнена.
  assert_has_line 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE"
}

@test "leaves only ssh open for incoming connections and allows all outgoing ones" {
  run "$SCRIPT_UNDER_TEST"

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
  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  # Транзитный трафик клиентов VPN должен проходить: политика по умолчанию для
  # перенаправляемых соединений — allow.
  assert_has_line 'default allow routed' "${BATS_TEST_TMPDIR}/ufw.calls"
}

@test "applies the firewall rules again on a second run without changing them" {
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  local first_run
  first_run="$(cat "${BATS_TEST_TMPDIR}/ufw.calls")"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  # Скрипт каждый раз задаёт одни и те же правила, поэтому повторный запуск
  # безопасен: ssh остаётся разрешён.
  [ "$(cat "${BATS_TEST_TMPDIR}/ufw.calls")" = "${first_run}"$'\n'"${first_run}" ]
}

@test "fails with a clear message when the ufw configuration directory is missing" {
  rm --recursive --force -- "$UFW_DIR"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"$UFW_DIR"* ]]
  # Шаг идёт после настройки SSH, поэтому она уже выполнена.
  assert_has_line 'PasswordAuthentication no' "$SSHD_CONFIG_FILE"
  # Каталог проверяется до вызовов ufw, поэтому брандмауэр не настраивается.
  [ ! -f "${BATS_TEST_TMPDIR}/ufw.calls" ]
}

@test "updates the package database and installs the packages in alphabetical order" {
  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  # Сначала обновляется база пакетов, затем ставятся пакеты в алфавитном
  # порядке; ничего лишнего не вызывается.
  [ "$(cat "${BATS_TEST_TMPDIR}/apt-get.calls")" \
      = $'update\ninstall --yes console-setup curl openssh-server ufw unattended-upgrades' ]
}

@test "writes the kernel parameters for the router role" {
  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updating ${SYSCTL_FILE}"* ]]
  assert_has_line 'net.core.default_qdisc = fq' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.ip_forward = 1' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.tcp_congestion_control = bbr' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.tcp_keepalive_probes = 1' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.tcp_mtu_probing = 1' "$SYSCTL_FILE"
  assert_has_line 'net.ipv6.conf.all.disable_ipv6 = 1' "$SYSCTL_FILE"
  # Записаны только заданные параметры, по одному в строке.
  [ "$(wc --lines < "$SYSCTL_FILE")" -eq 6 ]
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

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  # Строки с нашими ключами заменены на месте, в том числе закомментированная.
  assert_has_line 'net.ipv4.tcp_congestion_control = bbr' "$SYSCTL_FILE"
  assert_has_line 'net.ipv4.ip_forward = 1' "$SYSCTL_FILE"
  [ "$(count_exact_lines 'net.ipv4.tcp_congestion_control = bbr' "$SYSCTL_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'net.ipv4.ip_forward = 1' "$SYSCTL_FILE")" -eq 1 ]
  # Чужие строки не тронуты, остальные наши параметры добавлены в конец файла.
  assert_has_line '# Local notes' "$SYSCTL_FILE"
  assert_has_line 'vm.swappiness = 10' "$SYSCTL_FILE"
  [ "$(wc --lines < "$SYSCTL_FILE")" -eq "$((lines_before + 4))" ]
}

@test "is idempotent for the kernel parameters file: a second run does not change it" {
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  local after_first
  after_first="$(sha256sum "$SYSCTL_FILE")"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$SYSCTL_FILE")" = "$after_first" ]
}

@test "applies the kernel parameters by running sysctl --load" {
  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/sysctl.calls")" = "--load=${SYSCTL_FILE}" ]
}

@test "fails with a clear message when the kernel parameters directory is missing" {
  rm --recursive --force -- "$SYSCTL_DIR"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"$SYSCTL_DIR"* ]]
  # Шаг идёт после настройки консоли, поэтому она уже выполнена.
  assert_has_line 'CODESET="FullCyrSlav"' "$CONSOLE_SETUP_FILE"
}

@test "enables upgrades, removal of unused packages and a reboot at 05:00" {
  run "$SCRIPT_UNDER_TEST"

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

  run "$SCRIPT_UNDER_TEST"

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

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  assert_has_line 'APT::Periodic::Unattended-Upgrade "1";' "$APT_AUTO_UPGRADES_FILE"
  assert_has_line 'Unattended-Upgrade::Automatic-Reboot-Time "05:00";' "$APT_UNATTENDED_UPGRADES_FILE"
  [ "$(count_exact_lines 'APT::Periodic::Unattended-Upgrade "1";' "$APT_AUTO_UPGRADES_FILE")" -eq 1 ]
  [ "$(count_exact_lines 'Unattended-Upgrade::Automatic-Reboot-Time "05:00";' "$APT_UNATTENDED_UPGRADES_FILE")" -eq 1 ]
}

@test "is idempotent for the automatic upgrade files: a second run does not change them" {
  run "$SCRIPT_UNDER_TEST"
  [ "$status" -eq 0 ]
  local auto_upgrades_after
  local unattended_upgrades_after
  auto_upgrades_after="$(sha256sum "$APT_AUTO_UPGRADES_FILE")"
  unattended_upgrades_after="$(sha256sum "$APT_UNATTENDED_UPGRADES_FILE")"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(sha256sum "$APT_AUTO_UPGRADES_FILE")" = "$auto_upgrades_after" ]
  [ "$(sha256sum "$APT_UNATTENDED_UPGRADES_FILE")" = "$unattended_upgrades_after" ]
}

@test "fails with a clear message when the apt configuration directory is missing" {
  rm --recursive --force -- "$APT_CONF_DIR"

  run "$SCRIPT_UNDER_TEST"

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

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ -f "${BATS_TEST_TMPDIR}/setupcon.called" ]
}

@test "passes shellcheck" {
  run shellcheck "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
