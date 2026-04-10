#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[plain-host-deploy] %s\n' "$*" >&2
}

resolve_repo_url() {
	local ref="$1"
	if [[ "$ref" == path:* || "$ref" == github:* || "$ref" == git+* || "$ref" == https://* || "$ref" == ssh://* ]]; then
		printf '%s\n' "$ref"
		return 0
	fi

	if [[ "$ref" == . || "$ref" == /* ]]; then
		printf 'path:%s\n' "$(realpath "$ref")"
		return 0
	fi

	printf '%s\n' "$ref"
}

escape_nix_string() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//\$/\\\$}"
	value="${value//$'\n'/\\n}"
	printf '%s' "$value"
}

# generate_root_password_hash
# Prints a SHA-512 crypt hash for a freshly generated random password.
# Also logs the plaintext to stderr so the operator can record it.
generate_root_password_hash() {
	local plain_pass hash
	plain_pass="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)"
	hash="$(nix shell 'nixpkgs#mkpasswd' --command mkpasswd --method=sha-512 --rounds=500000 "$plain_pass" 2>/dev/null)"
	if [[ -z "$hash" ]]; then
		log "ERROR: could not generate root password hash (mkpasswd failed)"
		return 1
	fi
	log "Generated root password for KVM console access: ${plain_pass}"
	log "IMPORTANT: save this password — it will not be shown again"
	printf '%s' "$hash"
}

build_deploy_flake() {
	local repo_url="$1"
	local base_attr="$2"
	local hostname="$3"
	local disk="$4"
	local root_password_hash="${5:-}"
	local nix_hostname=""
	local nix_disk=""
	local root_pw_stmt=""

	nix_hostname="$(escape_nix_string "$hostname")"
	nix_disk="$(escape_nix_string "$disk")"

	if [[ -n "$root_password_hash" ]]; then
		local nix_root_pw
		nix_root_pw="$(escape_nix_string "$root_password_hash")"
		root_pw_stmt="
          users.users.root.hashedPassword = lib.mkForce \"${nix_root_pw}\";"
	fi

	cat <<EOF_FLAKE
{
  inputs.nixpi.url = "${repo_url}";

  outputs = { nixpi, ... }: {
    nixosConfigurations.deploy = nixpi.nixosConfigurations.${base_attr}.extendModules {
      modules = [
        ({ lib, ... }: {
          networking.hostName = lib.mkForce "${nix_hostname}";
          disko.devices.disk.main.device = lib.mkForce "${nix_disk}";${root_pw_stmt}
        })
      ];
    };
  };
}
EOF_FLAKE
}

run_ovh_deploy() {
	local target_host="$1"
	local disk="$2"
	local hostname="$3"
	local flake_ref="$4"
	local root_password_hash="${5:-}"
	shift 5

	local repo_ref=""
	local base_attr=""
	local repo_url=""
	local tmp_dir=""
	local nixos_anywhere_args=()
	local extra_args=("$@")

	if [[ "$flake_ref" != *#* ]]; then
		log "Flake ref must include a nixosConfigurations attribute, for example .#ovh-vps-base"
		return 1
	fi

	repo_ref="${flake_ref%%#*}"
	base_attr="${flake_ref#*#}"
	if [[ "$base_attr" != "ovh-vps-base" ]]; then
		log "Flake ref must target the ovh-vps-base nixosConfigurations profile (for example .#ovh-vps-base)"
		return 1
	fi
	repo_url="$(resolve_repo_url "$repo_ref")"
	tmp_dir="$(mktemp -d)"
	trap 'rm -rf "$tmp_dir"' RETURN

	if [[ -z "$root_password_hash" ]]; then
		root_password_hash="$(generate_root_password_hash)"
	fi

	build_deploy_flake "$repo_url" "$base_attr" "$hostname" "$disk" "$root_password_hash" > "$tmp_dir/flake.nix"

	log "WARNING: destructive install to ${target_host} using disk ${disk}"
	log "Using base configuration ${flake_ref} with target hostname ${hostname}"
	log "nixos-anywhere will install a plain OVH VPS base system only"
	log "After first boot, optionally run nixpi-bootstrap-host on the machine to layer NixPI onto /etc/nixos"

	nixos_anywhere_args=(
		--flake "$tmp_dir#deploy"
		--target-host "$target_host"
	)

	nixos_anywhere_args+=("${extra_args[@]}")

	exec "${NIXPI_NIXOS_ANYWHERE:-nixos-anywhere}" "${nixos_anywhere_args[@]}"
}
