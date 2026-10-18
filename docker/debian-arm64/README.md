# bladeRF Debian ARM64 packages

Run `docker/debian-arm64/build.sh` from an amd64 Linux host with Docker. The
default build targets Debian Trixie and writes packages and archives to
`build-arm64-trixie-prebuilt/artifacts/`.

Set `BLADERF_ARM64_SUITE=bookworm` to build against Bookworm. Each suite and
firmware mode uses a separate persistent workspace. `BLADERF_BUILD_JOBS` limits
parallel build jobs, and `BLADERF_ARM64_WORKSPACE` selects a custom workspace.
Use `--configure-only` to configure without compiling or fetching firmware.

The default `BLADERF_FIRMWARE_MODE=prebuilt` downloads the pinned upstream FX3
and five hosted FPGA images. Existing Debian package MD5 values are checked
before calculating SHA-256 values for the firmware cache and build manifest.
No firmware is downloaded during package installation.

`BLADERF_FIRMWARE_MODE=source` additionally requires the Cypress FX3 SDK and
Intel Quartus/Nios II installation. Set `BLADERF_CYPRESS_ROOT` to the directory
containing `fx3_firmware_linux/` and `ARM_GCC/arm-2013.11/`, and set
`BLADERF_INTELFPGA_ROOT` to the Intel FPGA installation directory. These vendor
tools are mounted read-only into the build container and are not distributed
by this project. Quartus licensing and the legacy FX3 toolchain/runtime remain
the user's responsibility.

The build requires initialized git submodules. Run
`git submodule update --init --recursive` in the checkout before building; the
builder keeps the source mount read-only. The included hosted FPGA images are
x40, x115, xA4, xA5, and xA9; experimental revisions are excluded.

## User-local archive installation

Both `.tar.gz` and `.tar.bz2` contain the same `usr/` payload and an
`install-user.sh` script. Extract either archive, enter its extracted directory,
and run the script as a normal user:

```sh
tar -xzf bladerf_<version>_trixie_arm64.tar.gz
cd bladerf_<version>_trixie_arm64
./install-user.sh
```

For bzip2 archives, use `tar -xjf` instead. The installer places files under
`~/.local/opt/`, adds launchers under `~/.local/bin/`, and links firmware into
`~/.config/Nuand/bladeRF/` for the current user's libbladeRF search path. Add
`~/.local/bin` to `PATH` if needed. Runtime dependencies are not bundled, and
user-local installation cannot install system udev rules. Install
`libbladerf-udev` as an administrator if USB permissions require it.

For development use, source the installed environment helper:

```sh
. "$HOME/.local/opt/<bundle-directory>/env.sh"
pkg-config --cflags --libs libbladeRF
```

It sets include/library, CMake, pkg-config, documentation, MATLAB, and wheel
paths. The `libbladerf-dev` headers, CMake config, and pkg-config file are
included in the archive. API documentation is available at `$BLADERF_DOC_DIR`.
MATLAB/Octave sources are at `$BLADERF_MATLAB_DIR`; they require a local runtime.
All five FPGA images and FX3 firmware are under the archive's
`usr/share/Nuand/bladeRF` and are linked into `$BLADERF_FIRMWARE_DIR` by the
installer. FPGA images are available there as files; use `bladeRF-cli load_fpga`
or `bladeRF-cli flash_fpga` with the chosen image when needed.

The pure Python wheel is also exported beside the archives. To avoid clashing
with the bundled `bladerf-tool` launcher, install it into a virtual environment:

```sh
python3 -m venv --system-site-packages ~/.venvs/bladerf
. ~/.venvs/bladerf/bin/activate
unset PYTHONPATH
pip install --no-index --no-deps --find-links "$BLADERF_WHEEL_DIR" bladerf
```

Install the wheel's runtime dependency `cffi` from the target distribution
before using it. The wheel contains the Python binding, not libbladeRF itself.
For MATLAB/Octave, add `$BLADERF_MATLAB_DIR` to the runtime path.

Debian package and archive filenames follow `git describe` for the checked-out
revision, with the Debian suite appended separately. The libbladeRF API/ABI
version remains the upstream `2.6.1` base and includes the Git revision suffix
for development builds. A `-dirty` checkout is marked `+dirty` in package
filenames and in the build manifest.

Build Bookworm packages for Bookworm rather than assuming Trixie binaries are
backwards-compatible.