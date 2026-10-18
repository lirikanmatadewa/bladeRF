#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' 'Run this installer as a normal user, not root.' >&2
    exit 1
fi

archive_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bundle_name=$(basename -- "$archive_dir")
install_dir="$HOME/.local/opt/$bundle_name"
user_bin="$HOME/.local/bin"
firmware_dir="$HOME/.config/Nuand/bladeRF"
env_file="$install_dir/env.sh"

if [ ! -d "$archive_dir/usr/bin" ] || [ ! -d "$archive_dir/usr/share/Nuand/bladeRF" ]; then
    printf '%s\n' 'Run this installer from the extracted bladeRF archive containing usr/bin and usr/share/Nuand/bladeRF.' >&2
    exit 1
fi

for source in "$archive_dir"/usr/share/Nuand/bladeRF/*; do
    [ -f "$source" ] || continue
    destination="$firmware_dir/$(basename -- "$source")"
    if [ -e "$destination" ] && [ ! -L "$destination" ]; then
        printf 'Refusing to replace existing firmware file: %s\n' "$destination" >&2
        exit 1
    fi
    if [ -L "$destination" ]; then
        target=$(readlink -- "$destination")
        case "$target" in
            "$HOME/.local/opt/bladerf_"*/usr/share/Nuand/bladeRF/*) ;;
            *)
                printf 'Refusing to replace unrelated firmware link: %s\n' "$destination" >&2
                exit 1
                ;;
        esac
    fi
done

for executable in "$archive_dir"/usr/bin/bladeRF-* "$archive_dir"/usr/bin/bladerf-tool; do
    [ -x "$executable" ] || continue
    command_name=$(basename -- "$executable")
    if [ -e "$user_bin/$command_name" ] && [ ! -L "$user_bin/$command_name" ]; then
        printf 'Refusing to replace existing command: %s\n' "$user_bin/$command_name" >&2
        exit 1
    fi
    if [ -L "$user_bin/$command_name" ]; then
        target=$(readlink -- "$user_bin/$command_name")
        case "$target" in
            "$HOME/.local/opt/bladerf_"*/bin/"$command_name") ;;
            *)
                printf 'Refusing to replace unrelated command link: %s\n' "$user_bin/$command_name" >&2
                exit 1
                ;;
        esac
    fi
done

mkdir -p "$install_dir/usr" "$install_dir/bin" "$user_bin" "$firmware_dir"
cp -R "$archive_dir/usr/." "$install_dir/usr/"
install -m 0644 "$archive_dir/env.sh" "$env_file"

for source in "$install_dir/usr/share/Nuand/bladeRF"/*; do
    [ -f "$source" ] || continue
    ln -sfn "$source" "$firmware_dir/$(basename -- "$source")"
done

for executable in "$install_dir/usr/bin"/bladeRF-* "$install_dir/usr/bin"/bladerf-tool; do
    [ -x "$executable" ] || continue
    command_name=$(basename -- "$executable")
    launcher="$install_dir/bin/$command_name"
    cat > "$launcher" <<'EOF'
#!/bin/sh
set -eu

launcher_path=$(readlink -f -- "$0")
app_root=$(CDPATH= cd -- "$(dirname -- "$launcher_path")/.." && pwd)
executable=$(basename -- "$0")
export LD_LIBRARY_PATH="$app_root/usr/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [ "$executable" = bladerf-tool ]; then
    for python_path in "$app_root"/usr/lib/python3*/dist-packages "$app_root"/usr/lib/python3*/site-packages; do
        if [ -d "$python_path" ]; then
            export PYTHONPATH="$python_path${PYTHONPATH:+:$PYTHONPATH}"
        fi
    done
fi
exec "$app_root/usr/bin/$executable" "$@"
EOF
    chmod 0755 "$launcher"
    ln -sfn "$launcher" "$user_bin/$command_name"
done

printf 'Installed bladeRF to %s\n' "$install_dir"
printf 'Add %s to PATH to use the bladeRF commands.\n' "$user_bin"
printf 'Run . "%s" to set development, documentation, MATLAB, and wheel paths.\n' "$env_file"
printf 'Firmware lookup links are in %s.\n' "$firmware_dir"
printf '%s\n' 'USB access may still require the system udev rules; install libbladerf-udev as an administrator if needed.'