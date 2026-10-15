# self-hosting-ansible-example

This repository is the working example for the article [Self-Hosting Your Own Website, from Start to Finish](https://benmandrew.com/articles/self-hosting-website). It deploys the static site, Gitea and its continuous integration (CI) runner onto one server with Ansible and Docker Compose.

## Deploy

```bash
make install-deps   # the community.docker collection
# set `domain` in group_vars/all/main.yml and the server's address in inventory.yml
make bootstrap      # vault password, self-signed certificate, encrypted secrets
make deploy
```

## Further reading

- [docs/layout.md](docs/layout.md) maps each article section onto files and describes the four roles.
- [docs/setup.md](docs/setup.md) covers requirements, secrets, a real certificate, partial deploys and lint.
- [docs/testing.md](docs/testing.md) describes the end-to-end test against a local virtual machine.
- [docs/left-out.md](docs/left-out.md) lists what is deliberately absent. The runner mounts the Docker socket, so any workflow is root on the server.
