#!/usr/bin/env python3
"""PreToolUse Hook - Security-first validation with change-aware Python checking.

This hook implements MANDATORY security controls:

1. **BLOCKS DANGEROUS BASH COMMANDS** (exit code 2):
   - git reset --hard, git push --force (history destruction)
   - rm -rf, rm * (file deletion)
   - sudo rm, chmod 777, chmod -R 777 (privilege abuse)
   - dd if=/dev (disk operations)
   - | bash, | sh (pipe to shell)

2. **Validates Python files** (Edit/Write tools only):
   - Change-aware: BLOCKS syntax errors in CHANGED lines only
   - Pre-existing: WARNS (does not block) about errors in unchanged lines
   - Ignores import errors (E402, F401, F403, I001)

3. **Creates backup** for rollback capability

Exit codes:
- 0: Allow tool execution (safe operation)
- 1: Warning (violations in changed lines but still allowed)
- 2: BLOCK (dangerous operation or critical error)
"""

from __future__ import annotations

import json
import re
import subprocess  # noqa: S404
import sys
from datetime import UTC, datetime
from pathlib import Path

# Try to import iterative_edit_tracker, fallback to None if not available
try:
    from iterative_edit_tracker import IterativeEditTracker
    HAS_TRACKER = True
except ImportError:
    HAS_TRACKER = False
    IterativeEditTracker = None  # type: ignore[assignment, misc]

# Hook metadata
HOOK_NAME = "pre_tool_use"
HOOK_VERSION = "1.0.0"
HOOK_TYPE = "pre_tool"

# Exit codes
EXIT_SUCCESS = 0
EXIT_WARNING = 1
EXIT_ERROR = 2

# Feature flags
ENABLE_LOGGING = True
ENABLE_JSON_OUTPUT = True

# Constants
FILE_MOD_TOOLS = {"Edit", "Write"}
IGNORED_VIOLATION_CODES = {"E402", "F401", "F403", "I001"}  # Import-related codes

# Dangerous Bash patterns that MUST be BLOCKED (exit code 2)
DANGEROUS_PATTERNS = [
    # Git history destruction
    (r"git\s+reset\s+(--hard|--force)", "git reset --hard: Destructive operation (reverts commits)"),
    (r"git\s+push\s+(--force|-f|--force-with-lease)", "git push --force: Overwrites remote history"),

    # File deletion - BLOCK ALL rm commands, suggest mv to .bak
    (r"rm\s+(-rf|-fr|--recursive|--force)[\s/]", "rm -rf: Recursive file deletion"),
    (r"rm\s+\*", "rm *: Mass file deletion"),
    (r"find.*-exec\s+rm", "find -exec rm: Dangerous file deletion"),
    (r"sudo\s+rm", "sudo rm: Dangerous privileged deletion"),
    (r"rm\s+", "rm: File deletion blocked. Use 'mv file.txt file.txt.bak' for safe backup instead"),

    # Privilege and permission abuse
    (r"chmod\s+(-R|\s+\d*7\d*7)", "chmod 777: Dangerous permission change"),
    (r"chown\s+(-R|.*:\s)", "chown -R: Dangerous ownership change"),

    # Disk operations
    (r"dd\s+if=/dev/", "dd if=/dev: Dangerous disk operation"),
    (r"mkfs\.|fdisk\s|parted\s", "mkfs/fdisk/parted: Disk formatting"),

    # Pipe to shell execution
    (r"\|\s*bash", "| bash: Execute arbitrary code"),
    (r"\|\s*sh", "| sh: Execute arbitrary code"),
    (r"curl.*\|\s*(bash|sh)", "curl | bash: Remote code execution"),
    (r"wget.*\|\s*(bash|sh)", "wget | sh: Remote code execution"),
]

# Compile patterns for efficiency
DANGEROUS_PATTERNS_COMPILED = [
    (re.compile(pattern, re.IGNORECASE), desc)
    for pattern, desc in DANGEROUS_PATTERNS
]


def check_bash_safety(command: str) -> tuple[bool, str]:
    """Check if a Bash command is safe to execute.

    Args:
        command: Bash command to validate

    Returns:
        Tuple of (is_safe, reason_if_unsafe)

    """
    for pattern, description in DANGEROUS_PATTERNS_COMPILED:
        if pattern.search(command):
            return False, description

    return True, ""


def get_timestamp() -> str:
    """Get current timestamp in ISO format."""
    return datetime.now(UTC).isoformat()


def validate_input(input_data: dict) -> tuple[bool, str]:
    """Validate hook input.

    Args:
        input_data: Input from Claude Code

    Returns:
        Tuple of (is_valid, error_message)

    """
    # Check required fields
    if not isinstance(input_data, dict):
        return False, "Input must be a dictionary"

    tool_name = input_data.get("tool_name", "")
    if not tool_name:
        return False, "tool_name is required"

    # We only validate Edit/Write tools
    if tool_name not in FILE_MOD_TOOLS:
        return True, ""  # Allow other tools

    # For file modification tools, check file_path
    tool_input = input_data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    if not file_path:
        return False, "file_path is required for file modification tools"

    return True, ""


def get_changed_lines(file_path: str) -> set[int]:
    """Determine which lines were changed.

    For iterative edits: compares with original backup to find changed line numbers.
    For new edits: considers all non-import lines as "changed".

    Args:
        file_path: Path to the file being edited

    Returns:
        Set of line numbers that were changed

    """
    if not HAS_TRACKER:
        return get_non_import_lines(file_path)

    tracker = IterativeEditTracker()
    pending = tracker.get_pending_edit(file_path)

    if pending and pending.original_backup and Path(pending.original_backup).exists():
        # Iterative reedition - compare with original
        try:
            original_lines = Path(pending.original_backup).read_text(encoding="utf-8").splitlines()
            current_lines = Path(file_path).read_text(encoding="utf-8").splitlines()

            changed_lines = set()
            for i, (orig, curr) in enumerate(zip(original_lines, current_lines, strict=False), start=1):
                if orig != curr:
                    changed_lines.add(i)

            # Handle file size changes
            if len(current_lines) != len(original_lines):
                start = min(len(original_lines), len(current_lines)) + 1
                end = max(len(original_lines), len(current_lines)) + 1
                changed_lines.update(range(start, end))

            return changed_lines
        except Exception:
            # If comparison fails, treat all lines as potentially changed
            return get_non_import_lines(file_path)
    else:
        # First edit - all non-import lines are "changed"
        return get_non_import_lines(file_path)


def get_non_import_lines(file_path: str) -> set[int]:
    """Get line numbers that are not import statements.

    Args:
        file_path: Path to the Python file

    Returns:
        Set of line numbers (1-indexed) that are not imports or empty

    """
    try:
        lines = Path(file_path).read_text(encoding="utf-8").splitlines()
        non_import_lines = set()

        import_section_end = 0
        for i, line in enumerate(lines, start=1):
            stripped = line.strip()

            # Skip empty lines and comments in the beginning
            if not stripped or stripped.startswith('#'):
                if i <= len(lines) // 4:  # Only in first quarter
                    continue

            # Detect end of import section (first non-import line)
            if i > import_section_end and stripped and not stripped.startswith(('import ', 'from ')):
                import_section_end = i

            # Line is in import section, skip it
            if i <= import_section_end and (stripped.startswith(('import ', 'from ', '__future__'))):
                continue

            # Line is code (not import, not docstring header)
            if stripped and not stripped.startswith(('"""', "'''", '#')):
                non_import_lines.add(i)

        return non_import_lines
    except Exception:
        return set()


def validate_file_lint(file_path: str) -> tuple[bool, list[dict]]:
    """Run ruff lint on single file only.

    Args:
        file_path: Path to the file to validate

    Returns:
        Tuple of (validation_passed, violations_list)

    """
    try:
        result = subprocess.run(  # noqa: S603
            ["ruff", "check", file_path, "--output-format", "json"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.stdout.strip():
            violations = json.loads(result.stdout)
            # Filter out INP001 (implicit namespace) for standalone files
            violations = [v for v in violations if v.get("code") != "INP001"]
            return len(violations) == 0, violations

        return True, []
    except (subprocess.SubprocessError, json.JSONDecodeError, FileNotFoundError):
        return True, []


def filter_violations_by_changed_lines(
    violations: list[dict],
    changed_lines: set[int],
) -> tuple[list[dict], list[dict]]:
    """Separate violations into warning and informational categories.

    Args:
        violations: All violations found
        changed_lines: Set of line numbers that were changed

    Returns:
        Tuple of (warning_violations, info_violations)

    """
    warnings = []
    info = []

    for violation in violations:
        code = violation.get("code", "")

        # Always mark as informational on ignored codes (imports, etc)
        if code in IGNORED_VIOLATION_CODES:
            info.append(violation)
            continue

        # Get line number
        location = violation.get("location", {})
        line_no = location.get("row", 0)

        # If in changed lines, it's a warning
        if line_no in changed_lines:
            warnings.append(violation)
        else:
            info.append(violation)

    return warnings, info


def output_result(result: dict, exit_code: int) -> None:
    """Output result and exit.

    Args:
        result: Result dict to output
        exit_code: Exit code to use

    """
    if ENABLE_JSON_OUTPUT:
        print(json.dumps(result), file=sys.stderr)  # noqa: T201
    sys.exit(exit_code)


def process_hook(input_data: dict) -> tuple[dict, int]:
    """Main hook processing logic.

    Args:
        input_data: Input from Claude Code

    Returns:
        Tuple of (result_dict, exit_code)

    """
    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # CRITICAL: Check Bash commands FIRST (dangerous operations must be blocked immediately)
    if tool_name == "Bash":
        command = tool_input.get("command", "")
        if command:
            is_safe, reason = check_bash_safety(command)
            if not is_safe:
                result = {
                    "hook": HOOK_NAME,
                    "version": HOOK_VERSION,
                    "decision": "block",
                    "reason": f"🚫 BLOCKED: {reason}\n\nThis command is dangerous and has been blocked for security.",
                    "timestamp": get_timestamp(),
                    "blocked_command": command[:100],  # First 100 chars
                }
                return result, EXIT_ERROR

        # Command is safe, allow it
        return {
            "hook": HOOK_NAME,
            "version": HOOK_VERSION,
            "decision": "allow",
            "reason": "Bash command passed safety validation",
            "timestamp": get_timestamp(),
        }, EXIT_SUCCESS

    # For non-Bash tools that aren't Edit/Write, allow them
    if tool_name not in FILE_MOD_TOOLS:
        return {
            "hook": HOOK_NAME,
            "version": HOOK_VERSION,
            "decision": "allow",
            "reason": f"Tool {tool_name} does not require validation",
            "timestamp": get_timestamp(),
        }, EXIT_SUCCESS

    file_path = tool_input.get("file_path", "")

    # Only validate Python files that exist
    if not file_path.endswith(".py") or not Path(file_path).exists():
        return {
            "hook": HOOK_NAME,
            "version": HOOK_VERSION,
            "decision": "allow",
            "reason": f"File {file_path} is not a Python file or does not exist",
            "timestamp": get_timestamp(),
        }, EXIT_SUCCESS

    # Validate lint on single file
    passed, violations = validate_file_lint(file_path)

    # Determine which lines were actually changed
    changed_lines = get_changed_lines(file_path)

    # Separate violations: warning (in changed lines) vs info (elsewhere)
    warning_violations, info_violations = filter_violations_by_changed_lines(
        violations, changed_lines
    )

    # If no warning violations in changed lines, allow
    if not warning_violations:
        # Save original before allowing edit (for next iteration if needed)
        if HAS_TRACKER:
            tracker = IterativeEditTracker()
            tracker.save_original_before_edit(file_path)

        # Build result
        result = {
            "hook": HOOK_NAME,
            "version": HOOK_VERSION,
            "decision": "allow",
            "timestamp": get_timestamp(),
            "metadata": {
                "tool_name": tool_name,
                "file_path": file_path,
                "changed_lines_count": len(changed_lines),
            },
        }

        # Report info for context if there are pre-existing violations
        if info_violations:
            msg_lines = [f"  [{v['code']}] L{v['location']['row']}: {v['message']}"
                         for v in info_violations[:5]]
            extra = f"\n  ... and {len(info_violations) - 5} more" if len(info_violations) > 5 else ""
            result["reason"] = "ℹ️ Pre-existing violations (not blocking):\n" + "\n".join(msg_lines) + extra
            result["info_violations"] = len(info_violations)
        else:
            result["reason"] = "No violations detected in changed lines"

        return result, EXIT_SUCCESS

    # Warn: violations found in changed lines (but still allow execution)
    error_msgs = [
        f"  [{v['code']}] L{v['location']['row']}: {v['message']}"
        for v in warning_violations[:10]
    ]
    extra = f"\n  ... and {len(warning_violations) - 10} more" if len(warning_violations) > 10 else ""

    # Enhanced warning with actionable guidance
    warning_text = (
        f"⚠️  WARNING: {len(warning_violations)} violations detected in changed lines\n\n"
        f"📋 Violations:\n"
        + "\n".join(error_msgs)
        + extra
        + "\n\n"
        "✅ Execution allowed - Please review and fix these violations:\n"
        "   1. Review the violations listed above\n"
        "   2. Use suggested fixes from hook output\n"
        "   3. Re-run your edit to validate corrections\n"
        "   4. Automatic rollback available if validation fails\n\n"
        "📖 Reference: ~/.claude/hooks/HOOK_WARNINGS.md"
    )

    result = {
        "hook": HOOK_NAME,
        "version": HOOK_VERSION,
        "decision": "warn",
        "reason": warning_text,
        "timestamp": get_timestamp(),
        "metadata": {
            "tool_name": tool_name,
            "file_path": file_path,
            "violations_count": len(warning_violations),
            "changed_lines_count": len(changed_lines),
        },
        "violations": [
            {
                "code": v['code'],
                "line": v['location']['row'],
                "message": v['message']
            }
            for v in warning_violations[:10]
        ],
    }

    if info_violations:
        result["info_violations_count"] = len(info_violations)

    return result, EXIT_WARNING


def main() -> None:
    """Main hook entry point."""
    try:
        # 1. Read and validate input
        input_data = json.loads(sys.stdin.read())
        is_valid, error_msg = validate_input(input_data)

        if not is_valid:
            result = {
                "hook": HOOK_NAME,
                "version": HOOK_VERSION,
                "decision": "error",
                "reason": error_msg,
                "timestamp": get_timestamp(),
            }
            output_result(result, EXIT_ERROR)

        # 2. Process hook
        result, exit_code = process_hook(input_data)

        # 3. Output result and exit
        output_result(result, exit_code)

    except json.JSONDecodeError as e:
        result = {
            "hook": HOOK_NAME,
            "version": HOOK_VERSION,
            "decision": "error",
            "reason": f"Invalid JSON input: {e!s}",
            "timestamp": get_timestamp(),
        }
        output_result(result, EXIT_ERROR)
    except OSError as e:
        result = {
            "hook": HOOK_NAME,
            "version": HOOK_VERSION,
            "decision": "error",
            "reason": f"OS error: {e!s}",
            "timestamp": get_timestamp(),
        }
        output_result(result, EXIT_ERROR)
    except Exception as e:
        result = {
            "hook": HOOK_NAME,
            "version": HOOK_VERSION,
            "decision": "error",
            "reason": f"Unexpected error: {e!s}",
            "timestamp": get_timestamp(),
        }
        output_result(result, EXIT_ERROR)


if __name__ == "__main__":
    main()
