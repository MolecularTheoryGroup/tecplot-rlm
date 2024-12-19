#!/bin/bash

CONFIG_DIR="/etc/rlm"
INSTALL_DIR="/opt/rlm"
LICENSE_FILE="tecplotlm.lic"
HOSTIDS_FILE="myhostids.txt"

# Function to copy .opt files from install dir to config dir if they don't exist
init_opt_files() {
    for opt_file in "${INSTALL_DIR}"/*.opt; do
        if [ -f "$opt_file" ]; then
            filename=$(basename "$opt_file")
            if [ ! -f "${CONFIG_DIR}/${filename}" ]; then
                echo "Copying ${filename} to config directory..."
                cp "$opt_file" "${CONFIG_DIR}/${filename}"
            fi
        fi
    done
}

# Function to copy .opt files from config dir to install dir
update_opt_files() {
    for opt_file in "${CONFIG_DIR}"/*.opt; do
        if [ -f "$opt_file" ]; then
            filename=$(basename "$opt_file")
            echo "Updating ${filename} in installation directory..."
            cp "$opt_file" "${INSTALL_DIR}/${filename}"
        fi
    done
}

# Function to restart RLM
restart_rlm() {
    echo "Restarting RLM server..."
    bash ${INSTALL_DIR}/rlm_process stop
    bash ${INSTALL_DIR}/rlm_process start
}

# Function to monitor license file for changes
monitor_license() {
    echo "Monitoring license file..."
    while true; do
        inotifywait -e modify,create "${CONFIG_DIR}/${LICENSE_FILE}" 2>/dev/null
        echo "License file change detected"
        cp "${CONFIG_DIR}/${LICENSE_FILE}" "${INSTALL_DIR}/${LICENSE_FILE}"
        echo "Running rlmreread..."
        ${INSTALL_DIR}/rlmutil rlmreread
    done
}

# Monitor .opt files for changes
monitor_opt_files() {
    echo "Monitoring .opt files..."
    while true; do
        inotifywait -e modify,create,delete "${CONFIG_DIR}"/*.opt 2>/dev/null
        echo "Option file change detected"
        update_opt_files
        restart_rlm
    done
}

# Function to monitor log files
monitor_logs() {
    declare -A tail_pids

    while true; do
        # Check for new log files
        for log_file in "${INSTALL_DIR}"/*.log; do
            if [ -f "$log_file" ]; then
                filename=$(basename "$log_file")
                if [ -z "${tail_pids[$filename]}" ] || ! kill -0 "${tail_pids[$filename]}" 2>/dev/null; then
                    echo "Starting monitoring of ${filename}..."
                    tail -f "$log_file" &
                    tail_pids[$filename]=$!
                fi
            fi
        done

        # Clean up tail processes for removed log files
        for filename in "${!tail_pids[@]}"; do
            if [ ! -f "${INSTALL_DIR}/${filename}" ]; then
                echo "Log file ${filename} no longer exists, stopping monitoring..."
                kill "${tail_pids[$filename]}" 2>/dev/null
                unset tail_pids[$filename]
            fi
        done

        sleep 1
    done
}

# Function to copy documentation files to config directory
init_docs() {
    echo "Copying documentation files to config directory..."
    for doc in "${INSTALL_DIR}"/*.pdf "${INSTALL_DIR}"/*.html "${INSTALL_DIR}"/README.pw; do
        if [ -f "$doc" ]; then
            filename=$(basename "$doc")
            if [ ! -f "${CONFIG_DIR}/${filename}" ]; then
                echo "Copying ${filename} to config directory..."
                cp "$doc" "${CONFIG_DIR}/${filename}"
            fi
        fi
    done
}

# Initialize documentation files
init_docs

# Initialize .opt files
init_opt_files

# Update .opt files at startup
update_opt_files

# Backup existing host IDs file if it exists
if [ -f "${CONFIG_DIR}/${HOSTIDS_FILE}" ]; then
    echo "Backing up existing ${HOSTIDS_FILE} to ${HOSTIDS_FILE}.bak"
    mv -f "${CONFIG_DIR}/${HOSTIDS_FILE}" "${CONFIG_DIR}/${HOSTIDS_FILE}.bak"
fi

# Run gethostids.sh
echo "Running gethostids.sh..."
sh ${INSTALL_DIR}/gethostids.sh ${CONFIG_DIR}

# Verify and display host IDs file
if [ ! -f "${CONFIG_DIR}/${HOSTIDS_FILE}" ]; then
    echo "Error: Host IDs file ${HOSTIDS_FILE} was not created in ${CONFIG_DIR}"
    exit 1
fi

echo "Host IDs file created successfully. Contents:"
echo "----------------------------------------"
cat "${CONFIG_DIR}/${HOSTIDS_FILE}"
echo "----------------------------------------"

# Also run `rlmutil rlmhostid` to display host IDs
echo "Running 'rlmutil rlmhostid' for comparison..."
${INSTALL_DIR}/rlmutil rlmhostid

# Check for license file
if [ ! -f "${CONFIG_DIR}/${LICENSE_FILE}" ]; then
    echo "Error: License file ${LICENSE_FILE} not found in ${CONFIG_DIR}"
    echo "Please obtain a license file and place it in the config directory"
    exit 1
fi

# Link or copy license file to installation directory
echo "Installing license file..."
cp "${CONFIG_DIR}/${LICENSE_FILE}" "${INSTALL_DIR}/${LICENSE_FILE}"

# Start log monitoring in background
monitor_logs &
LOG_MONITOR_PID=$!

# Start .opt file monitoring in background
monitor_opt_files &
OPT_MONITOR_PID=$!

# Start license file monitoring in background
monitor_license &
LICENSE_MONITOR_PID=$!

# Sleep for a bit to let logs start
sleep 1

# Start RLM
echo "Starting RLM..."
bash ${INSTALL_DIR}/rlm_process start &

# Give RLM a moment to start
sleep 2

# Monitor port 5054
echo "Monitoring RLM on port 5054..."
while true; do
    if ! netstat -tln | grep -q ':5054 '; then
        echo "RLM is no longer listening on port 5054"
        break
    fi
    sleep 5
done

# If RLM process exits, kill all monitoring processes
echo "Killing monitoring processes..."
kill $LOG_MONITOR_PID
kill $OPT_MONITOR_PID
kill $LICENSE_MONITOR_PID

# Copy *.log files to config directory
echo "Copying log files to config directory..."
cp "${INSTALL_DIR}"/*.log "${CONFIG_DIR}/"

echo "Exiting..."
exit 1