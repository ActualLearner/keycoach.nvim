# Limit configuration writes to accepted mapping additions

After explicit acceptance, the plugin may append a Mapping Candidate to the user-selected Lua mappings file, but it never rewrites or removes existing configuration. Two alternatives were rejected: a plugin-owned mapping registry under the data directory would keep accepted mappings out of the user's own configuration, and a managed configuration block would make rollback easier. Append-only ownership of a file the user selects preserves user trust and leaves removal under the user's control.
