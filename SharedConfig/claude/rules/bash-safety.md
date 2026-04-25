# Bash: Never combine cd with other commands

NEVER use `cd /path && command` or `cd /path; command`.

Always `cd` first in a separate Bash call, then run the command.
The working directory persists between calls.

This is required for permission auto-approval whitelisting to work correctly.
