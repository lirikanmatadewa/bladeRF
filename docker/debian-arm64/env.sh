#!/bin/sh

_bladerf_env_source=${BASH_SOURCE:-$0}
_bladerf_env_path=$(readlink -f -- "$_bladerf_env_source")
BLADERF_ROOT=$(CDPATH= cd -- "$(dirname -- "$_bladerf_env_path")" && pwd)
export BLADERF_ROOT

export PATH="$BLADERF_ROOT/bin:$BLADERF_ROOT/usr/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="$BLADERF_ROOT/usr/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LIBRARY_PATH="$BLADERF_ROOT/usr/lib/aarch64-linux-gnu${LIBRARY_PATH:+:$LIBRARY_PATH}"
export CPATH="$BLADERF_ROOT/usr/include${CPATH:+:$CPATH}"
export PKG_CONFIG_PATH="$BLADERF_ROOT/usr/lib/aarch64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PKG_CONFIG_SYSROOT_DIR="$BLADERF_ROOT"
export CMAKE_PREFIX_PATH="$BLADERF_ROOT/usr${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export BLADERF_DOC_DIR="$BLADERF_ROOT/usr/share/doc/libbladerf-doc/html"
export BLADERF_MATLAB_DIR="$BLADERF_ROOT/usr/share/bladerf/matlab"
export BLADERF_WHEEL_DIR="$BLADERF_ROOT/usr/share/bladerf/wheels"
export BLADERF_FIRMWARE_DIR="$HOME/.config/Nuand/bladeRF"

for _bladerf_python_path in "$BLADERF_ROOT"/usr/lib/python3*/dist-packages; do
	if [ -d "$_bladerf_python_path" ]; then
		PYTHONPATH="$_bladerf_python_path${PYTHONPATH:+:$PYTHONPATH}"
	fi
done
export PYTHONPATH
unset _bladerf_python_path

unset _bladerf_env_source _bladerf_env_path