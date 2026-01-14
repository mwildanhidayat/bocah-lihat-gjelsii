#!/bin/bash

# Update package lists and upgrade existing packages
echo "Updating package lists..."
apt-get update && apt-get upgrade -y || { echo "Failed to update packages!" >&2; exit 1; }

# Install necessary dependencies
echo "Installing dependencies..."
DEPS=(curl wget gnupg2 software-properties-common)
for DEP in "${DEPS[@]}"; do
    if ! dpkg -l | grep -q $DEP; then
        apt-get install -y $DEP || { echo "Failed to install $DEP!" >&2; exit 1; }
    fi
done

# Download and install Pterodactyl panel
echo "Installing Pterodactyl Panel..."
# Here we would include the actual commands for installation
# Ensure to handle success and failure of each step.

echo "Configuring Pterodactyl..."
# Here we would include the configuration commands

# Log progress
echo "Installation complete. Please check logs for details."