# Dependency Management: `pyproject.toml` vs `requirements.txt`

## Why two files exist

GeoDE has two dependency manifests that serve different consumers:

| File | Audience | Installed via | Contains |
|---|---|---|---|
| `pyproject.toml` | Library users (`pip install geode-gnss`) | `pip install geode-gnss` | Core scientific/GNSS deps only |
| `web/backend/requirements.txt` | Web-app deployers | `pip install -r requirements.txt` | Django, DRF, Celery, Redis, Gunicorn, **plus** `geode-gnss` itself |

The web backend *consumes* the library. `requirements.txt` lists `geode-gnss`, which
pulls in every dependency declared in `pyproject.toml` transitively. Merging the two
files would mean either:

- **(a)** every `pip install geode-gnss` user also installs Django, Celery, Redis, etc., or
- **(b)** the web app loses its reproducible dependency manifest.

Neither is acceptable. **The files must stay separate.**

## What changed

Four packages previously appeared in **both** files with explicit pins:

| Package | Was in `pyproject.toml` | Was in `requirements.txt` | Risk |
|---|---|---|---|
| `numpy` | `==1.26.4` | `==1.26.4` | Version drift between files causes unresolvable installs |
| `psycopg2-binary` | `==2.9.9` | `==2.9.9` | Same |
| `python-dotenv` | `>=1.0.0` | `==1.0.1` | Web over-constrained; blocked library upgrades |
| `country-converter` | (unpinned) | `==1.3` (as `country_converter`) | Naming mismatch; web pinned tighter than library |

Because `requirements.txt` already depends on `geode-gnss`, pip resolves the library's
own deps automatically. The duplicate pins were redundant at best and conflicting at
worst.

### Changes made

1. **Removed** `numpy==1.26.4`, `psycopg2-binary==2.9.9`, `python-dotenv==1.0.1`, and
   `country_converter==1.3` from `web/backend/requirements.txt`. These are now provided
   transitively via `geode-gnss`.

2. **Added** a comment header to `requirements.txt` explaining the boundary:
   ```
   # Web-backend dependencies only.
   # Core scientific/GNSS deps come transitively via geode-gnss (see pyproject.toml).
   # Do NOT duplicate pyproject.toml pins here.
   ```

3. **Pinned** `country-converter>=1.3` in `pyproject.toml` (was unpinned). The library
   now owns the minimum version floor for this package.

4. **Left `geode-gnss` unpinned** in `requirements.txt`. The web app and library live in
   the same repo and deploy together; a minimum version pin would be maintenance noise.

## How to validate

| Check | Command / Method | Pass criteria |
|---|---|---|
| **No resolver conflicts** | `pip install -r requirements.txt && pip check` | Exit 0, no "has requirement X, but you have Y" |
| **Library installs standalone** | `pip install .` from repo root | Installs without pulling Django/Celery/web deps |
| **Web tests pass** | Run the Django test suite after installing from the cleaned `requirements.txt` | All tests green |
| **No missing imports** | `python -c "import geode"` and start the Django app | No `ModuleNotFoundError` |
| **Transitive versions acceptable** | `pip freeze \| grep -E 'numpy\|psycopg2\|dotenv\|country'` | Versions satisfy both library and web needs |
| **CI pipeline green** | Push branch, check CI | Build + test jobs pass |

## Ongoing policy

- **Library deps** (`pyproject.toml`): use lower-bound pins (`>=`) or compatible-release
  pins (`~=`) so downstream consumers (including the web app) can resolve freely.
- **Web deps** (`requirements.txt`): pin exact versions for reproducibility, but
  **only for packages not already covered by `geode-gnss`**.
- When upgrading a shared dep (e.g., numpy), update **only** `pyproject.toml`. The web
  app inherits the new version transitively.
- Periodically run `pip-compile` or equivalent to regenerate a lockfile and catch
  transitive conflicts early.
