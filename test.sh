#!/usr/bin/env bash

# test.sh - Script test các function cơ bản
# Dùng để debug và kiểm tra trước khi deploy chính

echo "=== TEST SCRIPT ==="

# Source các file cần thiết
source "./lib/common.sh"
source "./lib/check_environment.sh"

echo -e "\n1. Testing color output..."
success_message "This is a success message"
error_message "This is an error message"
warning_message "This is a warning message"
info_message "This is an info message"

echo -e "\n2. Testing OS detection..."
if detect_os; then
    echo "OS detected: $OStype"
else
    echo "OS detection failed"
fi

echo -e "\n3. Testing network interface detection..."
interface=$(detect_network_interface)
if [[ $? -eq 0 ]]; then
    echo "Interface detected: $interface"
else
    echo "Interface detection failed"
fi

echo -e "\n4. Testing squid installation check..."
if is_squid_installed; then
    echo "Squid is installed"
else
    echo "Squid is not installed"
fi

echo -e "\n5. Testing debug squid status..."
debug_squid_status

echo -e "\n=== TEST COMPLETED ===" 