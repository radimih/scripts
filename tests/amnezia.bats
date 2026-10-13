#!/usr/bin/env bats

# Тесты для amnezia.sh.
#
# Запускаются от имени root внутри контейнера Debian 13, в котором установлен
# пакет console-setup (см. amnezia.Dockerfile и run-tests.sh): скрипт читает
# /etc/os-release, правит реальный /etc/default/console-setup и вызывает setupcon.
#
# Проверяется:
#
# - на системе, отличной от Debian, скрипт завершается с ошибкой и не трогает
#   настройки консоли;
# - то же самое, если ID системы не определён или нет /etc/os-release;
# - параметры CODESET, FONTFACE и FONTSIZE получают нужные значения;
# - закомментированные параметры заменяются на месте, без дубликатов;
# - отсутствующие параметры добавляются в конец файла;
# - повторный запуск не меняет файл (идемпотентность);
# - при отсутствии /etc/default/console-setup скрипт завершается с ошибкой
#   и внятным сообщением;
# - перед установкой пакетов обновляется база пакетов, а сами пакеты ставятся
#   в алфавитном порядке;
# - список пакетов в тестовом образе совпадает с APT_PACKAGES в скрипте;
# - скрипт вызывает setupcon;
# - shellcheck не находит замечаний.

SCRIPT_UNDER_TEST="${BATS_TEST_DIRNAME}/../amnezia.sh"
CONSOLE_SETUP_FILE="/etc/default/console-setup"
OS_RELEASE_FILE="/etc/os-release"
# Эталонные копии файлов в том виде, в каком их ставит базовый образ и пакет
# console-setup: setup() восстанавливает из них исходное состояние перед каждым
# сценарием.
CONSOLE_SETUP_PRISTINE="/usr/share/amnezia-test/console-setup.pristine"
OS_RELEASE_PRISTINE="/usr/share/amnezia-test/os-release.pristine"

setup() {
  cp -- "$CONSOLE_SETUP_PRISTINE" "$CONSOLE_SETUP_FILE"
  cp -- "$OS_RELEASE_PRISTINE" "$OS_RELEASE_FILE"

  # apt-get не выполняется по-настоящему: тесты проверяют не установку пакетов,
  # а то, как скрипт её запускает. Заглушка записывает вызовы в файл, чтобы тест
  # мог проверить их состав и порядок.
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir --parents "$stub_dir"
  cat > "${stub_dir}/apt-get" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${BATS_TEST_TMPDIR}/apt-get.calls"
EOF
  chmod +x "${stub_dir}/apt-get"
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

# Число строк файла, целиком совпадающих с ожидаемой строкой; при отсутствии
# совпадений возвращает 0, а не ошибку.
count_exact_lines() {
  grep --fixed-strings --line-regexp --count -- "$1" "$CONSOLE_SETUP_FILE" || true
}

# Проверяет, что в файле есть строка, целиком совпадающая с ожидаемой.
assert_has_line() {
  grep --fixed-strings --line-regexp --quiet -- "$1" "$CONSOLE_SETUP_FILE"
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
  assert_has_line 'CODESET="FullCyrSlav"'
  assert_has_line 'FONTFACE="Terminus"'
  assert_has_line 'FONTSIZE="8x16"'

  # Остальные настройки пакета не затронуты, включая закомментированный
  # пример FONT= (ключ FONT — префикс ключа FONTFACE).
  assert_has_line 'ACTIVE_CONSOLES="/dev/tty[1-6]"'
  assert_has_line 'CHARMAP="UTF-8"'
  assert_has_line 'VIDEOMODE='
  assert_has_line "# FONT='lat9w-08.psf.gz brl-8x8.psf'"
}

@test "replaces commented-out parameters in place without duplicating them" {
  comment_out_param CODESET 'CODESET="guess"'
  comment_out_param FONTFACE 'FONTFACE="Fixed"'
  comment_out_param FONTSIZE 'FONTSIZE="8x16"'
  local lines_before
  lines_before="$(wc --lines < "$CONSOLE_SETUP_FILE")"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"')" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"')" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"')" -eq 1 ]
  [ "$(count_exact_lines '# CODESET="guess"')" -eq 0 ]
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
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"')" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"')" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"')" -eq 1 ]
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
  [ "$(count_exact_lines 'CODESET="FullCyrSlav"')" -eq 1 ]
  [ "$(count_exact_lines 'FONTFACE="Terminus"')" -eq 1 ]
  [ "$(count_exact_lines 'FONTSIZE="8x16"')" -eq 1 ]
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
  assert_has_line 'CODESET="guess"'
}

@test "fails when the system ID cannot be determined" {
  printf 'NAME="Some OS"\n' > "$OS_RELEASE_FILE"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"the current system is unknown"* ]]
  # Настройка консоли не выполняется: проверка ОС идёт первой.
  assert_has_line 'CODESET="guess"'
}

@test "fails when the OS release file is missing" {
  rm -- "$OS_RELEASE_FILE"

  run "$SCRIPT_UNDER_TEST"

  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot detect the operating system"* ]]
  assert_has_line 'CODESET="guess"'
}

@test "updates the package database and installs the packages in alphabetical order" {
  run "$SCRIPT_UNDER_TEST"

  [ "$status" -eq 0 ]
  # Сначала обновляется база пакетов, затем ставятся пакеты в алфавитном
  # порядке; ничего лишнего не вызывается.
  [ "$(cat "${BATS_TEST_TMPDIR}/apt-get.calls")" \
      = $'update\ninstall --yes console-setup curl ufw unattended-upgrades' ]
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
