#!/usr/bin/env bash
set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly PRODUCT="kkt"
readonly DEFAULT_TARGET="${HOME}/.local/bin/kkt"
readonly TARGET="${1-$DEFAULT_TARGET}"
readonly INSTALL_MODE="755"
readonly USAGE="사용법: scripts/install.sh [설치할 실행 파일 경로]"
readonly INSTALLED_MESSAGE="설치 경로:"
readonly DOCTOR_HINT="권한과 환경을 확인하세요 (kkt doctor):"
readonly SYMLINK_MESSAGE="기본 설치 경로가 심볼릭 링크입니다. 설치할 경로를 명시하세요."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/kkt-clang-module-cache}"

if [[ $# -gt 1 || -z "$TARGET" || -d "$TARGET" ]]; then
    printf '%s\n' "$USAGE" >&2
    exit 1
fi
if [[ $# -eq 0 && -L "$TARGET" ]]; then
    printf '%s\n' "$SYMLINK_MESSAGE" >&2
    exit 1
fi

cd "$REPO_DIR"
if ! swift build -c release --product "$PRODUCT"; then
    if ! swift build -c release --product "$PRODUCT" --build-system native; then
        swift build -c release --product "$PRODUCT" --build-system native --disable-sandbox
    fi
fi

mkdir -p "$(dirname "$TARGET")"
install -m "$INSTALL_MODE" ".build/release/$PRODUCT" "$TARGET"
printf '%s %s\n' "$INSTALLED_MESSAGE" "$TARGET"
printf '%s "%s" doctor\n' "$DOCTOR_HINT" "$TARGET"
