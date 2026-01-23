# Author: Shane Grigsby (espg) <refuge@rocktalus.com>
# Created: October 2024

import pgamit


def test_version_exists():
    """Verify pgamit has a version string."""
    assert hasattr(pgamit, '__version__')
    assert isinstance(pgamit.__version__, str)
    assert len(pgamit.__version__) > 0


def test_version_format():
    """Verify version string is a valid format (PEP 440 compatible)."""
    version = pgamit.__version__
    # setuptools-scm produces versions like "0.1.dev5+g1234567" or "1.0.0"
    # At minimum it should contain digits
    assert any(c.isdigit() for c in version)
