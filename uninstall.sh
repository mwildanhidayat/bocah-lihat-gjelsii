#!/bin/bash

GITHUB_RAW="https://raw.githubusercontent.com/boca-lihat-gjelsii/Protect-panel/refs/heads/main"
FILES=(
    "ApiController.php"
    "ApiKeyController.php"
    "BuildModificationService.php"
    "ClientServerController.php"
    "DatabaseController.php"
    "DatabaseManagementService.php"
    "DetailsModificationService.php"
    "FileController.php"
    "IndexController.php"
    "LocationController.php"
    "MountController.php"
    "NestController.php"
    "NodeController.php"
    "ReinstallServerService.php"
)

for file in "${FILES[@]}"; do
    echo -n "Testing $file: "
    if curl -s -f "$GITHUB_RAW/$file" > /dev/null; then
        echo "✓ OK"
    else
        echo "✗ FAILED (404)"
    fi
done
