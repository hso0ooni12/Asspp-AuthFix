#!/usr/bin/env bash
# Installs a pinned official ipatool release in the Codespace user's home.
# Never asks for, records, or transfers Apple Account credentials.
set -euo pipefail

version="2.7.0"
asset="ipatool-${version}-linux-amd64.tar.gz"
release="https://github.com/majd/ipatool/releases/download/v${version}"
target_dir="${HOME}/.local/bin"
target="${target_dir}/ipatool"

if [[ -x "${target}" ]] && "${target}" --version 2>/dev/null | grep -Fq "${version}"; then
    echo "Official ipatool ${version} already installed."
    exit 0
fi

for command_name in curl tar sha256sum awk install; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing required command: ${command_name}" >&2
        exit 1
    fi
done

temporary_dir="$(mktemp -d)"
trap 'rm -r -- "${temporary_dir}"' EXIT

echo "Downloading official ipatool ${version}..."
curl --fail --location --silent --show-error --retry 3 --max-time 180 \
    "${release}/${asset}" --output "${temporary_dir}/${asset}"
curl --fail --location --silent --show-error --retry 3 --max-time 60 \
    "${release}/${asset}.sha256sum" --output "${temporary_dir}/checksum"

expected="$(awk 'NR == 1 { print $1 }' "${temporary_dir}/checksum")"
if ! [[ "${expected}" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo "Official release checksum is missing or invalid." >&2
    exit 1
fi
actual="$(sha256sum "${temporary_dir}/${asset}" | awk '{ print $1 }')"
if [[ "${actual,,}" != "${expected,,}" ]]; then
    echo "SHA-256 verification failed. Refusing to install." >&2
    exit 1
fi

mkdir -p "${target_dir}"
mkdir -p "${temporary_dir}/unpacked"
tar -xzf "${temporary_dir}/${asset}" -C "${temporary_dir}/unpacked"
binary="$(find "${temporary_dir}/unpacked" -type f \( -name ipatool -o -name 'ipatool-*-linux-amd64' \) -print -quit)"
if [[ -z "${binary}" ]]; then
    echo "Official release archive did not contain ipatool." >&2
    exit 1
fi
install -m 0755 "${binary}" "${target}"
echo "Verified and installed: ${target}"
