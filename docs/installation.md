# Installation Guide

## Prerequisites

Before installing Parallel.GAMIT, ensure you have the following external dependencies. Some of these require licenses or specific academic access.

1.  **GAMIT/GLOBK**: [http://www-gpsg.mit.edu/gg/](http://www-gpsg.mit.edu/gg/)
2.  **GFZRNX**: [https://gnss.gfz-potsdam.de/services/gfzrnx](https://gnss.gfz-potsdam.de/services/gfzrnx)
    *   *Note for Mac Users:* You may need to allow unsigned software in System Settings > Privacy and Security after downloading. Move the executable to a path like `/usr/local/bin/gfzrnx`.
3.  **RNX2CRX / CRX2RNX**: [https://terras.gsi.go.jp/ja/crx2rnx.html](https://terras.gsi.go.jp/ja/crx2rnx.html) (often included with GAMIT)
4.  **GPSPACE**: [https://github.com/lahayef/GPSPACE](https://github.com/lahayef/GPSPACE) (or the [fork](https://github.com/demiangomez/GPSPACE) used by this project).

## Environment Setup (Pixi)

We recommend using [Pixi](https://prefix.dev/) to manage the Python environment and dependencies.

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/demiangomez/Parallel.GAMIT.git
    cd Parallel.GAMIT
    ```

2.  **Install dependencies:**
    ```bash
    pixi install
    ```

3.  **Activate the shell:**
    ```bash
    pixi shell
    ```

## Database Setup

PGAMIT relies heavily on a PostgreSQL database. The setup can be complex as it involves loading a legacy schema.

### 1. Install PostgreSQL
On your database server (can be remote):
```bash
sudo apt update
sudo apt install postgresql
```

### 2. Network Configuration (Tailscale Recommended)
If using a remote server, it is highly recommended to use a VPN like Tailscale to secure the database connection instead of exposing port 5432 to the public internet.

*   **Tailscale Serve:**
    ```bash
    sudo tailscale serve --bg --tcp=5432 tcp://127.0.0.1:5432
    ```
*   **Postgres Configuration (`pg_hba.conf`):**
    Allow connections from the Tailscale subnet (e.g., `100.64.0.0/10`).

### 3. Schema Loading
**Important:** Do not use the raw `gnss_data_dump.sql` directly if it contains hardcoded owners or insecure settings. Use the provided "clotilde" dump or clean the dump as follows:

1.  **Create User and Database:**
    ```sql
    CREATE USER pgamit WITH PASSWORD 'your_secure_password';
    CREATE DATABASE pgamit OWNER pgamit;
    ```
2.  **Clean the Dump:**
    *   Remove `SET transaction_timeout` lines.
    *   Replace hardcoded owners (e.g., `gnss_data_osu`) with `pgamit` or `postgres`.
3.  **Import:**
    ```bash
    psql -U pgamit -d pgamit -f clean_schema.sql
    ```

See the [Database Setup](database.md) page for a detailed walkthrough of cleaning the schema.

