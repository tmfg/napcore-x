#!/usr/bin/env bash
# Builds the patched OTP (custom debug-client logo) into a local podman image,
# using jib directly instead of the official image's build
#
# Assumes the debug client source changes are already made and manually
# verified
#
# Env vars (both optional):
#   OTP_DIR         - path to the cloned OpenTripPlanner source tree.
#   TARGET_PLATFORM - jib platform to build for (must match the machine this
#                     image will actually run on). Defaults to linux/amd64.
#
# Requires: maven, npm, podman.

set -euo pipefail

OTP_DIR="${OTP_DIR:-./OpenTripPlanner}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"
IMAGE_NAME="localhost/otp-custom:latest"

if [ ! -f "${OTP_DIR}/pom.xml" ]; then
  echo "OTP_DIR (${OTP_DIR}) does not look like an OpenTripPlanner checkout (no pom.xml found)" >&2
  exit 1
fi

cd "${OTP_DIR}"

echo "==> Building debug client (npx vite build, npm run build was failing)" >&2
( cd client && npx vite build )

echo "==> Replacing application/src/client/ with the fresh build" >&2
rm -rf application/src/client/*
cp -r client/output/* application/src/client/

echo "==> Building reactor (mvn install, no jib) from ${OTP_DIR}" >&2
mvn -pl application -am clean install -DskipTests

echo "==> Containerizing application module with jib (platform: ${TARGET_PLATFORM})" >&2
mvn -pl application jib:buildTar \
  -Djib.to.image="${IMAGE_NAME}" \
  -Djib.from.platforms="${TARGET_PLATFORM}"

echo "==> Loading image into podman" >&2
podman load -i application/target/jib-image.tar

echo "${IMAGE_NAME}"
