# Dependency Management: `pyproject.toml` vs `requirements.txt`

## Why two files exist

GeoDE has two dependency manifests that serve different consumers:

| File | Audience | Installed via | Contains |
|---|---|---|---|
| `pyproject.toml` | Library users (`pip install geode-gnss`) | `pip install geode-gnss` | Core scientific/GNSS deps only |
| `web/backend/requirements.txt` | Web-app deployers | `pip install -r requirements.txt` | Django, DRF, Celery, Redis, Gunicorn, **plus** `geode-gnss` itself |

The web backend *consumes* the library. `requirements.txt` line 45 (`geode-gnss`) pulls
in every dependency declared in `pyproject.toml` transitively. Merging the two files
would mean either:

- **(a)** every `pip install geode-gnss` user also installs Django, Celery, Redis, etc., or
- **(b)** the web app loses its reproducible dependency manifest.

Neither is acceptable. **The files must stay separate.**

## The problem: double-pinned transitive deps

Today four packages appear in **both** files with explicit pins:

| Package | `pyproject.toml` | `web/backend/requirements.txt` | Risk |
|---|---|---|---|
| `numpy` | `==1.26.4` | `==1.26.4` | Version drift between files causes unresolvable installs |
| `psycopg2-binary` | `==2.9.9` | `==2.9.9` | Same |
| `python-dotenv` | `>=1.0.0` | `==1.0.1` | Web over-constrains; blocks library upgrades |
| `country-converter` | (unpinned) | `==1.3` (as `country_converter`) | Naming mismatch; web pins tighter than library |

Because `requirements.txt` already depends on `geode-gnss`, pip will resolve the
library's own deps automatically. The duplicate pins are redundant at best and
conflicting at worst.

## Refactoring plan

### Step 1 -- Remove double-pinned packages from `requirements.txt`

Delete these four lines from `web/backend/requirements.txt`:

```
numpy==1.26.4          # line 26 -- provided by geode-gnss
psycopg2-binary==2.9.9 # line 28 -- provided by geode-gnss
python-dotenv==1.0.1   # line 32 -- provided by geode-gnss (>=1.0.0)
country_converter==1.3  # line 46 -- provided by geode-gnss
```

After removal, `requirements.txt` should contain **only** web-specific packages plus
the single `geode-gnss` entry.

### Step 2 -- Add a comment block explaining the boundary

At the top of `requirements.txt`, add:

```
# Web-backend dependencies only.
# Core scientific/GNSS deps come transitively via geode-gnss (see pyproject.toml).
# Do NOT duplicate pyproject.toml pins here.
```

### Step 3 -- Pin `geode-gnss` to a minimum version (optional)

If the web app requires a minimum library version, change line 45 to:

```
geode-gnss>=<version>
```

This makes the contract explicit without re-pinning individual transitive deps.

### Step 4 -- Validate with a clean install

Generate a fully resolved lockfile to confirm there are no conflicts:

```bash
# From web/backend/
python -m venv .venv-test
source .venv-test/bin/activate
pip install -r requirements.txt
pip check            # reports broken dependencies
pip freeze > resolved.txt
diff <(sort resolved.txt) <(sort requirements.txt)  # inspect transitive additions
deactivate && rm -rf .venv-test
```

## How to evaluate the refactor

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
