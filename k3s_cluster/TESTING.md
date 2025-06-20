# Testing Guide for K3S Puppet Module

This guide explains how to test the K3S Puppet module before deployment to catch errors early.

## Pre-Deployment Testing

### Quick Validation

Before deploying to EC2 instances, always run the pre-deployment test:

```bash
cd k3s_cluster
./scripts/pre-deployment-test.sh
```

This script validates:
- ✅ **Puppet manifest syntax** - Ensures no compilation errors
- ✅ **Parameter references** - Catches undefined variable errors  
- ✅ **Token automation** - Validates service name references
- ✅ **Basic compilation** - Tests manifest parsing

### What the Test Catches

The pre-deployment test specifically catches errors like:

1. **Undefined Variable Errors** (like the `server_service_name` bug)
   ```
   Error: Unknown variable: 'k3s_cluster::params::server_service_name'
   ```

2. **Missing Parameter References**
   ```
   Error: Could not find class ::params::nonexistent_param
   ```

3. **Syntax Errors**
   ```
   Error: Syntax error at '=>'; expected '}'
   ```

### Test Output

**✅ Success Output:**
```
🔍 K3S Puppet Module Pre-Deployment Validation
==============================================
✅ PASS: Puppet manifest syntax is valid
✅ PASS: No undefined parameter references found
✅ PASS: Token automation uses correct service name parameter

🚀 Critical issues resolved. Module can be safely deployed to EC2.
```

**❌ Failure Output:**
```
🔍 K3S Puppet Module Pre-Deployment Validation
==============================================
❌ FAIL: Found potential undefined parameter references
manifests/token_automation.pp:49:Service[$k3s_cluster::params::server_service_name]

❌ Please fix the failed tests before deploying to EC2.
```

## Best Practices

### Always Test Before Deployment

```bash
# ❌ Don't do this
puppet apply k3s_config.pp

# ✅ Do this instead  
./scripts/pre-deployment-test.sh && puppet apply k3s_config.pp
```

## Summary

The pre-deployment testing approach ensures:

- 🚀 **Faster feedback** - Catch errors in seconds, not minutes
- �� **Cost savings** - Avoid EC2 instance costs for failed deployments
- 🔒 **Reliability** - Prevent runtime failures in production
- 📊 **Quality** - Maintain high code quality standards

Always run `./scripts/pre-deployment-test.sh` before deploying to EC2!
