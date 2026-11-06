#pragma once
/// Puts this process in the given seatbelt profile (see `man sandbox_init`). Returns 0 on success; on failure,
/// writes a message to `error` (free it with move_sandbox_free_error).
int move_sandbox_apply(const char *profile, char **error);
void move_sandbox_free_error(char *error);
