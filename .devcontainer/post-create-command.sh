#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

echo "[1/3] Installing frontend dependencies..."
npm install || exit $?

echo "[2/3] Installing server dependencies..."
(
  cd server && npm install
) || exit $?

echo "[3/3] Installing Azure CLI extension for k8s deployments..."
if ! az extension show --name connectedk8s >/dev/null 2>&1; then
  az extension add --name connectedk8s --yes || {
    echo "Warning: failed to install Azure CLI extension 'connectedk8s'."
    echo "Install it manually before running k8s deployments: az extension add --name connectedk8s"
  }
fi

echo ""
echo "================================================"
echo " Setup complete! Run 'az login' then 'azd up' to get started."
echo "================================================"
