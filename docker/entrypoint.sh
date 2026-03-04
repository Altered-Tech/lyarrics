#!/bin/sh
mkdir -p /var/log
touch /var/log/lyarrics.log
exec tail -F /var/log/lyarrics.log
