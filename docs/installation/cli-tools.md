# CLI Tools Setup

This guide covers configuring and running GeoDE command-line tools for GNSS processing.

## Installation

Install GeoDE in your Python environment:

```bash
pip install geode-gnss
```

Or with Pixi (recommended for development):

```bash
pixi install
pixi shell
```

## Configuration File

Copy the example configuration file to your working directory and customize it:

```bash
cp gnss_data.cfg.example gnss_data.cfg
# Edit gnss_data.cfg with your database credentials and paths
```

GeoDE commands look for `gnss_data.cfg` in the current working directory.

### Configuration Sections

```ini
[postgres]
# Database connection information
hostname = your-db-server.example.com
username = geode
password = your_secure_password
database = geode

# Directory for format scripts (data download processing)
format_scripts_path = /path/to/format_scripts

[archive]
# Absolute location of the RINEX tank
path = /path/to/archive
repository = /path/to/repository

# Orbit file locations (use $year, $doy, $gpsweek, $gpswkday variables)
ionex = /path/to/orbits/ionex/$year
brdc = /path/to/orbits/brdc/$year
sp3 = /path/to/orbits/sp3/$gpsweek

# Hostnames for parallel processing nodes
node_list = node1,node2,node3

# Orbit center type precedence (AC=Analysis Center, CS=campaign, ST=solution type)
sp3_ac = COD,IGS
sp3_cs = OPS,R03,MGX
sp3_st = FIN,SNX,RAP

[otl]
# Ocean tide loading configuration
grdtab = /path/to/gamit/bin/grdtab
otlgrid = /path/to/gamit/tables/otl.grid
otlmodel = FES2014b

[ppp]
# PPP processing configuration
ppp_path = /path/to/PPP_NRCAN
ppp_exe = /path/to/PPP_NRCAN/source/ppp
institution = Your Institution
info = Your Group Name

# Reference frames (comma-separated list)
frames = IGS20,
IGS20 = 1987_1,

# ATX files (same order as frames)
atx = /path/to/resources/atx/igs20_2335_plus.atx
```

## Running Commands

Once configured, run GeoDE from any folder containing the `.cfg` file:

```bash
# Plot ETM for a station
PlotETM.py igm1

# Scan archive for RINEX files
ScanArchive.py igs.all -rinex 1

# Download data for stations
DownloadSources.py rms.all -date 2024.001 2024.365

# Run archive service
ArchiveService.py
```

## Station List Syntax

Most commands accept a station list argument with flexible syntax:

| Format | Description |
|--------|-------------|
| `stnm` | Single station (all networks) |
| `net.stnm` | Station in specific network |
| `net.all` | All stations in network |
| `all` | All stations in database |
| `ARG` | All stations in country (3-letter ISO code) |
| `*net.stnm` | Exclude station from list |
| `ars.at1[3-5]` | Regex range (at13, at14, at15) |
| `ars.at%` | Wildcard (any string) |

## Common Workflows

### Adding RINEX to Database

```bash
# Scan archive and add RINEX files
ScanArchive.py net.all -rinex 0

# Or scan everything (ignore station list)
ScanArchive.py net.all -rinex 1
```

### Running PPP

```bash
# Run PPP for date range
ScanArchive.py net.all -ppp 2024.001 2024.100
```

### Plotting Time Series

```bash
# Interactive plot
PlotETM.py station_code -gui

# Save to directory
PlotETM.py net.all -dir /path/to/output
```

### Downloading Data

```bash
# Download for last 30 days
DownloadSources.py net.all -win 30

# Download specific date range
DownloadSources.py net.all -date 2024/01/01 2024/12/31
```

## Next Steps

- See [CLI Reference](../usage/cli-reference.md) for detailed command documentation
- See [Configuration](../reference/configuration.md) for all configuration options
