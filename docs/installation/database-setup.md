# Database Setup

PGAMIT relies heavily on a PostgreSQL database. Ideally, use two systems: one for the PostgreSQL database engine and another for running PGAMIT. While running both on the same computer is possible, it's not recommended for high-efficiency processing.

## Install PostgreSQL

On your database server (can be remote or local):

```bash
sudo apt update
sudo apt install postgresql
```

## Network Configuration

Choose the appropriate configuration based on your setup:

- **Local Setup (Docker on same machine)**: See [Local Development Setup](#local-development-setup)
- **Remote Setup (database on separate server)**: See [Remote Server Setup](#remote-server-setup)

### Local Development Setup

When running PostgreSQL and Docker on the same machine, you need to configure PostgreSQL to accept connections from Docker containers.

#### PostgreSQL Listen Address

Edit `/etc/postgresql/XX/main/postgresql.conf` (replace `XX` with your version):

```bash
# Find your PostgreSQL version
ls /etc/postgresql/

# Edit the config
sudo nano /etc/postgresql/XX/main/postgresql.conf
```

Change:

```
#listen_addresses = 'localhost'
```

To:

```
listen_addresses = 'localhost,172.17.0.1'
```

This allows PostgreSQL to accept connections from the Docker bridge gateway while keeping it off public interfaces.

#### PostgreSQL Client Authentication

Edit `/etc/postgresql/XX/main/pg_hba.conf`:

```bash
sudo nano /etc/postgresql/XX/main/pg_hba.conf
```

Add this line to allow Docker containers to connect:

```
# Docker networks (172.16.x.x - 172.31.x.x)
host    all    pgamit    172.16.0.0/12    md5
```

!!! note
    We use `172.16.0.0/12` instead of `172.17.0.0/16` because Docker Compose creates its own networks in the `172.18.x.x` range, not just the default bridge network.

#### Apply Changes

```bash
sudo systemctl restart postgresql
```

#### Docker Configuration

In your `.env` file, use `host.docker.internal` to reach PostgreSQL on the host:

```
POSTGRES_HOST=host.docker.internal
```

### Remote Server Setup

If using a remote server, it is highly recommended to use a VPN like [Tailscale](https://tailscale.com/) to secure the database connection instead of exposing port 5432 to the public internet.

#### Tailscale Setup (Recommended)

```bash
sudo tailscale serve --bg --tcp=5432 tcp://127.0.0.1:5432
```

#### PostgreSQL Configuration

Edit `pg_hba.conf` to allow connections from your Tailscale network:

```
# Allow Tailscale subnet
host    all    pgamit    100.64.0.0/10    md5
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

3. **Start the web interface** (migrations run automatically):
    ```bash
    docker compose up -d
    ```
    Django migrations run automatically on container startup, adding web UI tables and `api_id` columns.

4. **Login** at `http://localhost:${APP_PORT}` with `admin/admin`

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
