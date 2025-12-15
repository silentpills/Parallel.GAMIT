# Parallel.GAMIT

A Python wrapper to manage GNSS data and metadata and parallelize GAMIT executions.

## Overview

Parallel.GAMIT (PGAMIT) is a Python software solution for parallel GNSS processing of large regional or global networks. It provides:

- **Metadata Management**: Consistent RINEX archive with PostgreSQL backend
- **Parallel Processing**: Distributed GAMIT execution using dispy
- **Network Splitting**: Automatic subnetwork creation for large networks (>50 stations)
- **Web Interface**: Django/React frontend for data visualization and station management
- **Time Series Analysis**: Extended trajectory model fitting and plotting

## Quick Start

```bash
git clone https://github.com/demiangomez/Parallel.GAMIT.git
cd Parallel.GAMIT
pixi install
pixi shell
```

## Documentation

Full documentation: [https://demiangomez.github.io/Parallel.GAMIT/](https://demiangomez.github.io/Parallel.GAMIT/)

### Local Documentation

```bash
pixi run -e docs docs:serve
```

## External Dependencies

PGAMIT requires licensed software not included in this package:

- [GAMIT/GLOBK](http://www-gpsg.mit.edu/gg/) - MIT GPS processing software
- [GFZRNX](https://gnss.gfz-potsdam.de/services/gfzrnx) - RINEX converter
- [GPSPACE](https://github.com/demiangomez/GPSPACE) - PPP processing

## License

BSD-3-Clause

## Citation

See [CITATION.cff](CITATION.cff) for citation information.

## Author

Demián D. Gómez
