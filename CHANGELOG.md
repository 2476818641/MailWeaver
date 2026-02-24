# Changelog

All notable changes to the MailWeaver project will be documented in this file.

## [1.7.1-alpha] - 2026-02-24

### 🔒 Security Enhancements
- Added strict file permissions for SSL certificates (chmod 600)
- Unified password policy to 12+ characters with mixed types
- Optimized configuration file permissions
- Added input validation for domains, emails, and FQDNs

### ⚡ Performance Optimizations
- Cached Docker Compose command detection results
- Reduced redundant command executions
- Simplified configuration generation logic

### 🔧 Code Quality
- Removed redundant sed replacements in configuration generation
- Extracted startup scripts to `templates/diy/` directory
- Implemented unified logging system
- Added operation logging for critical actions

### 🛡️ Error Handling
- Added automatic rollback on SSL certificate request failures
- Improved database initialization error handling
- Added Docker image build failure logging
- Implemented trap-based error catching mechanism

### ✅ Reliability
- Added configuration validation mechanisms
- Optimized container status detection
- Made health check timeout configurable
- Enhanced logging system

### 📝 Documentation
- Added `log.md` optimization task tracking document
- Created `templates/.env.example` configuration template
- Added startup script templates (postfix, dovecot, roundcube)

### 🧪 Testing
- All scripts passed `bash -n` syntax validation
- Verified error handling mechanisms
- Tested logging system functionality

### 📊 Changes Summary
- Modified: 6 files
- Added: 4 files
- Total: 11 files changed, 1075 insertions(+), 102 deletions(-)
- Completed: 17 optimization tasks (9 high priority + 8 medium priority)

### ⚠️ Breaking Changes
- Password policy increased from 8 to 12 characters (new users only)
- Existing users are not affected

### ✅ Compatibility
- Fully backward compatible
- All existing functionality preserved
- New validation is optional and does not enforce blocking
- Timeout parameters have sensible defaults

## [1.7.0] - Previous Release
- Initial release with Mailu and DIY deployment options
- Basic user management and backup functionality
- SSL certificate automation
- ViMbAdmin integration for DIY solution

---

## Version History

| Version | Date | Status | Notes |
|---------|------|--------|-------|
| 1.7.1-alpha | 2026-02-24 | Alpha | Security enhancements and code quality improvements |
| 1.7.0 | - | Stable | Initial release |

---

## Release Notes

### Alpha Branch
The alpha branch (v1.7.1-alpha) contains new features and improvements that are currently under testing. Please report any issues found.

### Main Branch
The main branch (v1.7.0) contains the stable production release.

---

## Contributing

For guidelines on contributing to the project, please refer to AGENTS.md.