#!/usr/bin/env bash

set -euo pipefail

# Configuration
SOURCE_DIR="./quadlets"
TARGET_USER="ess-deploy"
TARGET_DIR="/home/${TARGET_USER}/.config/containers/systemd"

normalize_file() {
    sed 's/\r$//' "$1"
}

files_match() {
    local src_file="$1"
    local dest_file="$2"

    [[ -f "$dest_file" ]] && cmp -s <(normalize_file "$src_file") "$dest_file"
}

install_normalized_file() {
    local src_file="$1"
    local dest_file="$2"

    normalize_file "$src_file" > "$dest_file"
    chmod 644 "$dest_file"
}

# Ensure target directory exists
install -d -m 755 "$TARGET_DIR"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_DIR"

changed_services=()

# Copy changed files
for service_dir in "$SOURCE_DIR"/*; do
    [[ -d "$service_dir" ]] || continue

    service_name=$(basename "$service_dir")
    target_service_dir="${TARGET_DIR}/${service_name}"
    changed=false

    install -d -m 755 "$target_service_dir"
    chown "$TARGET_USER:$TARGET_USER" "$target_service_dir"

    while IFS= read -r -d '' src_file; do
        relative_path="${src_file#"${service_dir}/"}"
        dest_file="${target_service_dir}/${relative_path}"

        install -d -m 755 "$(dirname "$dest_file")"

        if ! files_match "$src_file" "$dest_file"; then
            install_normalized_file "$src_file" "$dest_file"
            chown "$TARGET_USER:$TARGET_USER" "$dest_file"
            changed=true
        fi
    done < <(find "$service_dir" -type f -print0)

    if $changed; then
        changed_services+=("$service_name")
    fi
done

if [[ ${#changed_services[@]} -eq 0 ]]; then
    echo "No configuration changes detected."
    exit 0
fi

echo "Reloading user systemd daemon..."
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    systemctl --user daemon-reload

for service in "${changed_services[@]}"; do
    unit="${service}.service"

    if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user is-enabled "$unit" >/dev/null 2>&1; then

        echo "Restarting $unit..."
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
            systemctl --user restart "$unit"

    else
        echo "Enabling and starting $unit..."
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
            systemctl --user enable --now "$unit"
    fi
done

echo "Done."