# Installation

GeoDE requires Python 3.10 or later.

Once installed, you can run GeoDE from any folder containing the `.cfg` file
with the configuration to access the RINEX and orbits archive, database, etc.
Commands are included in your PATH so you can execute, for example `PlotETM.py
igm1`

## As a Library

GeoDE can be installed using pip:

```bash
pip install geode-gnss
```

This will install the python libraries and dependencies, but does not setup
the database tools.

## As a Development or Production Environment

We recommend using [Pixi](https://pixi.sh/) to manage the Python environment and dependencies.

### 1. Clone the Repository

```bash
git clone https://github.com/demiangomez/Parallel.GAMIT.git
cd geode
```

### 2. Install Dependencies

```bash
pixi install
```

### 3. Activate the Environment

```bash
pixi shell
```

You can deactivate the environment by typing `exit` or pressing Ctrl+D.

### 4. Database Setup

See [Database Setup](docs/installation/database-setup.md) for detailed instructions on:

- Installing and configuring PostgreSQL
- Loading the database schema (`database/schema.sql`)
- Loading seed data (`database/seed.sql`)

### 5. Configuration File

Create `gnss_data.cfg` in your working directory. See [CLI Tools Setup](docs/installation/cli-tools.md) for configuration details.

## External Dependencies

> [!IMPORTANT]
> GeoDE requires access to some executables which are not installed by default. These programs are not all needed if you are planning to just execute time series analysis. The external dependencies are:
> + GAMIT/GLOBK: http://www-gpsg.mit.edu/gg/
> + GFZRNX: https://gnss.gfz-potsdam.de/services/gfzrnx
> + rnx2crx / crx2rnx: https://terras.gsi.go.jp/ja/crx2rnx.html (although this is also installed with GAMIT/GLOBK)
> + GPSPACE: https://github.com/demiangomez/GPSPACE (forked from https://github.com/lahayef/GPSPACE)

## Web Interface (Optional)

To deploy the web interface, see [Web Interface Setup](docs/installation/web-interface.md).
