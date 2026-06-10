# syntax=docker/dockerfile:1
#
# Custom GitHub Actions runner image for the platform's self-hosted ARC pool (ADR-065 / #323).
#
# Bakes the platform's pinned IaC toolchain onto the official ARC runner base so an in-VPC runner can run
# `terragrunt apply` against the PRIVATE EKS API (which GitHub-hosted runners can't reach). arm64 only — the
# platform is all-Graviton. Tool versions come from /.tool-versions (the single source of truth) as build-args;
# the build workflow reads that file and passes them in, so this image can't drift from CI or local dev. Each
# tool is SHA-256 verified at build (matching the repo's supply-chain posture). The `helm` CLI is debug-only —
# terragrunt drives chart installs through the Terraform helm provider, not this binary.

ARG RUNNER_VERSION=2.335.1
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

# Toolchain versions — supplied by the build workflow from /.tool-versions. No defaults on purpose: a missing
# build-arg should fail the build loudly, not silently bake an unpinned tool.
ARG TOFU_VERSION
ARG TERRAGRUNT_VERSION
ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG AWSCLI_VERSION

# The base ships as the unprivileged `runner` user; install as root, then drop back at the end.
USER root
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Base utilities for the installs (the runner image is intentionally minimal).
RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip ca-certificates curl jq \
 && rm -rf /var/lib/apt/lists/*

# OpenTofu — verify the zip against the release SHA256SUMS, then drop `tofu` on PATH.
RUN cd /tmp \
 && base="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}" \
 && asset="tofu_${TOFU_VERSION}_linux_arm64.zip" \
 && curl -fsSL "${base}/${asset}" -o "${asset}" \
 && curl -fsSL "${base}/tofu_${TOFU_VERSION}_SHA256SUMS" -o SHA256SUMS \
 && grep " ${asset}\$" SHA256SUMS | sha256sum -c - \
 && unzip -o "${asset}" tofu -d /usr/local/bin/ \
 && chmod +x /usr/local/bin/tofu \
 && rm -f "${asset}" SHA256SUMS

# Terragrunt — single binary, verified against the release SHA256SUMS.
RUN cd /tmp \
 && base="https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}" \
 && asset="terragrunt_linux_arm64" \
 && curl -fsSL "${base}/${asset}" -o "${asset}" \
 && curl -fsSL "${base}/SHA256SUMS" -o SHA256SUMS \
 && grep " ${asset}\$" SHA256SUMS | sha256sum -c - \
 && install -m 0755 "${asset}" /usr/local/bin/terragrunt \
 && rm -f "${asset}" SHA256SUMS

# kubectl — pinned to the cluster minor; verify against the published .sha256.
RUN cd /tmp \
 && ver="v${KUBECTL_VERSION}" \
 && curl -fsSL "https://dl.k8s.io/release/${ver}/bin/linux/arm64/kubectl" -o kubectl \
 && curl -fsSL "https://dl.k8s.io/release/${ver}/bin/linux/arm64/kubectl.sha256" -o kubectl.sha256 \
 && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - \
 && install -m 0755 kubectl /usr/local/bin/kubectl \
 && rm -f kubectl kubectl.sha256

# Helm (3.x — debug-only CLI) — verify the tarball against the published .sha256sum.
RUN cd /tmp \
 && asset="helm-v${HELM_VERSION}-linux-arm64.tar.gz" \
 && curl -fsSL "https://get.helm.sh/${asset}" -o "${asset}" \
 && curl -fsSL "https://get.helm.sh/${asset}.sha256sum" -o helm.sha256sum \
 && sha256sum -c helm.sha256sum \
 && tar -xzf "${asset}" linux-arm64/helm \
 && install -m 0755 linux-arm64/helm /usr/local/bin/helm \
 && rm -rf "${asset}" helm.sha256sum linux-arm64

# AWS CLI v2 — immutable per-version HTTPS artifact + official installer. (TODO: add GPG signature verification
# with AWS's public key — the CLI ships only a .sig, no SHA file, so it's deferred from this first cut.)
RUN cd /tmp \
 && asset="awscli-exe-linux-aarch64-${AWSCLI_VERSION}.zip" \
 && curl -fsSL "https://awscli.amazonaws.com/${asset}" -o awscliv2.zip \
 && unzip -q awscliv2.zip \
 && ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli \
 && rm -rf aws awscliv2.zip

# Fail the build if any tool didn't land / runs the wrong arch.
RUN tofu version \
 && terragrunt --version \
 && kubectl version --client \
 && helm version --short \
 && aws --version

USER runner
