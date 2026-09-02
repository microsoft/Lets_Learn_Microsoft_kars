#!/bin/sh
set -eu

mkdir -p /sandbox/agent
cp -R /opt/fabrikam-agent/. /sandbox/agent/
cd /sandbox/agent
exec /usr/local/bin/kars-maf-entrypoint.sh "$@"
