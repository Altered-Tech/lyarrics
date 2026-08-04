#!/bin/sh
mkdir -p /var/log
touch /var/log/lyarrics.log

# Bind to all interfaces so the server is reachable from outside the container;
# the CLI's own default of 127.0.0.1 is meant for running lyarrics on the host directly.
/usr/local/bin/lyarrics-bin serve --hostname 0.0.0.0 >> /var/log/lyarrics.log 2>&1 &

exec tail -F /var/log/lyarrics.log
