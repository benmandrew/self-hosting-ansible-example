# What is left out

A firewall, SSH hardening, a non-root deploy user, backups, monitoring and Let's Encrypt automation are all absent on purpose. Each is something to add yourself once the basics work.

## The Docker socket

The runner mounts `/var/run/docker.sock`, and jobs run as sibling containers on the host's Docker daemon. Any workflow can therefore act as root on the server. Keep the Gitea instance to people you trust.

The example stops at the point where a server serves a site and builds its own code, and everything past that is a decision about your own server.
