#!/bin/bash
set -e

echo "=== Cleanup Script ==="
echo "This will DELETE all resources in the bug bash environment"
echo ""

RESOURCE_GROUP="${1:-otel-bugbash-rg}"

echo "Resource Group to delete: $RESOURCE_GROUP"
echo ""
echo "WARNING: This action cannot be undone!"
echo ""

read -p "Are you sure you want to delete ALL resources? (type 'yes' to confirm) " -r
echo

if [[ ! $REPLY == "yes" ]]; then
    echo "Cleanup cancelled"
    exit 1
fi

echo "Deleting resource group: $RESOURCE_GROUP"
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo ""
echo "Deletion initiated. This may take several minutes."
echo "To check status:"
echo "  az group show --name $RESOURCE_GROUP"
echo ""
echo "The command will return an error when the resource group is fully deleted."
