#!/usr/bin/env sh
#
# Unified test execution script (Angular / Spring Boot).
# Usage: ./run-tests.sh <angular|springboot|all>
# Run from project root or set PROJECT_ROOT.
# Exit: 0 = success, non-zero = failure
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
RESULTS_DIR="${PROJECT_ROOT}/test-results"

usage() {
  echo "Usage: $0 <angular|springboot|all>"
  echo "  angular   - Run Angular (Karma/Jasmine) tests"
  echo "  springboot - Run Spring Boot (Gradle) tests"
  echo "  all       - Run both front and back tests"
  exit 1
}

clean_test_artifacts() {
  echo "[run-tests] Cleaning previous test artifacts..."
  rm -rf "${RESULTS_DIR:?}"
  mkdir -p "${RESULTS_DIR}"
}

run_angular_tests() {
  cd "${PROJECT_ROOT}/front" || exit 1
  echo "[run-tests] Installing front dependencies..."
  npm ci
  echo "[run-tests] Running Angular tests..."
  npm test
}

run_spring_boot_tests() {
  cd "${PROJECT_ROOT}/back" || exit 1
  echo "[run-tests] Running Spring Boot tests..."
  ./gradlew test --no-daemon
  GRADLE_EXIT=$?
  if [ -d "${PROJECT_ROOT}/back/build/test-results/test" ]; then
    cp -R "${PROJECT_ROOT}/back/build/test-results/test/." "${RESULTS_DIR}/" 2>/dev/null || true
  fi
  return $GRADLE_EXIT
}

main() {
  [ $# -eq 1 ] || usage

  case "$1" in
    angular)
      clean_test_artifacts
      if run_angular_tests; then
        echo "[run-tests] Angular tests passed."
        exit 0
      fi
      echo "[run-tests] Angular tests failed."
      exit 1
      ;;
    springboot)
      clean_test_artifacts
      if run_spring_boot_tests; then
        echo "[run-tests] Spring Boot tests passed."
        exit 0
      fi
      echo "[run-tests] Spring Boot tests failed."
      exit 1
      ;;
    all)
      clean_test_artifacts
      FAILED=0
      if ! run_spring_boot_tests; then
        FAILED=1
      fi
      if ! run_angular_tests; then
        FAILED=1
      fi
      if [ $FAILED -eq 0 ]; then
        echo "[run-tests] All tests passed."
        exit 0
      fi
      echo "[run-tests] Some tests failed."
      exit 1
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
