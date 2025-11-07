# Security Guidelines for Contributors

## ⚠️ NEVER COMMIT THESE

This repository is designed to be safely shared on GitHub. Please ensure you **NEVER** commit:

### 🔑 SSH Keys
- ❌ Private SSH keys (`id_rsa`, `*.pem`, `*.key`)
- ❌ Public SSH keys (keep local only)
- ❌ SSH configuration files with credentials

### 🔐 Secrets & Credentials
- ❌ Azure subscription IDs
- ❌ Azure credentials or service principal keys
- ❌ ACR passwords or tokens
- ❌ API keys or tokens
- ❌ Personal access tokens (PATs)

### 📝 Configuration Files with Secrets
- ❌ `.env` files with real values
- ❌ `*.parameters.local.json` files
- ❌ `appsettings.*.json` with connection strings

### 💾 State Files
- ❌ Terraform state files
- ❌ Azure deployment outputs with IPs/passwords

## ✅ Safe to Commit

The following are safe because they use placeholders:

### Parameter Files
- ✅ `infrastructure/main.parameters.json` - Uses `YOUR_SSH_PUBLIC_KEY_HERE` placeholder
- ✅ `appsettings.json` - Uses `localhost` defaults

### Scripts
- ✅ All shell scripts - Accept parameters, don't hardcode secrets
- ✅ Bicep templates - Use parameters with `@secure()` decorator

### Documentation
- ✅ README files
- ✅ Examples with placeholder values

## 🛡️ Security Best Practices

### For Contributors

1. **Generate Your Own SSH Keys**
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/otelbugbash_rsa
   ```
   Keep these keys LOCAL only!

2. **Use Environment Variables**
   ```bash
   export SSH_KEY=$(cat ~/.ssh/otelbugbash_rsa.pub)
   ./deploy-all.sh rg location "$SSH_KEY"
   ```

3. **Never Commit Real Values**
   - Review changes before committing: `git diff`
   - Use `.gitignore` patterns
   - Double-check with: `git status`

4. **Use Azure CLI Authentication**
   ```bash
   az login  # Uses browser-based auth
   ```
   Scripts will use your logged-in credentials automatically.

### For Bug Bash Participants

1. **Fork the Repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/OtelBugBash.git
   ```

2. **Keep Your Fork Private** (if needed)
   - Go to Settings → Change visibility → Private

3. **Or Use Local Copy Only**
   - No need to push back to GitHub
   - Deploy directly from local clone

4. **Clean Up After Bug Bash**
   ```bash
   ./scripts/cleanup.sh otel-bugbash-rg
   ```

## 🔍 Pre-Commit Checklist

Before committing, verify:

- [ ] No SSH keys in commits
- [ ] No passwords or secrets
- [ ] No real IP addresses (use placeholders like `<vm-ip>`)
- [ ] No subscription IDs
- [ ] Parameter files use placeholders
- [ ] `.gitignore` is working

### Quick Check
```bash
# Search for potential secrets in staged files
git diff --cached | grep -E "(password|secret|key.*=|token)"

# If anything shows up, review carefully!
```

## 🚨 If You Accidentally Commit a Secret

1. **Don't push!** If you haven't pushed yet:
   ```bash
   git reset HEAD~1
   # Remove the secret from the file
   git add .
   git commit -m "Your message"
   ```

2. **If you already pushed:**
   - Rotate the secret immediately (new SSH key, new passwords)
   - Use `git filter-branch` or BFG Repo-Cleaner to remove from history
   - Contact repository maintainers

## 🔐 How This Repository Stays Safe

### Architecture
1. **No Hardcoded Secrets**
   - All secrets passed as parameters
   - Scripts fetch secrets from Azure at runtime

2. **Secure Parameter Decorator**
   ```bicep
   @secure()
   param sshPublicKey string
   ```
   This prevents secrets from appearing in logs.

3. **Runtime Secret Retrieval**
   ```bash
   # Secrets fetched only when needed
   ACR_PASSWORD=$(az acr credential show ...)
   ```

4. **.gitignore Protection**
   - Blocks common secret file patterns
   - Prevents accidental commits

### Deployment Flow
```
User's SSH Key (local) 
    ↓
    Parameter to script
    ↓
    Passed to Bicep
    ↓
    Used for VM setup
    ↓
    Never stored in repo
```

## 📚 Additional Resources

- [GitHub: Removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
- [Azure: Security best practices](https://docs.microsoft.com/azure/security/)
- [OWASP: Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)

## ❓ Questions?

If you're unsure whether something is safe to commit, **don't commit it**. Ask the maintainers first.

---

**Remember**: It's easier to not commit a secret than to remove it from Git history! 🔒
