#!/usr/bin/env bash

detect_node22_bin() {
  local candidate

  if [[ -n "${NODE22_BIN:-}" ]]; then
    candidate="${NODE22_BIN}"
  else
    for candidate in \
      "/opt/homebrew/opt/node@22/bin" \
      "/usr/local/opt/node@22/bin"; do
      if [[ -x "${candidate}/node" ]]; then
        break
      fi
    done

    if [[ ! -x "${candidate:-}/node" ]] && command -v node >/dev/null 2>&1; then
      candidate="$(dirname "$(command -v node)")"
    fi
  fi

  if [[ ! -x "${candidate:-}/node" ]] ||
    [[ "$("${candidate}/node" --version)" != v22.* ]]; then
    echo "Node.js 22 was not found. Set NODE22_BIN to its bin directory." >&2
    return 1
  fi

  NODE22_BIN="${candidate}"
  export NODE22_BIN
  export PATH="${NODE22_BIN}:${PATH}"
}

detect_container_platform() {
  if [[ -n "${CONTAINER_PLATFORM:-}" ]]; then
    export CONTAINER_PLATFORM
    return
  fi

  case "$(uname -m)" in
    arm64 | aarch64)
      CONTAINER_PLATFORM="linux/arm64"
      ;;
    x86_64 | amd64)
      CONTAINER_PLATFORM="linux/amd64"
      ;;
    *)
      echo "Unsupported host architecture: $(uname -m). Set CONTAINER_PLATFORM explicitly." >&2
      return 1
      ;;
  esac

  export CONTAINER_PLATFORM
}

detect_node22_bin
detect_container_platform
