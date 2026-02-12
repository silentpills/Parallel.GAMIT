"""
Shared configuration for GeoDE.

This module is the single source of truth for database connection settings.
Both CLI tools and the Django web interface import from here.

Database credentials are read from environment variables, which can be
populated via a .env file (using python-dotenv) or set directly in the
shell / Docker environment.

Processing-specific configuration (archive paths, OTL, PPP, frames) still
lives in gnss_data.cfg and is read by pyOptions.ReadOptions.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Load .env file (if present).  python-dotenv does NOT override env vars that
# are already set, so Docker / shell env vars always take precedence.
# ---------------------------------------------------------------------------
_env_file = Path.cwd() / ".env"
if _env_file.exists():
    load_dotenv(_env_file)
else:
    # Walk parent directories looking for a .env (useful from subdirs)
    load_dotenv()

# ---------------------------------------------------------------------------
# Database defaults – used only when no env var is set AND no legacy
# gnss_data.cfg [postgres] section supplies a value.
# ---------------------------------------------------------------------------
DB_DEFAULTS = {
    "hostname": "localhost",
    "port": "5432",
    "username": "postgres",
    "password": "",
    "database": "gnss_data",
}

# Mapping from gnss_data.cfg key → environment variable name
_CFG_TO_ENV = {
    "hostname": "POSTGRES_HOST",
    "port": "POSTGRES_PORT",
    "username": "POSTGRES_USER",
    "password": "POSTGRES_PASSWORD",
    "database": "POSTGRES_DB",
}


def get_db_config(cfg_options=None):
    """Return a dict of database connection parameters.

    Resolution order (highest priority wins):
        1. Environment variables  (POSTGRES_HOST, …)
        2. *cfg_options* dict     (from a legacy gnss_data.cfg [postgres] section)
        3. Hard-coded defaults    (DB_DEFAULTS)

    Parameters
    ----------
    cfg_options : dict, optional
        Key/value pairs from a ConfigParser ``[postgres]`` section.
        Used as a fallback for any env var that is not set.
    """
    result = dict(DB_DEFAULTS)

    # Layer 2 – legacy config-file values (if provided)
    if cfg_options:
        for key in DB_DEFAULTS:
            if key in cfg_options:
                result[key] = cfg_options[key]

    # Layer 1 – environment variables (always win)
    for key, env_var in _CFG_TO_ENV.items():
        val = os.getenv(env_var)
        if val:
            result[key] = val

    return result


def get_gnss_data_cfg_path():
    """Return the path to ``gnss_data.cfg``.

    Reads from the ``GNSS_CONFIG_FILE`` environment variable, falling back
    to ``"gnss_data.cfg"`` (relative to cwd, i.e. the project root).
    """
    return os.getenv("GNSS_CONFIG_FILE") or "gnss_data.cfg"
