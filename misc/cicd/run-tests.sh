#!/usr/bin/env sh
#
# Unified test execution script (Angular / Spring Boot).
# Usage: ./run-tests.sh <angular|springboot>
# Exit: 0 = success, non-zero = failure
#

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
RESULTS_DIR="${PROJECT_ROOT}/test-results"

usage() {
  echo "Usage: $0 <angular|springboot>"
  echo "  angular  -  Run Angular (Karma/Jasmine) tests"
  echo "  springboot - Run Spring Boot tests"
  echo "  output as JUnit XML to test-results/ "
  exit 1
}

clean_test_artifacts() {
  echo "[run-tests] Cleaning previous test artifacts..."
  rm -rf "${RESULTS_DIR:?}"
  mkdir -p "${RESULTS_DIR}"
}

# --- Angular: Karma + JUnit XML report ---
run_angular_tests() {
  cd "${PROJECT_ROOT}"
  echo "[run-tests] intall dependencies..."
  npm ci
  echo "[run-tests] Running Angular tests..."
  if ! npm test; then
    return 1
  fi
  return 0
}

# --- Spring Boot: placeholder for future implementation ---
run_spring_boot_tests() {
  cd "${PROJECT_ROOT}"
  echo "[run-tests] Running Spring Boot tests..."
  if ! ./gradlew test; then
    return 1
  fi
  if [ -d "${PROJECT_ROOT}/build/test-results/test" ]; then
    cp -R "${PROJECT_ROOT}/build/test-results/test/." "${RESULTS_DIR}/"
  else
    echo "[run-tests] Warning: Gradle test results not found at build/test-results/test"
  fi
  return 0
}

# --- Main ---
main() {
  [ $# -eq 1 ] || usage

  case "$1" in
    angular)
      clean_test_artifacts
      if run_angular_tests; then
        echo "[run-tests] Angular tests passed. JUnit report in ${RESULTS_DIR}/"
        exit 0
      fi
      echo "[run-tests] Angular tests failed."
      exit 1
      ;;
    springboot)
      clean_test_artifacts
      if run_spring_boot_tests; then
        echo "[run-tests] Spring Boot tests passed. JUnit report in ${RESULTS_DIR}/"
        exit 0
      fi
      echo "[run-tests] Spring Boot tests failed or not implemented."
      exit 1
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
