#!/usr/bin/env bash

# Собирает образы тестового окружения (базовый Debian 13 и образ указанного
# скрипта) и запускает тесты скрипта в контейнере.

set -euo pipefail

readonly IMAGE_REPO="${IMAGE_REPO:-scripts-test}"
readonly BASE_NAME=debian
readonly BASE_IMAGE="${IMAGE_REPO}:${BASE_NAME}"

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTS_DIR
REPO_DIR="$(dirname -- "$TESTS_DIR")"
readonly REPO_DIR

# Имена скриптов, для которых есть тесты (tests/<имя>.bats), без расширения.
available_scripts() {
  local file

  for file in "$TESTS_DIR"/*.bats; do
    [[ -e "$file" ]] || continue
    basename -- "$file" .bats
  done
}

usage() {
  cat <<EOF
Usage: $(basename -- "$0") <script> [bats options]

Собирает базовый образ Debian 13 ($BASE_IMAGE) и образ теста
$IMAGE_REPO:<script>, затем запускает tests/<script>.bats в контейнере
от имени root. Рабочая копия репозитория монтируется в /src только для
чтения, поэтому тесты не могут изменить файлы проекта.

Примеры:
  $(basename -- "$0") amnezia
  $(basename -- "$0") amnezia --filter 'missing'

Доступные скрипты: $(available_scripts | paste --serial --delimiters ' ')

Переменные окружения:
  IMAGE_REPO   репозиторий образов (по умолчанию: $IMAGE_REPO)
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  '')
    usage >&2
    exit 2
    ;;
esac

readonly SCRIPT="$1"
shift

[[ -f "$TESTS_DIR/$SCRIPT.bats" ]] \
  || die "нет тестов для скрипта '$SCRIPT' (ожидается $TESTS_DIR/$SCRIPT.bats); доступны: $(available_scripts | paste --serial --delimiters ' ')"
[[ -f "$TESTS_DIR/$SCRIPT.Dockerfile" ]] \
  || die "нет образа для скрипта '$SCRIPT' (ожидается $TESTS_DIR/$SCRIPT.Dockerfile)"

docker build --tag "$BASE_IMAGE" --file "$TESTS_DIR/$BASE_NAME.Dockerfile" "$TESTS_DIR"

docker build \
  --tag "$IMAGE_REPO:$SCRIPT" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --file "$TESTS_DIR/$SCRIPT.Dockerfile" \
  "$TESTS_DIR"

docker run --rm \
  --volume "$REPO_DIR:/src:ro" \
  --workdir /src \
  "$IMAGE_REPO:$SCRIPT" \
  bats --print-output-on-failure "$@" "/src/tests/$SCRIPT.bats"
