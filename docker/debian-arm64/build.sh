#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
suite=${BLADERF_ARM64_SUITE:-trixie}
firmware_mode=${BLADERF_FIRMWARE_MODE:-prebuilt}

if [[ ! "$suite" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    printf 'Invalid Debian suite: %s\n' "$suite" >&2
    exit 2
fi
if [[ "$firmware_mode" != prebuilt && "$firmware_mode" != source ]]; then
    printf 'Invalid firmware mode: %s (expected prebuilt or source)\n' "$firmware_mode" >&2
    exit 2
fi

configure_only=0
if [[ ${1:-} == --configure-only ]]; then
    configure_only=1
    shift
fi
if (( $# > 1 )); then
    printf 'Usage: %s [--configure-only] [output-directory]\n' "$0" >&2
    exit 2
fi

image=${BLADERF_ARM64_IMAGE:-bladerf-debian-${suite}-arm64-builder}
workspace_default="$repo_root/build-arm64-$suite-$firmware_mode"
workspace=${BLADERF_ARM64_WORKSPACE:-$workspace_default}
output=${1:-"$workspace/artifacts"}
mkdir -p "$workspace" "$output"
workspace=$(CDPATH= cd -- "$workspace" && pwd)
output=$(CDPATH= cd -- "$output" && pwd)

exec 9>"$workspace/.build.lock"
if ! flock -n 9; then
    printf 'Another bladeRF build is using %s\n' "$workspace" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    printf '%s\n' 'Docker is unavailable. Start Docker or configure BLADERF_ARM64_IMAGE for an accessible daemon.' >&2
    exit 1
fi

docker build --platform linux/amd64 \
    --build-arg "DEBIAN_SUITE=$suite" \
    -f "$script_dir/Dockerfile" \
    -t "$image" "$script_dir"

docker_mounts=()
docker_env=(
    -e "BLADERF_DEBIAN_SUITE=$suite" \
    -e "BLADERF_FIRMWARE_MODE=$firmware_mode" \
    -e "BLADERF_CONFIGURE_ONLY=$configure_only" \
    -e "BLADERF_BUILD_JOBS=${BLADERF_BUILD_JOBS:-}"
)
if [[ "$firmware_mode" == source ]]; then
    cypress_root=${BLADERF_CYPRESS_ROOT:-}
    intel_fpga_root=${BLADERF_INTELFPGA_ROOT:-}
    if [[ ! -d "$cypress_root" || ! -d "$intel_fpga_root" ]]; then
        printf '%s\n' 'Source firmware mode requires BLADERF_CYPRESS_ROOT and BLADERF_INTELFPGA_ROOT directories.' >&2
        exit 2
    fi
    docker_mounts+=(--mount "type=bind,source=$(cd "$cypress_root" && pwd),target=/vendor/cypress,readonly")
    intel_fpga_root=$(cd "$intel_fpga_root" && pwd)
    docker_mounts+=(--mount "type=bind,source=$intel_fpga_root,target=/vendor/intelFPGA,readonly")
    docker_env+=(-e BLADERF_CYPRESS_ROOT=/vendor/cypress -e BLADERF_INTELFPGA_ROOT=/vendor/intelFPGA)
    if [[ -n ${BLADERF_QUARTUS_ROOTDIR:-} ]]; then
        quartus_root=$(realpath "$BLADERF_QUARTUS_ROOTDIR")
        case "$quartus_root" in
            "$intel_fpga_root"/*)
                docker_env+=(-e "BLADERF_QUARTUS_ROOTDIR=/vendor/intelFPGA/${quartus_root#"$intel_fpga_root"/}")
                ;;
            *)
                printf '%s\n' 'BLADERF_QUARTUS_ROOTDIR must be inside BLADERF_INTELFPGA_ROOT so it can be mounted read-only.' >&2
                exit 2
                ;;
        esac
    fi
fi

docker run --rm --platform linux/amd64 \
    "${docker_env[@]}" \
    -v "$repo_root:/source:ro" \
    -v "$workspace:/workspace" \
    -v "$output:/output" \
    "${docker_mounts[@]}" \
    "$image" 2>&1 | tee -a "$workspace/build.log"

if (( configure_only )); then
    printf 'Configure-only build completed; see %s/build.log\n' "$workspace"
else
    printf 'Packages and archives written to %s\n' "$output"
fi