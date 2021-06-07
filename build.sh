#!/bin/bash
#
#
set -e
docker build ./ --rm -t chef-server
docker run -v /sys/fs/cgroup:/sys/fs/cgroup:ro --tmpfs /tmp --tmpfs /run --rm --privileged -it --name chef-server -p 443:443 -p 80:80 --restart on-failure chef-server