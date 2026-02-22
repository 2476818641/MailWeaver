# AGENTS.md - Agentic Coding Guidelines for MailWeaver

## Build/Test Commands
This is a Bash/Docker project - no traditional build/test commands. Use these instead:

```bash
# Test scripts (dry run, validation)
bash -n <script>.sh              # Check syntax
shellcheck <script>.sh           # Lint bash scripts (if shellcheck installed)

# Run single service/container for testing
cd build && docker-compose up -d <service>
docker-compose logs -f <service>  # View logs
docker-compose ps                 # Check status

# Docker Compose command detection (both formats supported)
docker compose version &>/dev/null && echo "docker compose" || echo "docker-compose"
```

## Code Style Guidelines

### Bash Scripting Standards

**Header & Setup:**
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"
```

**Imports & Dependencies:**
- Always source `lib/common.lib.sh` for shared functions
- Use `declare -g` for global variable assignment in library functions
- Import before any code execution
- All scripts must start with `#!/bin/bash` (not `/bin/sh`)

**Formatting & Structure:**
- 4-space indentation (no tabs)
- Functions: snake_case (`add_user`, `generate_config`)
- Constants: ALL_CAPS, export from common.lib.sh (`PROJECT_NAME`, `VERSION`)
- Local variables: lowercase snake_case with `local` keyword (`local service_name=""`)
- Case statements for command parsing with help pattern:
  ```bash
  case "$command" in
      add) add_user ;;
      help|--help|-h) show_help ;;
      *) log_error "Unknown command" && exit 1 ;;
  esac
  ```

**Error Handling:**
- Always use `set -euo pipefail` at script start
- Use library functions: `log_info()`, `log_warn()`, `log_error()` (writes to stderr)
- Validate inputs before processing (non-empty, format checks)
- For destructive ops: `prompt_yes_no()` or `confirm_dangerous_operation()`
- Escape SQL inputs: use `escape_sql()` from library
- Passwords must pass `validate_password_strength()` (12+ chars, mix of types)

**Docker Integration:**
- Detect docker compose format: `if docker compose version &>/dev/null`
- Use wrapper functions from lib:
  - `wait_for_service()`, `wait_for_mariadb()`
  - `db_exec()`, `db_exec_ignore_error()`
  - `create_backup()`, `restore_backup()`
- All docker output muted with `2>/dev/null` on non-critical ops
- Use `--quiet` flag with acme.sh certificate requests

**Naming & Conventions:**
- Variables with user input: `prompt_for_input VAR_NAME "Prompt" "default"`
- Password inputs: `prompt_for_password()` or `prompt_for_password_with_confirm()`
- Commands in scripts: subcommand pattern (`./mail-admin.sh add`, `./backup.sh list`)
- Exit codes: 0 for success, 1 for errors

**Database Operations:**
- Always use escaped values in queries: `'$(escape_sql "$value")'`
- Use `db_exec()` wrapper with `-T` flag for non-interactive mode
- Capture output: `local result=$(db_exec "SELECT ...")`
- Handle empty results with `if [[ -z "$result" ]]`

**Security:**
- No eval; use `declare -g` for variable assignment
- Secrets never logged or echoed
- Sensitive files require chmod 400/600 or chmod o-rwx
- Database credentials from .env with `load_env .env`
- `.env` files deleted after installation in build directory

**Dockerfile Style:**
- Minimal base images (`debian:12-slim`, `php:8.2-fpm-alpine`)
- Single layer with && chains, clean apt cache
- EXPOSE only necessary ports
- ENTRYPOINT for container startup script
- Start scripts at `/start.sh` with `chmod +x`

**Testing Verification:**
- Bash syntax: `bash -n script.sh`
- Verify script execution: `./script.sh help`
- Docker operations: check `docker-compose ps`, logs, container status

**Documentation:**
- Every script must have `show_help()` function
- Help shows usage, available commands, examples
- Log messages: INFO (progress), WARN (non-critical), ERROR (failure)
- Chinese language for user-facing messages (per project README)

**Library Functions (from lib/common.lib.sh):**
- Colors: `GREEN`, `RED`, `YELLOW`, `CYAN`, `NC`, `BOLD`
- Logging: `log_info`, `log_warn`, `log_error`, `log_debug`
- Input: `prompt_for_input`, `prompt_for_password`, `prompt_for_password_with_confirm`, `prompt_yes_no`
- Password: `generate_random_string`, `generate_strong_password`, `validate_password_strength`
- URL: `urlencode`
- Docker: `wait_for_service`, `wait_for_mariadb`
- Database: `db_exec`, `db_exec_ignore_error`
- Operations: `create_backup`, `restore_backup`, `confirm_dangerous_operation`
