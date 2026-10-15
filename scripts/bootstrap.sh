#!/usr/bin/env bash
# Create the secrets this repository needs, encrypted with Ansible Vault:
#
#   vault-pass.txt                   the vault password (never committed)
#   roles/certs/files/origin.{pem,key}  a self-signed TLS certificate
#   group_vars/all/vault.yml         the Gitea admin password and runner token
#
# Existing files are left alone, so this is safe to re-run. Replace the
# self-signed certificate with a real one (a Cloudflare origin certificate,
# say) before pointing DNS at the server.
set -euo pipefail

cd "$(dirname "$0")/.."

domain=$(sed -n 's/^domain: *//p' group_vars/all/main.yml)

if [[ ! -f vault-pass.txt ]]; then
	openssl rand -base64 32 >vault-pass.txt
	chmod 600 vault-pass.txt
	echo "Wrote vault-pass.txt. Keep a copy somewhere safe; nothing decrypts without it."
fi

if [[ ! -f roles/certs/files/origin.pem ]]; then
	mkdir -p roles/certs/files
	openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
		-subj "/CN=${domain}" \
		-addext "subjectAltName=DNS:${domain},DNS:*.${domain}" \
		-keyout roles/certs/files/origin.key \
		-out roles/certs/files/origin.pem 2>/dev/null
	ansible-vault encrypt roles/certs/files/origin.key roles/certs/files/origin.pem
	echo "Wrote a self-signed certificate for ${domain} and *.${domain}."
fi

if [[ ! -f group_vars/all/vault.yml ]]; then
	admin_password=$(openssl rand -base64 18)
	cat >group_vars/all/vault.yml <<VAULT
---
vault_gitea_admin_password: "${admin_password}"
vault_gitea_runner_token: "$(openssl rand -hex 32)"
VAULT
	ansible-vault encrypt group_vars/all/vault.yml
	echo "Wrote group_vars/all/vault.yml. The Gitea admin password is: ${admin_password}"
	echo "Read it again later with: ansible-vault view group_vars/all/vault.yml"
fi
