#!/usr/bin/env bash
# Build and push the otp-build / otp-serve images to Azure Container Registry.
#
# Tags images with "<otp-version>-<git-sha>" (add "-dirty" if the working tree
# has uncommitted changes) for traceability
#
# ACR name defaults to $ACR_NAME env var, falling back to acrnapcorexdemodev
# (see infra/main.bicepparam).
# OTP_IMAGE defaults to official image v2.9.0. Replace with custom image if desired
# Requires:
#   - az CLI logged in (az login) with at least AcrPush on the registry.
#   - podman installed.
set -euo pipefail

cd "$(dirname "$0")/.."

ACR_NAME="${1:-${ACR_NAME:-acrnapcorexdemodev}}"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
OTP_IMAGE="${2:-${OTP_IMAGE:-docker.io/opentripplanner/opentripplanner:2.9.0}}"

# Pinned base image version, see src/build/Dockerfile and src/serve/Dockerfile.
# TODO: update this when the base image is updated.
OTP_VERSION=2.9.0

GIT_SHA="$(git rev-parse --short HEAD)"
if ! git diff --quiet || ! git diff --cached --quiet; then
  GIT_SHA="${GIT_SHA}-dirty"
fi
TAG="${OTP_VERSION}-${GIT_SHA}"

echo "==> Tag: ${TAG}"
echo "==> Registry: ${ACR_LOGIN_SERVER}"
echo "==> OTP base image: ${OTP_IMAGE}"

echo "==> Logging in to ${ACR_LOGIN_SERVER}"
ACR_TOKEN="$(az acr login --name "${ACR_NAME}" --expose-token --output tsv --query accessToken)"
podman login "${ACR_LOGIN_SERVER}" -u 00000000-0000-0000-0000-000000000000 --password "${ACR_TOKEN}"

echo "==> Building otp-build:${TAG}"
podman build -f src/build/Dockerfile --build-arg OTP_BASE_IMAGE="${OTP_IMAGE}" -t "${ACR_LOGIN_SERVER}/otp-build:${TAG}" .

echo "==> Building otp-serve:${TAG}"
podman build -f src/serve/Dockerfile --build-arg OTP_BASE_IMAGE="${OTP_IMAGE}" -t "${ACR_LOGIN_SERVER}/otp-serve:${TAG}" .

echo "==> Pushing otp-build:${TAG}"
podman push "${ACR_LOGIN_SERVER}/otp-build:${TAG}"

echo "==> Pushing otp-serve:${TAG}"
podman push "${ACR_LOGIN_SERVER}/otp-serve:${TAG}"

echo "==> Done. Pushed:"
echo "    ${ACR_LOGIN_SERVER}/otp-build:${TAG}"
echo "    ${ACR_LOGIN_SERVER}/otp-serve:${TAG}"
