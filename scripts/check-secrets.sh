# Pre-Commit Security Check

This script helps verify that no secrets are being committed to the repository.

## Usage

Run this before committing:

```bash
./check-secrets.sh
```

Add to git pre-commit hook (optional):

```bash
cp check-secrets.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## What It Checks

- SSH private keys
- Azure credentials
- Passwords in configuration files
- Real IP addresses or endpoints
- Access tokens

## Exit Codes

- 0: All clear, safe to commit
- 1: Potential secrets found, review before committing
