# Database Setup

PGAMIT relies heavily on a PostgreSQL database. Ideally, use two systems: one for the PostgreSQL database engine and another for running PGAMIT. While running both on the same computer is possible, it's not recommended for high-efficiency processing.

## Install PostgreSQL

On your database server (can be remote):

```bash
sudo apt update
sudo apt install postgresql
```

## Network Configuration

If using a remote server, it is highly recommended to use a VPN like [Tailscale](https://tailscale.com/) to secure the database connection instead of exposing port 5432 to the public internet.

### Tailscale Setup (Recommended)

```bash
sudo tailscale serve --bg --tcp=5432 tcp://127.0.0.1:5432
```

### PostgreSQL Configuration

Edit `pg_hba.conf` to allow connections from your network:

```
# Allow Tailscale subnet
host    all    all    100.64.0.0/10    md5
```

## Create User and Database

```sql
CREATE USER pgamit WITH PASSWORD 'your_secure_password';
CREATE DATABASE pgamit OWNER pgamit;
```

## Load Schema

Use the clean schema file provided in `database/schema.sql`:

```bash
psql -U pgamit -d pgamit -f database/schema.sql
```

## Load Seed Data

Populate reference tables with initial data:

```bash
psql -U pgamit -d pgamit -f database/seed.sql
```

The seed data includes:

| Table | Description | Source |
|-------|-------------|--------|
| `keys` | Key names used in PGAMIT | `csv/keys.csv` |
| `rinex_tank_struct` | RINEX archive structure | `csv/rinex_tank_struct.csv` |
| `antennas` | IGS antenna codes | `csv/antennas.csv` |
| `receivers` | IGS receiver codes | `csv/receivers.csv` |
| `gamit_htc` | Antenna height/offset codes | `csv/gamit_htc.csv` |

## Complete Setup Order

1. **Load schema** (creates core GNSS tables):
    ```bash
    psql -U pgamit -d pgamit -f database/schema.sql
    ```

2. **Load seed data** (populates reference tables):
    ```bash
    psql -U pgamit -d pgamit -f database/seed.sql
    ```

3. **Run Django migrations** (adds web UI tables + api_id columns):
    ```bash
    docker exec -it gnss-backend python manage.py migrate
    ```

4. **Start the web interface**:
    ```bash
    docker compose up -d
    ```

5. **Login** at `http://localhost:${APP_PORT}` with `admin/admin`

## Recommended RINEX Archive Structure

The `rinex_tank_struct` table defines how RINEX files are organized. The recommended structure is:

| Level | KeyCode |
|-------|---------|
| 1 | network |
| 2 | year |
| 3 | doy |

This organizes files as: `archive/network/year/doy/`

## Troubleshooting

### Permission Issues

Ensure the `pgamit` user has appropriate permissions:

```sql
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO pgamit;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO pgamit;
```

### Connection Issues

1. Check PostgreSQL is listening on the correct interface
2. Verify `pg_hba.conf` allows your connection
3. Test with: `psql -h hostname -U pgamit -d pgamit`
