#!/usr/bin/env bash
# End-to-end test: boot a fresh Debian 13 VM under QEMU, deploy the playbook to
# it twice, and check that the site, Gitea and the CI runner work.
#
# Needs qemu-system-x86_64, qemu-img, genisoimage, a usable /dev/kvm, and
# ansible with the collections from requirements.yml. Runs as an ordinary
# user: the VM uses QEMU's user-mode networking, with its ports forwarded to
# 127.0.0.1 only.
#
# KEEP_VM=1 leaves the VM running afterwards, for poking at by hand.
set -euo pipefail

cd "$(dirname "$0")/.."
repo=$PWD
# ssh forwards the locale, and the cloud image has only C.UTF-8.
export LC_ALL=C.UTF-8

image_url=https://cloud.debian.org/images/cloud/trixie/latest
image_name=debian-13-genericcloud-amd64.qcow2
cache=$repo/tests/.cache
work=$(mktemp -d)
failures=0

log() { printf '\n==> [%3ds] %s\n' "$SECONDS" "$*"; }
pass() { printf '  ok    %s\n' "$1"; }
fail() {
	printf '  FAIL  %s: %s\n' "$1" "$2"
	failures=$((failures + 1))
}

cleanup() {
	if [[ -f $work/qemu.pid ]] && [[ ${KEEP_VM:-0} != 1 ]]; then
		kill "$(cat "$work/qemu.pid")" 2>/dev/null || true
	fi
	if [[ ${KEEP_VM:-0} == 1 ]]; then
		echo "VM left running; its files are in $work"
	else
		rm -rf "$work"
	fi
}
trap cleanup EXIT

free_port() {
	python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'
}

# The playbook reads secrets from the vault, so they must exist.
./scripts/bootstrap.sh >/dev/null

log "Fetching the Debian 13 cloud image"
# Debian republishes "latest", so a cached image that no longer matches the
# published checksum is stale rather than corrupt, and is fetched again.
mkdir -p "$cache"
curl -fsSL -o "$cache/SHA512SUMS" "$image_url/SHA512SUMS"
image_ok() {
	[[ -f $cache/$image_name ]] &&
		(cd "$cache" && grep " $image_name\$" SHA512SUMS | sha512sum -c --quiet - >/dev/null 2>&1)
}
if ! image_ok; then
	curl -fsSL -o "$cache/$image_name" "$image_url/$image_name"
	image_ok || {
		echo "Downloaded image does not match its checksum"
		exit 1
	}
fi

log "Booting the VM"
qemu-img create -q -f qcow2 -b "$cache/$image_name" -F qcow2 "$work/disk.qcow2" 20G
ssh-keygen -q -t ed25519 -N '' -f "$work/id" -C e2e
# apt's HTTP pipelining stalls for about 30 s per update behind QEMU's
# user-mode network (34-46 s against 3.4-3.8 s without it, measured on this
# image; no stall on the host). A real server has no such problem, so this
# removes an emulator artefact rather than changing what is tested.
cat >"$work/user-data" <<CLOUD
#cloud-config
disable_root: false
write_files:
  - path: /etc/apt/apt.conf.d/99-no-pipelining
    content: 'Acquire::http::Pipeline-Depth "0";'
users:
  - name: root
    ssh_authorized_keys:
      - $(cat "$work/id.pub")
CLOUD
printf 'instance-id: e2e\nlocal-hostname: droplet\n' >"$work/meta-data"
genisoimage -quiet -output "$work/seed.iso" -volid cidata -joliet -rock \
	"$work/user-data" "$work/meta-data"

ssh_port=$(free_port)
http_port=$(free_port)
https_port=$(free_port)
git_ssh_port=$(free_port)
qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m 4096 \
	-drive "file=$work/disk.qcow2,if=virtio" \
	-drive "file=$work/seed.iso,media=cdrom" \
	-netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$ssh_port-:22,hostfwd=tcp:127.0.0.1:$http_port-:80,hostfwd=tcp:127.0.0.1:$https_port-:443,hostfwd=tcp:127.0.0.1:$git_ssh_port-:2222" \
	-device virtio-net-pci,netdev=n0 \
	-display none -serial "file:$work/console.log" \
	-daemonize -pidfile "$work/qemu.pid"

ssh_opts=(-q -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5 -i "$work/id" -p "$ssh_port")
# shellcheck disable=SC2029 # the command is meant to expand locally
vm() { ssh "${ssh_opts[@]}" root@127.0.0.1 "$@"; }

for _ in $(seq 180); do
	vm 'cloud-init status --wait >/dev/null' 2>/dev/null && break
	sleep 1
done
vm true || {
	tail -30 "$work/console.log"
	echo "VM never accepted SSH"
	exit 1
}

# Ansible reads group_vars from beside the inventory file, so link them in.
cat >"$work/inventory.yml" <<INV
myhosts:
  hosts:
    droplet:
      ansible_host: 127.0.0.1
      ansible_port: $ssh_port
      ansible_user: root
      ansible_ssh_private_key_file: $work/id
      ansible_ssh_common_args: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
INV
ln -s "$repo/group_vars" "$work/group_vars"

log "Deploying (first run)"
ansible-playbook -i "$work/inventory.yml" playbooks/site.yml | tee "$work/run1.log" | grep -E '^(TASK|fatal|PLAY RECAP)|failed='

log "Deploying again (should change nothing)"
ansible-playbook -i "$work/inventory.yml" playbooks/site.yml >"$work/run2.log"
if grep -qE 'droplet +: .*changed=0 .*failed=0' "$work/run2.log"; then
	pass "second run is idempotent"
else
	fail "second run is idempotent" "$(grep -E 'droplet +:' "$work/run2.log")"
	grep -E '^(TASK|changed)' "$work/run2.log" | grep -B1 '^changed'
fi

log "Checking the deployment"
domain=$(sed -n 's/^domain: *//p' group_vars/all/main.yml)
git_domain=git.$domain
resolve=(--resolve "$domain:$https_port:127.0.0.1" --resolve "www.$domain:$https_port:127.0.0.1"
	--resolve "$git_domain:$https_port:127.0.0.1" --resolve "$domain:$http_port:127.0.0.1")
get() { curl -sk "${resolve[@]}" "$@"; }

expect() { # name, expected, actual
	if [[ $3 == "$2" ]]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

expect "site answers" 200 "$(get -o /dev/null -w '%{http_code}' "https://$domain:$https_port/")"
expect "missing page is a 404" 404 "$(get -o /dev/null -w '%{http_code}' "https://$domain:$https_port/no-such-page")"
expect "www redirects to the apex" "301 https://$domain/x" \
	"$(get -o /dev/null -w '%{http_code} %{redirect_url}' "https://www.$domain:$https_port/x")"
expect "HTTP redirects to HTTPS" "301 https://$domain/" \
	"$(get -o /dev/null -w '%{http_code} %{redirect_url}' "http://$domain:$http_port/")"
expect "Gitea answers through nginx" 200 \
	"$(get -o /dev/null -w '%{http_code}' "https://$git_domain:$https_port/api/v1/version")"

# Captured first: grep -q exits at the first match, and under pipefail the
# SIGPIPE that kills curl mid-page would fail the check.
signup=$(get "https://$git_domain:$https_port/user/sign_up")
if grep -q 'Registration is disabled' <<<"$signup"; then
	pass "public registration is disabled"
else
	fail "public registration is disabled" "sign-up page does not say so"
fi

banner=$(timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/$git_ssh_port; head -c 7 <&3" || true)
expect "git over SSH answers" SSH-2.0 "$banner"

admin=$(sed -n 's/^gitea_admin_user: *//p' group_vars/all/main.yml)
password=$(ansible-vault view group_vars/all/vault.yml | sed -n 's/^vault_gitea_admin_password: *"\(.*\)"$/\1/p')
api() { get -u "$admin:$password" -H 'Content-Type: application/json' "$@"; }
api_url=https://$git_domain:$https_port/api/v1

expect "admin can log in" 200 "$(api -o /dev/null -w '%{http_code}' "$api_url/user")"

log "Running a CI job on the runner"
# No actions/checkout: the job container would clone from the public URL,
# which does not resolve inside the VM. The job runs in Alpine rather than the
# label's 589 MB runner image, which is most of what the VM would download.
api -X POST "$api_url/user/repos" -d '{"name":"e2e","auto_init":true}' -o /dev/null
workflow=$(printf 'on: [push]\njobs:\n  hello:\n    runs-on: ubuntu-latest\n    container: alpine:3.24.2\n    steps:\n      - run: echo hello\n' | base64 -w0)
api -X POST "$api_url/repos/$admin/e2e/contents/.gitea/workflows/ci.yml" \
	-d "{\"content\":\"$workflow\",\"message\":\"Add CI\"}" -o /dev/null

status=none
for _ in $(seq 300); do
	status=$(api "$api_url/repos/$admin/e2e/actions/runs" | python3 -c '
import json, sys
runs = json.load(sys.stdin).get("workflow_runs") or []
print(runs[0]["status"], runs[0].get("conclusion")) if runs else print("none")')
	[[ $status == completed* ]] && break
	sleep 2
done
expect "CI job succeeds" "completed success" "$status"

log "Result"
if ((failures > 0)); then
	echo "$failures check(s) failed"
	exit 1
fi
echo "All checks passed"
