"""Iterative Edit Tracking System.

Tracks rejected edits and allows iterative reediting until they pass validation.
Manages backup files for both original content and rejected attempts.

Flow:
1. PRE-TOOL: Saves original file content before edit
2. POST-TOOL: If validation fails:
   - Saves current (broken) content as rejected attempt
   - Restores original from backup
   - Agent corrects the rejected attempt
3. Agent tries again with corrected code
4. Cycle repeats until validation passes
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import NamedTuple

# Hook metadata
HOOK_NAME = "iterative_edit_tracker"
HOOK_VERSION = "1.0.0"

# Constants - Use project directory if available, else global
PROJECT_DIR = Path.cwd() / ".claude"
GLOBAL_DIR = Path.home() / ".claude"
TRACKER_DIR = (PROJECT_DIR if PROJECT_DIR.exists() else GLOBAL_DIR) / ".hooks_state"
STATE_FILE = TRACKER_DIR / "edit_tracking.json"
BACKUP_DIR = TRACKER_DIR / "backups"

# Ensure directories exist
TRACKER_DIR.mkdir(parents=True, exist_ok=True)
BACKUP_DIR.mkdir(parents=True, exist_ok=True)


class PendingEdit(NamedTuple):
    """Represents a pending edit iteration."""

    file_path: str
    original_backup: str
    rejected_attempt: str
    iteration: int
    created_at: float
    violations: list[str]


class IterativeEditTracker:
    """Manages iterative edit tracking with backup/restore.

    Provides centralized tracking of edit iterations and automatic
    backup/restore functionality for iterative corrections.
    """

    def __init__(self, workspace: str = "global"):
        """Initialize tracker.

        Args:
            workspace: Workspace context (default: global)
        """
        self.workspace = workspace
        self.state_file = STATE_FILE
        self.backup_dir = BACKUP_DIR

    def _load_state(self) -> dict:
        """Load current state from file.

        Returns:
            Dict containing current tracking state
        """
        if not self.state_file.exists():
            return {}

        try:
            return json.loads(self.state_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return {}

    def _save_state(self, state: dict) -> None:
        """Save state to file.

        Args:
            state: State dict to save
        """
        try:
            self.state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
        except OSError:
            pass  # Fail silently

    def _get_backup_path(self, file_path: str, suffix: str) -> Path:
        """Get backup file path.

        Args:
            file_path: Original file path
            suffix: Backup suffix (original, rejected, etc)

        Returns:
            Path object for backup file
        """
        file_hash = str(hash(file_path))[-8:]
        timestamp = int(time.time())
        backup_name = f"{file_hash}_{timestamp}_{suffix}.bak"
        return self.backup_dir / backup_name

    def save_original_before_edit(self, file_path: str) -> None:
        """Save original file content before edit.

        Creates a backup of the original file content for potential rollback.

        Args:
            file_path: Path to the file being edited
        """
        try:
            file_obj = Path(file_path)
            if not file_obj.exists():
                return

            # Create backup
            backup_path = self._get_backup_path(file_path, "original")
            backup_path.write_text(file_obj.read_text(encoding="utf-8"), encoding="utf-8")

            # Update state
            state = self._load_state()
            if file_path not in state:
                state[file_path] = {}

            state[file_path]["original_backup"] = str(backup_path)
            state[file_path]["iteration"] = 0
            state[file_path]["created_at"] = time.time()

            self._save_state(state)

        except OSError:
            pass  # Fail silently

    def get_pending_edit(self, file_path: str) -> PendingEdit | None:
        """Get current pending edit info.

        Returns:
            PendingEdit object if edit is pending, None otherwise
        """
        try:
            state = self._load_state()
            if file_path not in state:
                return None

            edit_info = state[file_path]
            original_backup = edit_info.get("original_backup")

            if not original_backup or not Path(original_backup).exists():
                return None

            return PendingEdit(
                file_path=file_path,
                original_backup=original_backup,
                rejected_attempt=edit_info.get("rejected_attempt", ""),
                iteration=edit_info.get("iteration", 0),
                created_at=edit_info.get("created_at", 0),
                violations=edit_info.get("violations", []),
            )

        except Exception:
            return None

    def save_rejected_attempt(self, file_path: str, violations: list[str]) -> None:
        """Save rejected edit attempt.

        Saves the current (broken) version and restores original.

        Args:
            file_path: Path to the file
            violations: List of validation violations
        """
        try:
            state = self._load_state()
            if file_path not in state:
                return

            file_obj = Path(file_path)
            if not file_obj.exists():
                return

            # Save current broken version as rejected attempt
            backup_path = self._get_backup_path(file_path, "rejected")
            backup_path.write_text(file_obj.read_text(encoding="utf-8"), encoding="utf-8")

            # Update state with violations
            edit_info = state[file_path]
            edit_info["rejected_attempt"] = str(backup_path)
            edit_info["iteration"] = edit_info.get("iteration", 0) + 1
            edit_info["violations"] = violations

            self._save_state(state)

            # Restore original for next attempt
            original_backup = edit_info.get("original_backup")
            if original_backup and Path(original_backup).exists():
                original_content = Path(original_backup).read_text(encoding="utf-8")
                file_obj.write_text(original_content, encoding="utf-8")

        except OSError:
            pass  # Fail silently

    def mark_complete(self, file_path: str) -> None:
        """Mark edit as complete and clean up tracking.

        Args:
            file_path: Path to the file
        """
        try:
            state = self._load_state()
            if file_path in state:
                # Clean up backups
                edit_info = state[file_path]
                for key in ["original_backup", "rejected_attempt"]:
                    backup = edit_info.get(key)
                    if backup and Path(backup).exists():
                        Path(backup).unlink()

                # Remove from tracking
                del state[file_path]
                self._save_state(state)

        except OSError:
            pass  # Fail silently

    def cleanup_stale(self, max_age_seconds: int = 86400) -> None:
        """Clean up stale tracking entries.

        Args:
            max_age_seconds: Maximum age of tracking entries (default: 24 hours)
        """
        try:
            state = self._load_state()
            now = time.time()
            files_to_remove = []

            for file_path, edit_info in state.items():
                created_at = edit_info.get("created_at", now)
                if now - created_at > max_age_seconds:
                    files_to_remove.append(file_path)

            for file_path in files_to_remove:
                del state[file_path]

            if files_to_remove:
                self._save_state(state)

        except OSError:
            pass  # Fail silently
