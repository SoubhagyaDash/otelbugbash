# Repository Security Checklist

Use this checklist before pushing to GitHub or sharing the repository.

## ✅ Pre-Push Verification

### 1. Files Check
- [ ] No `.pem` files in repository
- [ ] No `.key` files in repository  
- [ ] No `id_rsa*` files in repository
- [ ] No `.env` files with real values
- [ ] No `*.tfstate` files
- [ ] No `credentials.json` or `secrets.json`

### 2. Content Check
- [ ] `infrastructure/main.parameters.json` has `YOUR_SSH_PUBLIC_KEY_HERE` placeholder
- [ ] No real IP addresses in code (only placeholders like `<vm-ip>`)
- [ ] No Azure subscription IDs
- [ ] No hardcoded passwords
- [ ] No API keys or tokens
- [ ] No connection strings

### 3. Scripts Check
- [ ] All scripts use parameters, not hardcoded values
- [ ] SSH keys passed as arguments, not embedded
- [ ] ACR passwords fetched at runtime via `az acr credential show`
- [ ] Environment variables used for configuration

### 4. Documentation Check
- [ ] Examples use placeholder values
- [ ] No real deployment outputs (IPs, FQDNs) in docs
- [ ] Security warnings present in README

### 5. Git Configuration
- [ ] `.gitignore` is comprehensive and tested
- [ ] GitHub Actions security workflow present
- [ ] SECURITY.md file present
- [ ] Pre-commit hook script available

## 🔧 Automated Checks

Run these before pushing:

```bash
# 1. Check for secrets in staged files
./scripts/check-for-secrets.sh

# 2. Verify .gitignore is working
git status --ignored

# 3. Search for potential secrets in all files
grep -r "password\s*=" . --exclude-dir=.git --exclude="*.md" || echo "No passwords found"
grep -r "BEGIN.*PRIVATE KEY" . --exclude-dir=.git || echo "No private keys found"

# 4. Check for real IPs (exclude docs and private ranges)
grep -rE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" . \
  --exclude-dir=.git --exclude="*.md" \
  | grep -v "127.0.0.1" \
  | grep -v "0.0.0.0" \
  | grep -v "10.0." \
  | grep -v "10.1." \
  | grep -v "localhost" \
  || echo "No real IPs found"
```

## 📋 Manual Review

### Parameter Files
```bash
cat infrastructure/main.parameters.json
# Verify: sshPublicKey = "YOUR_SSH_PUBLIC_KEY_HERE"
```

### Application Settings
```bash
cat dotnet-service/appsettings.json
# Verify: OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"
```

### Environment Variables
```bash
grep -r "export.*=" scripts/ | grep -i "password\|secret\|key"
# Should return nothing sensitive
```

## 🚨 If Secrets Found

1. **DO NOT PUSH**
2. Remove the secret from the file
3. Update `.gitignore` if needed
4. If already committed locally:
   ```bash
   git reset --soft HEAD~1
   # Edit files to remove secrets
   git add .
   git commit -m "Your message"
   ```
5. If already pushed to GitHub:
   - Rotate all exposed credentials immediately
   - Contact GitHub support to purge from cache
   - Use BFG Repo-Cleaner or git-filter-repo
   - Force push cleaned history

## ✅ Safe to Push Indicators

- ✅ All values are parameters or environment variables
- ✅ `YOUR_*_HERE` placeholders present
- ✅ Scripts use `$VARIABLE` syntax, not hardcoded values
- ✅ `az login` and `az acr credential show` used for auth
- ✅ `.gitignore` tested and working
- ✅ `check-for-secrets.sh` passes
- ✅ No warnings from Git about large files or binaries

## 📝 Final Steps

Before making repository public:

- [ ] Review entire commit history for secrets
- [ ] Test clone on clean machine
- [ ] Verify deployment works with placeholders
- [ ] Update README with fork instructions
- [ ] Add contributing guidelines
- [ ] Enable GitHub security features:
  - [ ] Secret scanning
  - [ ] Dependabot alerts
  - [ ] Code scanning

## 🔄 Regular Maintenance

Monthly:
- [ ] Review `.gitignore` effectiveness
- [ ] Update security documentation
- [ ] Check for new secret patterns
- [ ] Audit access to deployed resources

## 📞 Emergency Contacts

If secrets are exposed:
1. Azure Support: https://azure.microsoft.com/support/
2. GitHub Support: https://support.github.com/
3. Project maintainer: [Your contact]

---

**Last Verified**: [Date]  
**Verified By**: [Name]  
**Next Review**: [Date]
