#!/bin/bash
# Healthy once the server has logged that it started, for as long as its process runs.
[ -f /tmp/pz-ready ] && kill -0 "$(cat /tmp/pz-server.pid 2>/dev/null)" 2>/dev/null
