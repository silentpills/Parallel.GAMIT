# PRIDE PPP-AR Integration Plan

## Executive Summary

This document outlines a comprehensive plan to integrate **PRIDE PPP-AR** as an alternative/replacement PPP backend for Parallel.GAMIT, replacing or supplementing the legacy GPSPACE (NRCAN PPP) software.

### Key Benefits
- **Better accuracy**: <8mm RMSE vs ~cm level for GPSPACE
- **Multi-GNSS support**: GPS, GLONASS, Galileo, BDS-2/3, QZSS
- **Native RINEX 3/4 support**: Eliminates conversion step
- **Ambiguity resolution**: Integer ambiguity fixing for faster convergence
- **Active development**: Regular updates (v3.2.3 as of 2025)
- **Open source**: GPL-3.0 license

---

## 1. Current State Analysis

### 1.1 GPSPACE Integration Overview

The current PPP implementation lives in `pgamit/pyPPP.py` with the `RunPPP` class (lines 160-949).

**Key Interface:**
```python
class RunPPP(PPPSpatialCheck):
    def __init__(self, in_rinex, otl_coeff, options, sp3types, sp3altrn,
                 antenna_height, strict=True, apply_met=True, kinematic=False,
                 clock_interpolation=False, hash=0, erase=True, decimate=True,
                 solve_coordinates=True, solve_troposphere=105,
                 back_substitution=False, elev_mask=10, x=0, y=0, z=0,
                 observations=OBSERV_CODE_PHASE):
        ...

    def exec_ppp(self) -> None:
        """Execute PPP and populate result attributes"""
        ...
```

**Output Attributes:**
| Attribute | Type | Description |
|-----------|------|-------------|
| `x, y, z` | float | ECEF coordinates (meters) |
| `lat, lon, h` | float | Geographic coordinates |
| `sigmax, sigmay, sigmaz` | float | Coordinate uncertainties |
| `sigmaxy, sigmaxz, sigmayz` | float | Covariance elements |
| `clock_phase` | float | Receiver clock estimate |
| `frame` | str | Reference frame (IGS14, IGS20) |
| `record` | dict | Database-ready dictionary |

### 1.2 Current Callers

| File | Location | Purpose |
|------|----------|---------|
| `com/ArchiveService.py` | lines 477-489, 679-688 | New station processing |
| `com/ScanArchive.py` | lines 679-688 | Batch archive reprocessing |
| `com/LocateRinex.py` | lines 302-378 | Standalone PPP + OTL workflow |
| `pgamit/pyRinex.py` | `auto_coord()` method | Quick approximate coordinates |

### 1.3 Current Limitations

1. **GPS-only**: No multi-GNSS support
2. **RINEX 2 only**: Requires v3→v2 conversion (loses multi-GNSS data)
3. **No ambiguity resolution**: Float-only solutions
4. **Legacy codebase**: No longer maintained
5. **Closed source**: Cannot be extended or debugged

---

## 2. PRIDE PPP-AR Overview

### 2.1 Key Features

| Feature | Capability |
|---------|------------|
| GNSS Support | GPS, GLONASS, Galileo, BDS-2/3, QZSS |
| RINEX Support | v2.x, v3.x, v4.x (native) |
| Ambiguity Resolution | Yes (ML-based validation) |
| High-rate Processing | Up to 50 Hz |
| Multi-day Processing | Up to 108 days continuous |
| Accuracy | <8mm RMSE (best in class) |

### 2.2 Command-Line Interface

```bash
pdp3 [options] <rinex_file>

Key Options:
  -m <S|K|F|P>         Processing mode (Static/Kinematic/Fixed/Post-fit)
  -frq <config>        Frequency selection (e.g., "G:12,E:15,C:26")
  -sys <systems>       GNSS systems (e.g., "GREC" for GPS+GLO+GAL+BDS)
  -wcc                 Use Wuhan Combination Center products
  -twnd <start> <end>  Processing time window
  -v                   Verbose output
```

### 2.3 Required Products

| Product | Source | Format |
|---------|--------|--------|
| Orbits | Wuhan University | `WUM0MGXFIN_*_ORB.SP3` |
| Clocks | Wuhan University | `WUM0MGXFIN_*_CLK.CLK` |
| Biases | Wuhan University | `WUM0MGXFIN_*_OSB.BIA` |
| ERP | Wuhan University | `WUM0MGXFIN_*_ERP.ERP` |
| Antenna | IGS | `igs20.atx` |

**Product Server:** `ftp://igs.gnsswhu.cn/pub/whu/phasebias/`

### 2.4 Output Files

| File Pattern | Content |
|--------------|---------|
| `pos_YYYYDDD_ssss` | Static position solution |
| `kin_YYYYDDD_ssss` | Kinematic position time series |
| `ztd_YYYYDDD_ssss` | Zenith tropospheric delay |
| `rck_YYYYDDD_ssss` | Receiver clock estimates |
| `res_YYYYDDD_ssss` | Post-fit residuals |

---

## 3. Architecture Design

### 3.1 Backend Abstraction Pattern

```
                    ┌─────────────────────────┐
                    │   PPPBackend (ABC)      │
                    │  ─────────────────────  │
                    │  + exec_ppp()           │
                    │  + parse_results()      │
                    │  + coordinates          │
                    │  + covariance           │
                    │  + record               │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼────────┐ ┌──────▼───────┐ ┌──────▼───────┐
    │ GPSPACEBackend   │ │ PRIDEBackend │ │ (Future...)  │
    │ (NRCAN PPP)      │ │ (PRIDE PPP-AR│ │              │
    └──────────────────┘ └──────────────┘ └──────────────┘
```

### 3.2 Design Principles

1. **Backward compatibility**: Existing code continues to work unchanged
2. **Configuration-driven**: Backend selection via `gnss_data.cfg`
3. **Factory pattern**: `RunPPP()` function returns appropriate backend
4. **Interface compliance**: All backends implement same interface
5. **Graceful fallback**: If PRIDE fails, can fall back to GPSPACE

### 3.3 New Module Structure

```
pgamit/
├── pyPPP.py              # Refactor: GPSPACEBackend + factory function
├── pyPPPBackend.py       # NEW: Abstract base class
├── pyPPPPride.py         # NEW: PRIDE backend implementation
├── pyProducts.py         # EXTEND: Add Wuhan product sources
└── tests/
    ├── test_ppp_backends.py    # NEW: Backend interface tests
    ├── test_pride_parser.py    # NEW: PRIDE output parsing tests
    └── test_ppp_validation.py  # NEW: Cross-backend validation
```

---

## 4. Implementation Plan

### Phase 1: Core Abstraction Layer

**Deliverables:**
- `pgamit/pyPPPBackend.py` - Abstract base class
- Refactored `pgamit/pyPPP.py` - GPSPACEBackend + factory

**pyPPPBackend.py:**
```python
from abc import ABC, abstractmethod
from typing import Tuple, Dict, Optional
import numpy as np

class PPPBackend(ABC):
    """Abstract base class for PPP processing backends."""

    # Result attributes (set after exec_ppp)
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    lat: float = 0.0
    lon: float = 0.0
    h: float = 0.0
    sigmax: float = 0.0
    sigmay: float = 0.0
    sigmaz: float = 0.0
    sigmaxy: float = 0.0
    sigmaxz: float = 0.0
    sigmayz: float = 0.0
    clock_phase: float = 0.0
    clock_phase_sigma: float = 0.0
    frame: str = ""

    @abstractmethod
    def __init__(self, rinex, otl_coeff: str, options: dict,
                 antenna_height: float, **kwargs):
        """Initialize PPP backend with RINEX file and options."""
        pass

    @abstractmethod
    def exec_ppp(self) -> None:
        """Execute PPP processing. Raises exception on failure."""
        pass

    @abstractmethod
    def __enter__(self):
        """Context manager entry."""
        pass

    @abstractmethod
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit with cleanup."""
        pass

    @property
    def coordinates(self) -> Tuple[float, float, float]:
        """Return ECEF coordinates (x, y, z) in meters."""
        return (self.x, self.y, self.z)

    @property
    def coordinates_geodetic(self) -> Tuple[float, float, float]:
        """Return geodetic coordinates (lat, lon, height)."""
        return (self.lat, self.lon, self.h)

    @property
    def covariance(self) -> np.ndarray:
        """Return 3x3 covariance matrix."""
        return np.array([
            [self.sigmax**2, self.sigmaxy, self.sigmaxz],
            [self.sigmaxy, self.sigmay**2, self.sigmayz],
            [self.sigmaxz, self.sigmayz, self.sigmaz**2]
        ])

    @property
    @abstractmethod
    def record(self) -> Dict:
        """Return database-ready record dictionary."""
        pass
```

**Factory function in pyPPP.py:**
```python
def RunPPP(rinex, otl_coeff, options, sp3types=(), sp3altrn=(),
           antenna_height=0.0, **kwargs):
    """
    Factory function to create appropriate PPP backend.

    Maintains backward compatibility while allowing backend selection.
    """
    backend = options.get('ppp_backend', 'gpspace').lower()

    if backend == 'pride':
        from pgamit.pyPPPPride import PRIDEBackend
        return PRIDEBackend(rinex, otl_coeff, options,
                           antenna_height, **kwargs)

    elif backend == 'auto':
        # Use PRIDE for RINEX 3+, GPSPACE for RINEX 2
        if rinex.rinex_version >= 3:
            from pgamit.pyPPPPride import PRIDEBackend
            return PRIDEBackend(rinex, otl_coeff, options,
                               antenna_height, **kwargs)
        else:
            return GPSPACEBackend(rinex, otl_coeff, options,
                                  sp3types, sp3altrn, antenna_height, **kwargs)

    else:  # 'gpspace' or default
        return GPSPACEBackend(rinex, otl_coeff, options,
                              sp3types, sp3altrn, antenna_height, **kwargs)
```

### Phase 2: PRIDE Backend Implementation

**Deliverable:** `pgamit/pyPPPPride.py`

```python
"""
PRIDE PPP-AR backend for Parallel.GAMIT

Implements PPPBackend interface using PRIDE PPP-AR software.
Supports multi-GNSS (GPS, GLONASS, Galileo, BDS, QZSS) and
native RINEX 2/3/4 processing.
"""

import os
import uuid
import shutil
from pathlib import Path

from pgamit.pyPPPBackend import PPPBackend
from pgamit.Utils import ecef2lla
import pgamit.pyRunWithRetry as pyRunWithRetry


class PRIDEBackend(PPPBackend):
    """PRIDE PPP-AR backend implementation."""

    # PRIDE-specific constants
    DEFAULT_GNSS_SYSTEMS = "G"  # GPS only by default
    DEFAULT_FREQUENCIES = "G:12"  # L1+L2 for GPS

    def __init__(self, rinex, otl_coeff, options, antenna_height,
                 strict=True, kinematic=False, erase=True,
                 solve_coordinates=True, elev_mask=10,
                 observations=2, **kwargs):
        """
        Initialize PRIDE PPP-AR backend.

        Parameters
        ----------
        rinex : pyRinex.ReadRinex
            Input RINEX observation file
        otl_coeff : str
            Ocean tide loading coefficients (BLQ format)
        options : dict
            Configuration options from gnss_data.cfg
        antenna_height : float
            Antenna height offset in meters
        kinematic : bool
            If True, process in kinematic mode
        erase : bool
            If True, cleanup working directory after processing
        elev_mask : int
            Elevation mask angle in degrees
        """
        self.rinex = rinex
        self.otl_coeff = otl_coeff
        self.options = options
        self.antenna_height = antenna_height
        self.kinematic = kinematic
        self.erase = erase
        self.elev_mask = elev_mask
        self.strict = strict
        self.solve_coordinates = solve_coordinates

        # PRIDE-specific configuration
        self.pride_path = options.get('pride_path', '')
        self.pride_exe = options.get('pride_exe', 'pdp3')
        self.pride_products = options.get('pride_products', '')
        self.gnss_systems = options.get('pride_gnss_systems', self.DEFAULT_GNSS_SYSTEMS)
        self.frequencies = options.get('pride_frequencies', self.DEFAULT_FREQUENCIES)
        self.ambiguity_resolution = options.get('pride_ambiguity_resolution', True)

        # Working directory
        self.rootdir = os.path.join('production', 'pride', str(uuid.uuid4()))

        # Output file paths (set during execution)
        self.pos_file = None
        self.kin_file = None
        self.ztd_file = None

        # Initialize
        self._setup()

    def _setup(self):
        """Setup working directory and prepare files."""
        os.makedirs(self.rootdir, exist_ok=True)

        # Copy RINEX file (no conversion needed for PRIDE)
        self.rinex_path = os.path.join(self.rootdir,
                                        os.path.basename(self.rinex.rinex_path))
        shutil.copy(self.rinex.rinex_path, self.rinex_path)

        # Write OTL coefficients if provided
        if self.otl_coeff:
            self._write_otl()

        # Get required products
        self._get_products()

        # Write configuration
        self._write_config()

    def _write_otl(self):
        """Write ocean tide loading file."""
        otl_path = os.path.join(self.rootdir, 'otl.blq')
        with open(otl_path, 'w') as f:
            f.write(self.otl_coeff)

    def _get_products(self):
        """Retrieve Wuhan University products for processing date."""
        # Get date from RINEX
        date = self.rinex.date

        # Product types needed: SP3, CLK, OSB, ERP
        # Implementation will use pyProducts extensions
        # For now, assume products are pre-staged in pride_products path
        pass

    def _write_config(self):
        """Write PRIDE session configuration file."""
        config_path = os.path.join(self.rootdir, 'pride.config')

        # Determine processing mode
        mode = 'K' if self.kinematic else 'S'

        with open(config_path, 'w') as f:
            f.write(f"# PRIDE PPP-AR Configuration\n")
            f.write(f"# Generated by Parallel.GAMIT\n")
            f.write(f"Session mode = {mode}\n")
            f.write(f"GNSS systems = {self.gnss_systems}\n")
            f.write(f"Elevation cutoff = {self.elev_mask}\n")
            f.write(f"Ambiguity resolution = {'Y' if self.ambiguity_resolution else 'N'}\n")

    def _build_command(self):
        """Build PRIDE pdp3 command line."""
        cmd_parts = [self.pride_exe]

        # Processing mode
        mode = 'K' if self.kinematic else 'S'
        cmd_parts.extend(['-m', mode])

        # GNSS systems
        cmd_parts.extend(['-sys', self.gnss_systems])

        # Frequencies
        cmd_parts.extend(['-frq', self.frequencies])

        # Elevation mask
        cmd_parts.extend(['-elev', str(self.elev_mask)])

        # Product directory (if using local products)
        if self.pride_products:
            cmd_parts.extend(['-prd', self.pride_products])

        # Wuhan Combination Center products
        cmd_parts.append('-wcc')

        # Verbose output
        cmd_parts.append('-v')

        # RINEX file
        cmd_parts.append(self.rinex_path)

        return ' '.join(cmd_parts)

    def exec_ppp(self):
        """Execute PRIDE PPP-AR processing."""
        cmd = self._build_command()

        try:
            stdout, stderr, exit_code = pyRunWithRetry.RunCommand(
                cmd, 600, self.rootdir
            ).run_shell()

            if exit_code != 0:
                raise pyRunPPPException(f"PRIDE execution failed: {stderr}")

            # Find and parse output files
            self._find_output_files()
            self._parse_results()

        except Exception as e:
            raise pyRunPPPException(f"PRIDE execution error: {str(e)}")

    def _find_output_files(self):
        """Locate PRIDE output files."""
        # Output filename pattern: {type}_YYYYDDD_{site}
        date_str = self.rinex.date.yyyy() + self.rinex.date.ddd()
        site = self.rinex.StationCode.lower()

        self.pos_file = os.path.join(self.rootdir, f"pos_{date_str}_{site}")
        self.kin_file = os.path.join(self.rootdir, f"kin_{date_str}_{site}")
        self.ztd_file = os.path.join(self.rootdir, f"ztd_{date_str}_{site}")

    def _parse_results(self):
        """Parse PRIDE output files to extract coordinates."""
        if self.kinematic:
            self._parse_kinematic()
        else:
            self._parse_static()

        # Convert ECEF to geodetic
        self.lat, self.lon, self.h = ecef2lla(self.x, self.y, self.z)

    def _parse_static(self):
        """Parse static position file."""
        if not os.path.exists(self.pos_file):
            raise pyRunPPPException(f"Position file not found: {self.pos_file}")

        with open(self.pos_file, 'r') as f:
            for line in f:
                if line.startswith('#') or not line.strip():
                    continue

                parts = line.split()
                # Expected format: X Y Z sigX sigY sigZ ...
                if len(parts) >= 6:
                    self.x = float(parts[0])
                    self.y = float(parts[1])
                    self.z = float(parts[2])
                    self.sigmax = float(parts[3])
                    self.sigmay = float(parts[4])
                    self.sigmaz = float(parts[5])
                    break

        # Set frame (PRIDE uses IGS20 by default)
        self.frame = "IGS20"

    def _parse_kinematic(self):
        """Parse kinematic position file and compute mean."""
        if not os.path.exists(self.kin_file):
            raise pyRunPPPException(f"Kinematic file not found: {self.kin_file}")

        positions = []
        with open(self.kin_file, 'r') as f:
            for line in f:
                if line.startswith('#') or not line.strip():
                    continue

                parts = line.split()
                if len(parts) >= 6:
                    positions.append({
                        'x': float(parts[2]),
                        'y': float(parts[3]),
                        'z': float(parts[4]),
                    })

        if not positions:
            raise pyRunPPPException("No valid epochs in kinematic file")

        # Compute mean position
        import numpy as np
        self.x = np.mean([p['x'] for p in positions])
        self.y = np.mean([p['y'] for p in positions])
        self.z = np.mean([p['z'] for p in positions])

        # Compute standard deviations
        self.sigmax = np.std([p['x'] for p in positions])
        self.sigmay = np.std([p['y'] for p in positions])
        self.sigmaz = np.std([p['z'] for p in positions])

        self.frame = "IGS20"

    @property
    def record(self):
        """Return database-ready record dictionary."""
        return {
            'X': self.x,
            'Y': self.y,
            'Z': self.z,
            'sigmax': self.sigmax,
            'sigmay': self.sigmay,
            'sigmaz': self.sigmaz,
            'sigmaxy': self.sigmaxy,
            'sigmaxz': self.sigmaxz,
            'sigmayz': self.sigmayz,
            'lat': self.lat,
            'lon': self.lon,
            'height': self.h,
            'clock_phase': self.clock_phase,
            'clock_phase_sigma': self.clock_phase_sigma,
            'frame': self.frame,
            'backend': 'pride',
        }

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Cleanup working directory."""
        if self.erase and os.path.exists(self.rootdir):
            shutil.rmtree(self.rootdir, ignore_errors=True)
        return False


class pyRunPPPException(Exception):
    """Base exception for PRIDE PPP errors."""
    pass
```

### Phase 3: Product Management

**Deliverable:** Extensions to `pgamit/pyProducts.py`

```python
# Add to pyProducts.py

class GetWuhanOrbits(OrbitalProduct):
    """
    Retrieve Wuhan University MGEX orbit products.

    Product naming: WUM0MGXFIN_YYYYDDD0000_01D_05M_ORB.SP3
    Server: ftp://igs.gnsswhu.cn/pub/whu/phasebias/
    """

    def __init__(self, archive, date, copyto, product_type='FIN'):
        self.archive = archive
        self.date = date
        self.copyto = copyto
        self.product_type = product_type  # FIN, RAP, or RTS

        self.server = "igs.gnsswhu.cn"
        self.path = f"/pub/whu/phasebias/{date.yyyy()}/orbit/"
        self.filename = self._build_filename()

    def _build_filename(self):
        """Build WUM product filename."""
        return f"WUM0MGX{self.product_type}_{self.date.yyyy()}{self.date.ddd()}0000_01D_05M_ORB.SP3.gz"


class GetWuhanClocks(OrbitalProduct):
    """Retrieve Wuhan University MGEX clock products."""

    def _build_filename(self):
        return f"WUM0MGX{self.product_type}_{self.date.yyyy()}{self.date.ddd()}0000_01D_30S_CLK.CLK.gz"


class GetWuhanBiases(OrbitalProduct):
    """Retrieve Wuhan University phase bias (OSB) products."""

    def _build_filename(self):
        return f"WUM0MGX{self.product_type}_{self.date.yyyy()}{self.date.ddd()}0000_01D_01D_OSB.BIA.gz"


class GetWuhanERP(OrbitalProduct):
    """Retrieve Wuhan University ERP products."""

    def _build_filename(self):
        return f"WUM0MGX{self.product_type}_{self.date.yyyy()}{self.date.ddd()}0000_01D_01D_ERP.ERP.gz"
```

**New script:** `com/SyncWuhanOrbits.py`

```python
"""
Synchronize Wuhan University MGEX products for PRIDE PPP-AR.

Usage:
    python SyncWuhanOrbits.py -date YYYY-MM-DD [-type FIN|RAP]
"""

# Implementation follows SyncOrbits.py pattern
# Downloads: SP3, CLK, OSB, ERP from Wuhan FTP
```

### Phase 4: Configuration Updates

**Update `gnss_data.cfg.example`:**

```ini
[ppp]
# Backend selection: 'gpspace', 'pride', or 'auto'
# 'auto' uses PRIDE for RINEX 3+ files, GPSPACE for RINEX 2
ppp_backend = auto

# === GPSPACE (NRCAN PPP) Configuration ===
ppp_path = /opt/PPP_NRCAN
ppp_exe = /opt/PPP_NRCAN/source/ppp

# === PRIDE PPP-AR Configuration ===
pride_path = /opt/PRIDE-PPPAR
pride_exe = /opt/PRIDE-PPPAR/bin/pdp3
pride_products = /data/products/wuhan

# PRIDE Multi-GNSS options
# Systems: G=GPS, R=GLONASS, E=Galileo, C=BDS, J=QZSS
pride_gnss_systems = GREC

# Frequency selection per constellation
# Format: "SYS:F1F2,SYS:F1F2" (e.g., "G:12,E:15,C:26")
pride_frequencies = G:12,R:12,E:15,C:26

# Enable ambiguity resolution (true/false)
pride_ambiguity_resolution = true

# === Common PPP settings ===
institution = Your Institution
info = Processing Group

# Reference frames
frames = IGS20
IGS20 = 1987_1,

# Antenna calibration
atx = /data/resources/igs20.atx
```

**Update `pgamit/pyOptions.py`:**

```python
# Add to ReadOptions.__init__

# PPP Backend selection
self.options['ppp_backend'] = config.get('ppp', 'ppp_backend', fallback='gpspace')

# PRIDE-specific options
self.options['pride_path'] = config.get('ppp', 'pride_path', fallback='')
self.options['pride_exe'] = config.get('ppp', 'pride_exe', fallback='pdp3')
self.options['pride_products'] = config.get('ppp', 'pride_products', fallback='')
self.options['pride_gnss_systems'] = config.get('ppp', 'pride_gnss_systems', fallback='G')
self.options['pride_frequencies'] = config.get('ppp', 'pride_frequencies', fallback='G:12')
self.options['pride_ambiguity_resolution'] = config.getboolean(
    'ppp', 'pride_ambiguity_resolution', fallback=True
)
```

---

## 5. Testing Strategy

### 5.1 Current Test Coverage

**Existing tests in `pgamit/tests/`:**
- `test_version.py` - Version string validation
- `test_make_clusters.py` - Clustering algorithm tests
- `common.py` - Test utilities

**Gap:** No PPP-specific tests exist.

### 5.2 New Test Files

#### `pgamit/tests/test_ppp_backends.py`

```python
"""
Tests for PPP backend implementations.
"""

import pytest
import numpy as np
from unittest.mock import Mock, patch

from pgamit.pyPPPBackend import PPPBackend
from pgamit.pyPPP import GPSPACEBackend, RunPPP
from pgamit.pyPPPPride import PRIDEBackend


class TestPPPBackendInterface:
    """Verify all backends implement the required interface."""

    def test_gpspace_inherits_from_backend(self):
        """GPSPACEBackend should implement PPPBackend."""
        assert issubclass(GPSPACEBackend, PPPBackend)

    def test_pride_inherits_from_backend(self):
        """PRIDEBackend should implement PPPBackend."""
        assert issubclass(PRIDEBackend, PPPBackend)

    def test_backend_has_required_methods(self):
        """All backends must have exec_ppp, record property."""
        for backend_cls in [GPSPACEBackend, PRIDEBackend]:
            assert hasattr(backend_cls, 'exec_ppp')
            assert hasattr(backend_cls, 'record')
            assert hasattr(backend_cls, 'coordinates')
            assert hasattr(backend_cls, 'covariance')


class TestRunPPPFactory:
    """Test the RunPPP factory function."""

    def test_default_returns_gpspace(self):
        """Default backend should be GPSPACE."""
        with patch.object(GPSPACEBackend, '__init__', return_value=None):
            options = {}
            rinex = Mock()
            result = RunPPP(rinex, "", options, (), (), 0.0)
            assert isinstance(result, GPSPACEBackend)

    def test_pride_option_returns_pride(self):
        """Setting ppp_backend=pride should return PRIDEBackend."""
        with patch.object(PRIDEBackend, '__init__', return_value=None):
            options = {'ppp_backend': 'pride', 'pride_path': '/opt/pride'}
            rinex = Mock()
            result = RunPPP(rinex, "", options, (), (), 0.0)
            assert isinstance(result, PRIDEBackend)

    def test_auto_uses_pride_for_rinex3(self):
        """Auto mode should use PRIDE for RINEX 3+ files."""
        with patch.object(PRIDEBackend, '__init__', return_value=None):
            options = {'ppp_backend': 'auto', 'pride_path': '/opt/pride'}
            rinex = Mock()
            rinex.rinex_version = 3.04
            result = RunPPP(rinex, "", options, (), (), 0.0)
            assert isinstance(result, PRIDEBackend)


class TestBackendCoordinates:
    """Test coordinate property calculations."""

    def test_coordinates_tuple(self):
        """coordinates property should return (x, y, z) tuple."""
        backend = Mock(spec=PPPBackend)
        backend.x = 1000000.0
        backend.y = 2000000.0
        backend.z = 3000000.0
        backend.coordinates = PPPBackend.coordinates.fget(backend)

        assert backend.coordinates == (1000000.0, 2000000.0, 3000000.0)

    def test_covariance_matrix(self):
        """covariance property should return 3x3 matrix."""
        backend = Mock(spec=PPPBackend)
        backend.sigmax = 0.01
        backend.sigmay = 0.02
        backend.sigmaz = 0.015
        backend.sigmaxy = 0.001
        backend.sigmaxz = 0.002
        backend.sigmayz = 0.001
        backend.covariance = PPPBackend.covariance.fget(backend)

        cov = backend.covariance
        assert cov.shape == (3, 3)
        assert np.isclose(cov[0, 0], 0.01**2)
        assert np.isclose(cov[1, 1], 0.02**2)
```

#### `pgamit/tests/test_pride_parser.py`

```python
"""
Tests for PRIDE PPP-AR output file parsing.
"""

import pytest
import tempfile
import os

from pgamit.pyPPPPride import PRIDEBackend


class TestPRIDEStaticParser:
    """Test parsing of PRIDE static position files."""

    @pytest.fixture
    def sample_pos_file(self):
        """Create a sample PRIDE pos file."""
        content = """# PRIDE PPP-AR Position Solution
# Site: TEST
# Date: 2025-001
# Frame: IGS20
-2430567.1234  -4702345.5678  3546789.9012  0.0052  0.0067  0.0043
"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='_pos', delete=False) as f:
            f.write(content)
            return f.name

    def test_parse_static_coordinates(self, sample_pos_file):
        """Should extract X, Y, Z coordinates."""
        backend = PRIDEBackend.__new__(PRIDEBackend)
        backend.pos_file = sample_pos_file
        backend._parse_static()

        assert abs(backend.x - (-2430567.1234)) < 0.0001
        assert abs(backend.y - (-4702345.5678)) < 0.0001
        assert abs(backend.z - 3546789.9012) < 0.0001

        os.unlink(sample_pos_file)

    def test_parse_static_sigmas(self, sample_pos_file):
        """Should extract coordinate uncertainties."""
        backend = PRIDEBackend.__new__(PRIDEBackend)
        backend.pos_file = sample_pos_file
        backend._parse_static()

        assert abs(backend.sigmax - 0.0052) < 0.0001
        assert abs(backend.sigmay - 0.0067) < 0.0001
        assert abs(backend.sigmaz - 0.0043) < 0.0001

        os.unlink(sample_pos_file)


class TestPRIDEKinematicParser:
    """Test parsing of PRIDE kinematic position files."""

    @pytest.fixture
    def sample_kin_file(self):
        """Create a sample PRIDE kin file with multiple epochs."""
        content = """# PRIDE PPP-AR Kinematic Solution
# Columns: MJD SecOfDay X Y Z SigX SigY SigZ
60000.0  0.0  -2430567.100  -4702345.500  3546789.800  0.010  0.012  0.008
60000.0  30.0  -2430567.120  -4702345.520  3546789.820  0.009  0.011  0.007
60000.0  60.0  -2430567.110  -4702345.510  3546789.810  0.011  0.013  0.009
"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='_kin', delete=False) as f:
            f.write(content)
            return f.name

    def test_parse_kinematic_mean_position(self, sample_kin_file):
        """Should compute mean position from epochs."""
        backend = PRIDEBackend.__new__(PRIDEBackend)
        backend.kin_file = sample_kin_file
        backend._parse_kinematic()

        # Mean of three epochs
        expected_x = (-2430567.100 - 2430567.120 - 2430567.110) / 3
        assert abs(backend.x - expected_x) < 0.001

        os.unlink(sample_kin_file)
```

#### `pgamit/tests/test_ppp_validation.py`

```python
"""
Cross-validation tests between PPP backends.

These tests require actual GPSPACE and PRIDE installations.
Mark as slow/integration tests.
"""

import pytest
import os

from pgamit.pyPPP import GPSPACEBackend, RunPPP
from pgamit.pyPPPPride import PRIDEBackend


# Skip if PPP software not installed
GPSPACE_AVAILABLE = os.path.exists('/opt/PPP_NRCAN/source/ppp')
PRIDE_AVAILABLE = os.path.exists('/opt/PRIDE-PPPAR/bin/pdp3')


@pytest.mark.slow
@pytest.mark.integration
class TestBackendEquivalence:
    """Verify GPSPACE and PRIDE produce comparable results."""

    @pytest.fixture
    def sample_rinex2_file(self):
        """Path to a known-good RINEX 2 test file."""
        # Use an IGS station with known coordinates
        return "/data/test/brdc0010.24o"

    @pytest.fixture
    def known_coordinates(self):
        """Known coordinates for test station (ITRF2020)."""
        return {
            'x': -2430234.567,
            'y': -4702384.234,
            'z': 3546587.123,
            'tolerance': 0.05  # 5 cm agreement
        }

    @pytest.mark.skipif(not GPSPACE_AVAILABLE, reason="GPSPACE not installed")
    @pytest.mark.skipif(not PRIDE_AVAILABLE, reason="PRIDE not installed")
    def test_coordinate_agreement(self, sample_rinex2_file, known_coordinates):
        """Both backends should agree within tolerance."""
        options_gpspace = {'ppp_backend': 'gpspace', 'ppp_path': '/opt/PPP_NRCAN'}
        options_pride = {'ppp_backend': 'pride', 'pride_path': '/opt/PRIDE-PPPAR'}

        # Process with GPSPACE
        with RunPPP(sample_rinex2_file, "", options_gpspace, (), (), 0.0) as ppp_gps:
            ppp_gps.exec_ppp()
            gps_coords = ppp_gps.coordinates

        # Process with PRIDE
        with RunPPP(sample_rinex2_file, "", options_pride, (), (), 0.0) as ppp_pride:
            ppp_pride.exec_ppp()
            pride_coords = ppp_pride.coordinates

        # Compare
        tol = known_coordinates['tolerance']
        assert abs(gps_coords[0] - pride_coords[0]) < tol, "X coordinate disagreement"
        assert abs(gps_coords[1] - pride_coords[1]) < tol, "Y coordinate disagreement"
        assert abs(gps_coords[2] - pride_coords[2]) < tol, "Z coordinate disagreement"

    @pytest.mark.skipif(not PRIDE_AVAILABLE, reason="PRIDE not installed")
    def test_pride_matches_known_coordinates(self, sample_rinex2_file, known_coordinates):
        """PRIDE solution should match known station coordinates."""
        options = {'ppp_backend': 'pride', 'pride_path': '/opt/PRIDE-PPPAR'}

        with RunPPP(sample_rinex2_file, "", options, (), (), 0.0) as ppp:
            ppp.exec_ppp()

            tol = known_coordinates['tolerance']
            assert abs(ppp.x - known_coordinates['x']) < tol
            assert abs(ppp.y - known_coordinates['y']) < tol
            assert abs(ppp.z - known_coordinates['z']) < tol


@pytest.mark.slow
@pytest.mark.integration
class TestMultiGNSS:
    """Test PRIDE's multi-GNSS capabilities."""

    @pytest.fixture
    def sample_rinex3_file(self):
        """Path to a RINEX 3 file with multi-GNSS data."""
        return "/data/test/TEST00USA_R_20250010000_01D_30S_MO.rnx"

    @pytest.mark.skipif(not PRIDE_AVAILABLE, reason="PRIDE not installed")
    def test_multi_gnss_processing(self, sample_rinex3_file):
        """PRIDE should process multi-GNSS RINEX 3 without conversion."""
        options = {
            'ppp_backend': 'pride',
            'pride_path': '/opt/PRIDE-PPPAR',
            'pride_gnss_systems': 'GREC',
            'pride_frequencies': 'G:12,R:12,E:15,C:26'
        }

        with RunPPP(sample_rinex3_file, "", options, (), (), 0.0) as ppp:
            ppp.exec_ppp()

            # Should produce valid coordinates
            assert ppp.x != 0.0
            assert ppp.y != 0.0
            assert ppp.z != 0.0

            # Uncertainties should be reasonable (< 10 cm)
            assert ppp.sigmax < 0.10
            assert ppp.sigmay < 0.10
            assert ppp.sigmaz < 0.10
```

### 5.3 Test Data Requirements

| Test File | Description | Source |
|-----------|-------------|--------|
| `brdc0010.24o` | RINEX 2 GPS-only | IGS archive |
| `TEST00USA_R_*.rnx` | RINEX 3 multi-GNSS | IGS MGEX |
| `sample_pos` | PRIDE pos output | Generated |
| `sample_kin` | PRIDE kin output | Generated |

### 5.4 CI/CD Integration

Add to `.github/workflows/test.yml`:

```yaml
jobs:
  test-ppp:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -e .[test]

      - name: Run unit tests
        run: pytest pgamit/tests/test_ppp_backends.py pgamit/tests/test_pride_parser.py -v

      - name: Run integration tests (if PPP available)
        run: pytest pgamit/tests/test_ppp_validation.py -v --ignore-glob="*integration*"
        continue-on-error: true
```

---

## 6. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| PRIDE installation complexity | Medium | Medium | Docker container with pre-installed PRIDE |
| Wuhan product server unavailable | Low | High | Fallback to CDDIS MGEX, local caching |
| Output format changes in PRIDE updates | Low | Medium | Version detection, format validation |
| Performance regression | Low | Low | Benchmark both backends, document expectations |
| Coordinate disagreement between backends | Medium | Medium | Validation tests, tolerance thresholds |

---

## 7. Migration Path

### Stage 1: Parallel Operation (Initial Release)
- Both backends available
- Default: `ppp_backend = gpspace` (no change)
- Users opt-in to PRIDE with configuration

### Stage 2: Auto Mode Default
- Default: `ppp_backend = auto`
- PRIDE for RINEX 3+, GPSPACE for RINEX 2
- 6-month validation period

### Stage 3: PRIDE Default (Optional)
- If validation successful, PRIDE becomes default
- GPSPACE remains available as fallback
- Consider deprecation timeline

---

## 8. Timeline Summary

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Phase 1: Abstraction | 1-2 weeks | `pyPPPBackend.py`, refactored `pyPPP.py` |
| Phase 2: PRIDE Backend | 2 weeks | `pyPPPPride.py` |
| Phase 3: Products | 1 week | Wuhan product classes, `SyncWuhanOrbits.py` |
| Phase 4: Configuration | 1 week | Updated `pyOptions.py`, config examples |
| Phase 5: Testing | 2 weeks | All test files, CI integration |
| **Total** | **7-8 weeks** | Full PRIDE integration |

---

## References

- [PRIDE PPP-AR GitHub](https://github.com/PrideLab/PRIDE-PPPAR)
- [PRIDE PPP-AR Documentation](https://pride.whu.edu.cn/)
- [Wuhan University GNSS Products](ftp://igs.gnsswhu.cn/pub/whu/phasebias/)
- [PPP Software Comparison Study (MDPI)](https://www.mdpi.com/2072-4292/15/8/2034)
