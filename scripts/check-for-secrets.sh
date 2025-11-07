#!/bin/bash

echo "🔍 Checking for potential secrets in staged files..."
echo ""

ERRORS=0

# Check for SSH private keys
if git diff --cached --name-only | xargs grep -l "BEGIN.*PRIVATE KEY" 2>/dev/null; then
    echo "❌ ERROR: SSH private key detected!"
    ERRORS=$((ERRORS + 1))
fi

# Check for common secret patterns in staged changes
PATTERNS=(
    "password\s*=\s*['\"][^'\"]{8,}"
    "secret\s*=\s*['\"][^'\"]{8,}"
    "token\s*=\s*['\"][^'\"]{8,}"
    "apikey\s*=\s*['\"][^'\"]{8,}"
    "api_key\s*=\s*['\"][^'\"]{8,}"
    "-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----"
    "[0-9a-f]{32,}"  # Long hex strings (potential tokens)
)

for pattern in "${PATTERNS[@]}"; do
    if git diff --cached | grep -iE "$pattern" | grep -v "YOUR_.*_HERE" | grep -v "placeholder" | grep -v "example" >/dev/null 2>&1; then
        echo "⚠️  WARNING: Potential secret pattern found: $pattern"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check for real IP addresses (not localhost or placeholders)
if git diff --cached | grep -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | grep -v "127.0.0.1" | grep -v "0.0.0.0" | grep -v "localhost" | grep -v "<.*-ip>" | grep -v "10.0." | grep -v "10.1." >/dev/null 2>&1; then
    echo "⚠️  WARNING: Real IP address detected (verify it's not sensitive)"
    ERRORS=$((ERRORS + 1))
fi

# Check for Azure subscription IDs
if git diff --cached | grep -iE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | grep -v "example" | grep -v "00000000-0000-0000-0000-000000000000" >/dev/null 2>&1; then
    echo "⚠️  WARNING: Potential Azure subscription ID or GUID detected"
    ERRORS=$((ERRORS + 1))
fi

# Check for ssh-rsa public keys (should not be in repo)
if git diff --cached | grep "ssh-rsa AAAA" >/dev/null 2>&1; then
    echo "⚠️  WARNING: SSH public key detected (verify it's a placeholder)"
    ERRORS=$((ERRORS + 1))
fi

# Check specific files that should never be committed
FORBIDDEN_FILES=(
    "*.pem"
    "*.key"
    "*id_rsa*"
    "*.tfstate"
    ".env"
    "credentials.json"
    "secrets.json"
)

for pattern in "${FORBIDDEN_FILES[@]}"; do
    if git diff --cached --name-only | grep -E "$pattern" >/dev/null 2>&1; then
        echo "❌ ERROR: Forbidden file type staged: $pattern"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ No obvious secrets detected. Safe to commit!"
    exit 0
else
    echo "❌ Found $ERRORS potential issue(s). Please review before committing."
    echo ""
    echo "To see what's staged:"
    echo "  git diff --cached"
    echo ""
    echo "To unstage files:"
    echo "  git reset HEAD <file>"
    echo ""
    echo "If you're sure these are safe (e.g., placeholders), you can proceed."
    exit 1
fi
