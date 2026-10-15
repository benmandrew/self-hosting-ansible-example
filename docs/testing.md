# Testing

`make test` runs `tests/e2e.sh`, which boots a fresh Debian 13 cloud image under QEMU with the Kernel-based Virtual Machine (KVM) as an ordinary user. The virtual machine (VM) uses QEMU's *user-mode networking*, with its ports forwarded to `127.0.0.1` only. The script deploys twice and checks that:

- the second run changes nothing;
- the site answers 200 and a missing page answers 404;
- `www` and plain HTTP both redirect;
- Gitea answers through nginx, with registration disabled;
- git over Secure Shell (SSH) answers with a banner, and the admin user can log in;
- a continuous integration (CI) job pushed to a new repository completes successfully on the runner.

## Requirements

The test needs `qemu-system-x86_64`, `qemu-img`, `genisoimage`, access to `/dev/kvm`, and Ansible with the collections from `requirements.yml`. It runs `bootstrap.sh` first, since the playbook reads its secrets from the vault. The cloud image is cached in `tests/.cache` and fetched again when it no longer matches Debian's published checksum. `KEEP_VM=1 make test` leaves the VM running afterwards.

## Timing

A full local run of `make test` took 129 seconds, most of it downloading packages and images onto the fresh VM. The same test runs in GitHub Actions through `.github/workflows/e2e.yml`, where the job took about 2 minutes 16 seconds, 89 seconds of it in the script. That workflow caches the 341 MB cloud image, keyed on its published checksum.

## Two departures from a real server

The test VM turns off apt's HTTP pipelining, because it stalls for about 30 seconds per update behind QEMU's user-mode network. The test's CI job runs in an Alpine container rather than the 589 MB runner image behind the `ubuntu-latest` label, so it does not check that image itself.
