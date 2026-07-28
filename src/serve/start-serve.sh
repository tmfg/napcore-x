#!/usr/bin/env sh
set -eu

# Placeholder path: replace with the mounted directory that contains graph.obj.
OTP_GRAPH_DIR="${OTP_GRAPH_DIR:-<OTP_GRAPH_DIR_PLACEHOLDER>}"

if [ "$OTP_GRAPH_DIR" = "<OTP_GRAPH_DIR_PLACEHOLDER>" ]; then
  echo "Set OTP_GRAPH_DIR to the directory containing graph.obj before running."
  exit 1
fi

if [ ! -f "$OTP_GRAPH_DIR/graph.obj" ]; then
  echo "Missing graph file: $OTP_GRAPH_DIR/graph.obj"
  exit 1
fi

# NOTE: the base image's real entrypoint is /docker-entrypoint.sh, which always
# runs against the hardcoded /var/opentripplanner/ directory, so the graph must
# be copied there first. --load implies --serve.
mkdir -p /var/opentripplanner
cp "$OTP_GRAPH_DIR/graph.obj" /var/opentripplanner/graph.obj

exec /docker-entrypoint.sh --load
