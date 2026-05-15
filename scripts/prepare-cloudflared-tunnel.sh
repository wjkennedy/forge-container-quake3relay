#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

CLOUDFLARED_TUNNEL_NAME="${CLOUDFLARED_TUNNEL_NAME:-q3-websocket}"
CLOUDFLARED_PUBLIC_HOSTNAME="${CLOUDFLARED_PUBLIC_HOSTNAME:-q3a.a9group.net}"
CLOUDFLARED_ORIGIN_URL="${CLOUDFLARED_ORIGIN_URL:-http://q3-relay:8080}"
CLOUDFLARED_CREDENTIALS_DIR="${CLOUDFLARED_CREDENTIALS_DIR:-$HOME/.cloudflared}"
CLOUDFLARED_RUNTIME_DIR="${CLOUDFLARED_RUNTIME_DIR:-$ROOT_DIR/.cloudflared}"
CLOUDFLARED_TOKEN_REFRESH="${CLOUDFLARED_TOKEN_REFRESH:-auto}"
CLOUDFLARED_ROUTE_DNS="${CLOUDFLARED_ROUTE_DNS:-auto}"
CLOUDFLARED_ROUTE_DNS_OVERWRITE="${CLOUDFLARED_ROUTE_DNS_OVERWRITE:-true}"
CLOUDFLARED_TUNNEL_MODE="${TUNNEL_MODE:-${CLOUDFLARED_TUNNEL_MODE:-auto}}"
CLOUDFLARED_TUNNEL_ID="${CLOUDFLARED_TUNNEL_ID:-}"
CLOUDFLARED_ORIGIN_CERT="${CLOUDFLARED_ORIGIN_CERT:-$CLOUDFLARED_CREDENTIALS_DIR/cert.pem}"
CLOUDFLARED_RUNTIME_CONFIG="${CLOUDFLARED_RUNTIME_DIR}/config.yml"
CLOUDFLARED_RUNTIME_CREDENTIALS="${CLOUDFLARED_RUNTIME_DIR}/credentials.json"
CLOUDFLARED_RUNTIME_TOKEN_FILE="${CLOUDFLARED_RUNTIME_DIR}/token.txt"
CLOUDFLARED_RUNTIME_ENV="${CLOUDFLARED_RUNTIME_DIR}/runtime.env"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to prepare the Cloudflare tunnel runtime files." >&2
  exit 1
fi

mkdir -p "${CLOUDFLARED_RUNTIME_DIR}"

resolved_tunnel_id=""
resolved_tunnel_name=""
resolved_tunnel_ref=""
credentials_source_file="${CLOUDFLARED_CREDENTIALS_FILE:-}"
credentials_tunnel_id=""
credentials_account_tag=""
credentials_secret=""
effective_token="${CLOUDFLARED_TOKEN:-}"
lookup_failed_reason=""

lookup_tunnel_by_name() {
  if ! command -v cloudflared >/dev/null 2>&1; then
    lookup_failed_reason="cloudflared CLI is not installed"
    return 1
  fi

  if [[ ! -f "${CLOUDFLARED_ORIGIN_CERT}" ]]; then
    lookup_failed_reason="origin certificate is missing at ${CLOUDFLARED_ORIGIN_CERT}"
    return 1
  fi

  local tunnel_json
  if ! tunnel_json="$(cloudflared --origincert "${CLOUDFLARED_ORIGIN_CERT}" tunnel list --output json --name "${CLOUDFLARED_TUNNEL_NAME}" 2>/dev/null)"; then
    lookup_failed_reason="cloudflared tunnel list failed with the current origin certificate"
    return 1
  fi

  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"${tunnel_json}"; then
    lookup_failed_reason="cloudflared tunnel list did not return JSON"
    return 1
  fi

  local count
  count="$(jq 'if type == "array" then length else 0 end' <<<"${tunnel_json}")"
  if [[ "${count}" != "1" ]]; then
    lookup_failed_reason="expected one tunnel named ${CLOUDFLARED_TUNNEL_NAME}, got ${count}"
    return 1
  fi

  resolved_tunnel_id="$(jq -r '.[0].id // .[0].uuid // .[0].ID // empty' <<<"${tunnel_json}")"
  resolved_tunnel_name="$(jq -r '.[0].name // .[0].Name // empty' <<<"${tunnel_json}")"

  [[ -n "${resolved_tunnel_id}" ]]
}

load_credentials_file() {
  local file_path="$1"

  if [[ ! -f "${file_path}" ]]; then
    echo "Cloudflare tunnel credentials file not found: ${file_path}" >&2
    exit 1
  fi

  credentials_tunnel_id="$(jq -r '.TunnelID // empty' "${file_path}")"
  credentials_account_tag="$(jq -r '.AccountTag // empty' "${file_path}")"
  credentials_secret="$(jq -r '.TunnelSecret // empty' "${file_path}")"

  if [[ -z "${credentials_tunnel_id}" || -z "${credentials_account_tag}" || -z "${credentials_secret}" ]]; then
    echo "Invalid Cloudflare tunnel credentials JSON: ${file_path}" >&2
    echo "Expected TunnelID, AccountTag, and TunnelSecret." >&2
    exit 1
  fi

  credentials_source_file="${file_path}"
}

resolve_credentials_file() {
  if [[ -n "${credentials_source_file}" ]]; then
    load_credentials_file "${credentials_source_file}"
    return
  fi

  if [[ -n "${resolved_tunnel_id}" && -f "${CLOUDFLARED_CREDENTIALS_DIR}/${resolved_tunnel_id}.json" ]]; then
    load_credentials_file "${CLOUDFLARED_CREDENTIALS_DIR}/${resolved_tunnel_id}.json"
    return
  fi

  local candidate_files=()
  local file
  shopt -s nullglob
  for file in "${CLOUDFLARED_CREDENTIALS_DIR}"/*.json; do
    candidate_files+=("${file}")
  done
  shopt -u nullglob

  if [[ ${#candidate_files[@]} -eq 0 ]]; then
    echo "No Cloudflare tunnel credentials JSON files found in ${CLOUDFLARED_CREDENTIALS_DIR}." >&2
    exit 1
  fi

  if [[ -n "${resolved_tunnel_id}" ]]; then
    for file in "${candidate_files[@]}"; do
      if [[ "$(jq -r '.TunnelID // empty' "${file}")" == "${resolved_tunnel_id}" ]]; then
        load_credentials_file "${file}"
        return
      fi
    done

    echo "No credentials JSON matched tunnel ${CLOUDFLARED_TUNNEL_NAME} (${resolved_tunnel_id})." >&2
    exit 1
  fi

  if [[ ${#candidate_files[@]} -ne 1 ]]; then
    echo "Multiple Cloudflare credentials JSON files found in ${CLOUDFLARED_CREDENTIALS_DIR}." >&2
    echo "Set CLOUDFLARED_CREDENTIALS_FILE or ensure cloudflared tunnel name lookup works." >&2
    exit 1
  fi

  load_credentials_file "${candidate_files[0]}"
}

refresh_token_by_name() {
  if ! command -v cloudflared >/dev/null 2>&1; then
    return 1
  fi

  if [[ ! -f "${CLOUDFLARED_ORIGIN_CERT}" ]]; then
    return 1
  fi

  local refreshed_token
  if ! refreshed_token="$(cloudflared --origincert "${CLOUDFLARED_ORIGIN_CERT}" tunnel token "${CLOUDFLARED_TUNNEL_NAME}" 2>/dev/null)"; then
    return 1
  fi

  refreshed_token="$(printf '%s' "${refreshed_token}" | tr -d '\r\n')"
  if [[ -z "${refreshed_token}" ]]; then
    return 1
  fi

  effective_token="${refreshed_token}"
}

route_dns_hostname() {
  if ! command -v cloudflared >/dev/null 2>&1; then
    return 1
  fi

  if [[ ! -f "${CLOUDFLARED_ORIGIN_CERT}" ]]; then
    return 1
  fi

  if [[ -z "${resolved_tunnel_name}" ]]; then
    return 1
  fi

  local route_args=(
    --origincert "${CLOUDFLARED_ORIGIN_CERT}"
    tunnel
    route
    dns
  )

  if [[ "${CLOUDFLARED_ROUTE_DNS_OVERWRITE}" == "true" || "${CLOUDFLARED_ROUTE_DNS_OVERWRITE}" == "1" ]]; then
    route_args+=(--overwrite-dns)
  fi

  route_args+=("${resolved_tunnel_name}" "${CLOUDFLARED_PUBLIC_HOSTNAME}")
  cloudflared "${route_args[@]}"
}

case "${CLOUDFLARED_TUNNEL_MODE}" in
  auto|local-managed|token)
    ;;
  *)
    echo "Unsupported tunnel mode: ${CLOUDFLARED_TUNNEL_MODE}. Use auto, local-managed, or token." >&2
    exit 1
    ;;
esac

case "${CLOUDFLARED_ROUTE_DNS}" in
  auto|always|never)
    ;;
  *)
    echo "Unsupported CLOUDFLARED_ROUTE_DNS: ${CLOUDFLARED_ROUTE_DNS}. Use auto, always, or never." >&2
    exit 1
    ;;
esac

lookup_tunnel_by_name || true

if [[ -n "${CLOUDFLARED_TUNNEL_ID}" ]]; then
  resolved_tunnel_id="${CLOUDFLARED_TUNNEL_ID}"
fi
need_credentials_validation=false

case "${CLOUDFLARED_TUNNEL_MODE}" in
  local-managed)
    need_credentials_validation=true
    ;;
  auto)
    if [[ -n "${CLOUDFLARED_CREDENTIALS_FILE:-}" ]]; then
      need_credentials_validation=true
    elif compgen -G "${CLOUDFLARED_CREDENTIALS_DIR}/*.json" >/dev/null 2>&1; then
      need_credentials_validation=true
    fi
    ;;
  token)
    ;;
esac

if [[ "${need_credentials_validation}" == "true" ]]; then
  if [[ "${CLOUDFLARED_TUNNEL_MODE}" == "auto" && -z "${resolved_tunnel_id}" ]]; then
    echo "Auto mode found local Cloudflare credentials, but could not resolve the current tunnel ID for ${CLOUDFLARED_TUNNEL_NAME}." >&2
    if [[ -n "${lookup_failed_reason}" ]]; then
      echo "Reason: ${lookup_failed_reason}" >&2
    fi
    echo "Refusing to fall back to an unverified credentials JSON." >&2
    echo "Set CLOUDFLARED_TUNNEL_ID=${CLOUDFLARED_TUNNEL_ID:-<current-tunnel-id>} explicitly, re-run 'cloudflared tunnel login', or point CLOUDFLARED_CREDENTIALS_FILE at the current tunnel credentials JSON." >&2
    exit 1
  fi

  resolve_credentials_file

  if [[ -n "${resolved_tunnel_id}" && "${credentials_tunnel_id}" != "${resolved_tunnel_id}" ]]; then
    echo "Credentials JSON does not match tunnel ${CLOUDFLARED_TUNNEL_NAME}." >&2
    echo "Resolved tunnel ID: ${resolved_tunnel_id}" >&2
    echo "Credentials TunnelID: ${credentials_tunnel_id}" >&2
    exit 1
  fi

  if [[ -z "${resolved_tunnel_id}" ]]; then
    resolved_tunnel_id="${credentials_tunnel_id}"
  fi
fi

if [[ -z "${resolved_tunnel_name}" ]]; then
  resolved_tunnel_name="${CLOUDFLARED_TUNNEL_NAME}"
fi

# Inside the Docker cloudflared container we only mount runtime credentials/token
# files, so prefer the stable tunnel UUID over the display name whenever it is
# available. That avoids an extra name lookup dependency during tunnel startup.
if [[ -n "${resolved_tunnel_id}" ]]; then
  resolved_tunnel_ref="${resolved_tunnel_id}"
else
  resolved_tunnel_ref="${resolved_tunnel_name}"
fi

case "${CLOUDFLARED_TUNNEL_MODE}" in
  auto)
    if [[ "${need_credentials_validation}" == "true" ]]; then
      CLOUDFLARED_TUNNEL_MODE="local-managed"
    else
      CLOUDFLARED_TUNNEL_MODE="token"
    fi

    if [[ "${CLOUDFLARED_TUNNEL_MODE}" == "token" && "${CLOUDFLARED_TOKEN_REFRESH}" != "never" ]]; then
      refresh_token_by_name || true
    fi
    ;;
  token)
    if [[ "${CLOUDFLARED_TOKEN_REFRESH}" != "never" ]]; then
      refresh_token_by_name || true
    fi
    ;;
  local-managed)
    if [[ -z "${resolved_tunnel_id}" ]]; then
      echo "Unable to resolve tunnel ID for ${CLOUDFLARED_TUNNEL_NAME} in local-managed mode." >&2
      if [[ -n "${lookup_failed_reason}" ]]; then
        echo "Reason: ${lookup_failed_reason}" >&2
      fi
      echo "Run 'cloudflared tunnel login' again, provide CLOUDFLARED_TUNNEL_ID explicitly, or point CLOUDFLARED_CREDENTIALS_FILE at the current tunnel credentials JSON." >&2
      exit 1
    fi

    if [[ -n "${credentials_tunnel_id}" && "${credentials_tunnel_id}" != "${resolved_tunnel_id}" ]]; then
      echo "Credentials JSON does not match the expected tunnel." >&2
      echo "Expected tunnel ID:    ${resolved_tunnel_id}" >&2
      echo "Credentials TunnelID: ${credentials_tunnel_id}" >&2
      exit 1
    fi
    ;;
esac

case "${CLOUDFLARED_ROUTE_DNS}" in
  auto)
    route_dns_hostname >/dev/null 2>&1 || true
    ;;
  always)
    echo "Ensuring DNS route ${CLOUDFLARED_PUBLIC_HOSTNAME} -> ${resolved_tunnel_name}..."
    if ! route_dns_hostname; then
      echo "Failed to provision DNS route for ${CLOUDFLARED_PUBLIC_HOSTNAME}." >&2
      echo "Run 'cloudflared tunnel route dns ${resolved_tunnel_name} ${CLOUDFLARED_PUBLIC_HOSTNAME}' manually or fix local cloudflared auth." >&2
      exit 1
    fi
    ;;
  never)
    ;;
esac

if [[ "${CLOUDFLARED_TUNNEL_MODE}" == "token" ]]; then
  effective_token="$(printf '%s' "${effective_token}" | tr -d '[:space:]')"

  if [[ "${effective_token}" =~ [[:space:]] ]]; then
    echo "CLOUDFLARED_TOKEN contains whitespace, which usually means it was pasted incorrectly." >&2
    exit 1
  fi

  if [[ ${#effective_token} -lt 40 ]]; then
    echo "No valid Cloudflare token available for tunnel ${CLOUDFLARED_TUNNEL_NAME}." >&2
    echo "Set CLOUDFLARED_TOKEN or allow token refresh through cloudflared + cert.pem." >&2
    exit 1
  fi
fi

if [[ -n "${credentials_source_file}" ]]; then
  cp "${credentials_source_file}" "${CLOUDFLARED_RUNTIME_CREDENTIALS}"
  chmod 600 "${CLOUDFLARED_RUNTIME_CREDENTIALS}"
fi

cat > "${CLOUDFLARED_RUNTIME_CONFIG}" <<EOF
tunnel: ${resolved_tunnel_ref}
credentials-file: /etc/cloudflared/credentials.json
protocol: http2

ingress:
  - hostname: ${CLOUDFLARED_PUBLIC_HOSTNAME}
    service: ${CLOUDFLARED_ORIGIN_URL}
  - service: http_status:404
EOF
chmod 600 "${CLOUDFLARED_RUNTIME_CONFIG}"

if [[ -n "${effective_token}" ]]; then
  printf '%s' "${effective_token}" > "${CLOUDFLARED_RUNTIME_TOKEN_FILE}"
  chmod 600 "${CLOUDFLARED_RUNTIME_TOKEN_FILE}"
fi

cat > "${CLOUDFLARED_RUNTIME_ENV}" <<EOF
CLOUDFLARED_TUNNEL_MODE=${CLOUDFLARED_TUNNEL_MODE}
CLOUDFLARED_TUNNEL_NAME=${resolved_tunnel_name}
CLOUDFLARED_TUNNEL_ID=${resolved_tunnel_id}
CLOUDFLARED_TUNNEL_REF=${resolved_tunnel_ref}
CLOUDFLARED_PUBLIC_HOSTNAME=${CLOUDFLARED_PUBLIC_HOSTNAME}
CLOUDFLARED_ORIGIN_URL=${CLOUDFLARED_ORIGIN_URL}
CLOUDFLARED_ROUTE_DNS=${CLOUDFLARED_ROUTE_DNS}
CLOUDFLARED_CREDENTIALS_FILE=${credentials_source_file}
CLOUDFLARED_RUNTIME_CONFIG=${CLOUDFLARED_RUNTIME_CONFIG}
CLOUDFLARED_RUNTIME_CREDENTIALS=${CLOUDFLARED_RUNTIME_CREDENTIALS}
CLOUDFLARED_RUNTIME_TOKEN_FILE=${CLOUDFLARED_RUNTIME_TOKEN_FILE}
CLOUDFLARED_ORIGIN_CERT=${CLOUDFLARED_ORIGIN_CERT}
EOF
chmod 600 "${CLOUDFLARED_RUNTIME_ENV}"

echo "Prepared Cloudflare tunnel runtime files."
echo "  mode:        ${CLOUDFLARED_TUNNEL_MODE}"
echo "  tunnel name: ${resolved_tunnel_name}"
echo "  tunnel id:   ${resolved_tunnel_id}"
echo "  config ref:  ${resolved_tunnel_ref}"
if [[ -n "${credentials_source_file}" ]]; then
  echo "  credentials: ${credentials_source_file}"
fi
echo "  config:      ${CLOUDFLARED_RUNTIME_CONFIG}"
if [[ -n "${effective_token}" ]]; then
  echo "  token file:  ${CLOUDFLARED_RUNTIME_TOKEN_FILE}"
fi
