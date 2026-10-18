#!/usr/bin/env bash
set -euo pipefail

suite=${BLADERF_DEBIAN_SUITE:?BLADERF_DEBIAN_SUITE is required}
firmware_mode=${BLADERF_FIRMWARE_MODE:-prebuilt}
configure_only=${BLADERF_CONFIGURE_ONLY:-0}
source_dir=/workspace/source
firmware_dir=/workspace/firmware
jobs=${BLADERF_BUILD_JOBS:-$(nproc)}

if [[ ! -r /source/debian/control || ! -r /source/CMakeLists.txt ]]; then
    printf '%s\n' 'The read-only source mount does not contain a bladeRF source tree.' >&2
    exit 2
fi

if [[ -z "$(find /source/host/utilities/bladeRF-fsk/c -mindepth 1 -print -quit 2>/dev/null)" || \
      -z "$(find /source/thirdparty/analogdevicesinc/no-OS -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    printf '%s\n' 'Required git submodules are not initialized. Run git submodule update --init --recursive in the checkout, then retry.' >&2
    exit 2
fi

mkdir -p "$source_dir" "$firmware_dir"
rsync -a --delete \
    --exclude='/.git' \
    --exclude='/build*' \
    --exclude='/dist' \
    --exclude='/debian/*.debhelper' \
    --exclude='/debian/tmp' \
    /source/ "$source_dir/"

if [[ ! -e "$source_dir/.git" ]]; then
    ln -s /source/.git "$source_dir/.git"
fi
git config --global --add safe.directory "$source_dir"

git_revision=$(git -c safe.directory=/source -C /source rev-parse --short=12 HEAD)
git_describe=$(git -c safe.directory=/source -C /source describe --tags --always --dirty)
export SOURCE_DATE_EPOCH=$(git -c safe.directory=/source -C /source log -1 --format=%ct)
git_dirty_suffix=
if [[ "$git_describe" == *-dirty ]]; then
    git_dirty_suffix=-dirty
fi
export VERSION_INFO_OVERRIDE="git-${git_revision}${git_dirty_suffix}"
export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:+${DEB_BUILD_OPTIONS} }nocheck"
rm -rf /workspace/wheels
mkdir -p /workspace/wheels

cd "$source_dir"
version="${git_describe/-dirty/+dirty}-1~${suite}1"
sed -i "1s/^bladerf (.*) [^;]*;/bladerf (${version}) ${suite};/" debian/changelog

if [[ "$firmware_mode" == source ]]; then
    cypress_root=${BLADERF_CYPRESS_ROOT:?BLADERF_CYPRESS_ROOT is required}
    intel_fpga_root=${BLADERF_INTELFPGA_ROOT:?BLADERF_INTELFPGA_ROOT is required}
    fx3_sdk="$cypress_root/fx3_firmware_linux"
    export BLADERF_FX3_INSTALL_PATH="$fx3_sdk"
    quartus_root=${BLADERF_QUARTUS_ROOTDIR:-$(find "$intel_fpga_root" -type f -path '*/quartus/version.txt' -printf '%h\n' -quit)}
    if [[ ! -d "$fx3_sdk/cyfx3sdk" || ! -d "$cypress_root/ARM_GCC/arm-2013.11" ]]; then
        printf 'Cypress SDK layout not found under %s (expected fx3_firmware_linux and ARM_GCC/arm-2013.11).\n' "$cypress_root" >&2
        exit 2
    fi
    if [[ ! -f "$quartus_root/version.txt" ]]; then
        printf 'Quartus version.txt not found under %s.\n' "$quartus_root" >&2
        exit 2
    fi
fi

if [[ "$configure_only" == 1 ]]; then
    dpkg-architecture -aarm64 -c 'make -f debian/rules override_dh_auto_configure'
    printf 'Configure-only succeeded for Debian %s (arm64).\n' "$suite"
    exit 0
fi

if [[ "$firmware_mode" == prebuilt ]]; then
    /source/docker/debian-arm64/prepare-firmware.sh "$firmware_dir"
elif [[ "$firmware_mode" == source ]]; then
    export QUARTUS_ROOTDIR="$quartus_root"
    nios_root="$(dirname "$quartus_root")/nios2eds"
    export PATH="$quartus_root/bin:$nios_root/bin:$nios_root/sdk2/bin:$PATH"
    cd "$source_dir/hdl/quartus"
    for target in 'bladeRF 40 hostedx40' 'bladeRF 115 hostedx115' \
                  'bladeRF-micro A4 hostedxA4' 'bladeRF-micro A5 hostedxA5' \
                  'bladeRF-micro A9 hostedxA9'; do
        read -r board size filename <<< "$target"
        ./build_bladerf.sh -b "$board" -r hosted -s "$size" -D
        image=$(find . -maxdepth 2 -type f -path "*/hostedx${size}/${filename}.rbf" -print -quit)
        if [[ -z "$image" ]]; then
            image=$(find . -maxdepth 4 -type f -name "${filename}.rbf" -print -quit)
        fi
        if [[ -z "$image" ]]; then
            printf 'FPGA target %s did not produce %s.rbf.\n' "$size" "$filename" >&2
            exit 1
        fi
        install -m 0644 "$image" "$firmware_dir/$filename.rbf"
    done
else
    printf 'Unsupported firmware mode: %s\n' "$firmware_mode" >&2
    exit 2
fi

mkdir -p "$source_dir/debian/firmware"
cp -a "$firmware_dir"/* "$source_dir/debian/firmware/"
if [[ "$firmware_mode" == source ]]; then
    manifest="$source_dir/debian/firmware/firmware-manifest.json"
    cp /source/docker/debian-arm64/firmware-manifest.json "$manifest"
    while IFS= read -r firmware; do
        filename=$(basename "$firmware")
        sha256=$(sha256sum "$firmware" | cut -d' ' -f1)
        jq --arg filename "$filename" --arg sha256 "$sha256" \
            '.firmware |= map(if .filename == $filename then .sha256 = $sha256 | .md5 = null | .version = "source" else . end)' \
            "$manifest" > "$manifest.tmp"
        mv "$manifest.tmp" "$manifest"
    done < <(find "$firmware_dir" -maxdepth 1 -type f ! -name 'firmware-manifest.json' -print)
fi

version=$(dpkg-parsechangelog -S Version)
package_set=(libbladerf2 libbladerf-dev libbladerf-doc libbladerf-udev bladerf)
package_set+=(bladerf-firmware-fx3 bladerf-fpga-hostedx40 bladerf-fpga-hostedx115)
package_set+=(bladerf-fpga-hostedxa4 bladerf-fpga-hostedxa5 bladerf-fpga-hostedxa9)
package_set+=(python3-bladerf bladerf-matlab)
for package in "${package_set[@]}"; do
    rm -f "/workspace/${package}_${version}_"*.deb
done
dpkg-buildpackage --build=binary --host-arch=arm64 --no-sign --jobs="$jobs"

archive_version=${git_describe//-dirty/+dirty}
archive_base="bladerf_${archive_version}_${suite}_arm64"
stage="/workspace/archive-root/$archive_base"
rm -rf "$stage"
mkdir -p "$stage"
deb_outputs=()
for package in "${package_set[@]}"; do
    deb=$(find /workspace -maxdepth 1 -type f -name "${package}_${version}_*.deb" -print -quit)
    if [[ -z "$deb" ]]; then
        printf 'Expected package missing: %s_%s_*.deb\n' "$package" "$version" >&2
        exit 1
    fi
    dpkg-deb -x "$deb" "$stage"
    deb_output="/output/$(basename "$deb")"
    cp -f "$deb" "$deb_output"
    deb_outputs+=("$deb_output")
done

install -d "$stage/usr/share/doc/bladerf"
cp -a debian/firmware/firmware-manifest.json "$stage/usr/share/doc/bladerf/firmware-manifest.json"
cp -a /source/docker/debian-arm64/README.md "$stage/usr/share/doc/bladerf/ARM64-BUILD.md"
install -m 0755 /source/docker/debian-arm64/install-user.sh "$stage/install-user.sh"
install -m 0644 /source/docker/debian-arm64/env.sh "$stage/env.sh"
install -d "$stage/usr/share/bladerf/wheels"
cp -a /workspace/wheels/*.whl "$stage/usr/share/bladerf/wheels/"
wheel_outputs=()
for wheel in /workspace/wheels/*.whl; do
    wheel_output="/output/$(basename "$wheel")"
    cp -a "$wheel" "$wheel_output"
    wheel_outputs+=("$wheel_output")
done
cat > "$stage/usr/share/doc/bladerf/build-manifest.json" <<EOF
{
    "git_describe": "$git_describe",
    "git_revision": "$git_revision",
    "debian_suite": "$suite",
    "host_architecture": "arm64",
    "firmware_mode": "$firmware_mode"
}
EOF
cp -a "$stage/usr/share/doc/bladerf/build-manifest.json" /output/"bladerf_${version}_${suite}_build-manifest.json"
record_outputs=()
for build_record in "/workspace/bladerf_${version}_arm64.buildinfo" "/workspace/bladerf_${version}_arm64.changes"; do
    if [[ -f "$build_record" ]]; then
        cp -f "$build_record" /output/
        record_outputs+=("$(basename "$build_record")")
    fi
done
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
    -C /workspace/archive-root -czf "/output/${archive_base}.tar.gz" "$archive_base"
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
    -C /workspace/archive-root -cjf "/output/${archive_base}.tar.bz2" "$archive_base"

checksum_files=("${archive_base}.tar.gz" "${archive_base}.tar.bz2"
    "bladerf_${version}_${suite}_build-manifest.json")
for artifact in "${deb_outputs[@]}" "${wheel_outputs[@]}" "${record_outputs[@]}"; do
    checksum_files+=("$(basename "$artifact")")
done
(
    cd /output
    sha256sum "${checksum_files[@]}" > "${archive_base}.sha256sum"
)
printf 'Built bladeRF %s for Debian %s arm64 from %s.\n' "$version" "$suite" "$git_revision"