#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/plain-host-ovh-common.sh"

usage() {
	cat <<'EOF_USAGE'
Usage: plain-host-deploy --target-host root@IP --disk /dev/sdX [--flake .#ovh-vps-base] [--hostname HOSTNAME] [--root-password-hash HASH] [extra nixos-anywhere args...]

Destructive plain NixOS base install for an OVH VPS in rescue mode.
Optionally bootstrap NixPI afterward on the installed machine with nixpi-bootstrap-host.

A root password is always set for OVH KVM console access. If --root-password-hash is not
supplied, a random password is generated, its plaintext is printed to stderr, and it is also
saved to a local root-only file in the current directory. Save it.

Examples:
  nix run .#plain-host-deploy -- --target-host root@198.51.100.10 --disk /dev/sda
  nix run .#plain-host-deploy -- --target-host root@198.51.100.10 --disk /dev/nvme0n1 --hostname bloom-eu-1
  nix run .#plain-host-deploy -- --target-host root@198.51.100.10 --disk /dev/sda --root-password-hash '$6$...'
EOF_USAGE
}

main() {
	local target_host=""
	local disk=""
	local hostname="ovh-vps-base"
	local flake_ref="${NIXPI_REPO_ROOT:-.}#ovh-vps-base"
	local root_password_hash=""
	local extra_args=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--target-host)
				target_host="${2:?missing target host}"
				shift 2
				;;
			--disk)
				disk="${2:?missing disk path}"
				shift 2
				;;
			--flake)
				flake_ref="${2:?missing flake ref}"
				shift 2
				;;
			--hostname)
				hostname="${2:?missing hostname}"
				shift 2
				;;
			--root-password-hash)
				root_password_hash="${2:?missing root password hash}"
				shift 2
				;;
			--bootstrap-user|--bootstrap-user=*|--bootstrap-password-hash|--bootstrap-password-hash=*)
				usage >&2
				printf 'Unsupported legacy option: %s. Install the plain ovh-vps-base system, then run nixpi-bootstrap-host after first boot.\n' "${1%%=*}" >&2
				exit 1
				;;
			--help|-h)
				usage
				exit 0
				;;
			*)
				extra_args+=("$1")
				shift
				;;
		esac
	done

	if [[ -z "$target_host" || -z "$disk" ]]; then
		usage >&2
		exit 1
	fi

	run_ovh_deploy "$target_host" "$disk" "$hostname" "$flake_ref" "$root_password_hash" "${extra_args[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
