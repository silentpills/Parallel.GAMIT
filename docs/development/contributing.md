# Contributing to Parallel.GAMIT

Thank you for your interest in contributing to Parallel.GAMIT!

## Development Setup

1. **Clone the repository:**
    ```bash
    git clone https://github.com/demiangomez/Parallel.GAMIT.git
    cd Parallel.GAMIT
    ```

2. **Install dependencies with Pixi:**
    ```bash
    pixi install
    pixi shell
    ```

3. **Run tests:**
    ```bash
    pixi run test
    ```

## Code Style

- Follow PEP 8 for Python code
- Use descriptive variable and function names
- Add docstrings to functions and classes
- Include type hints where practical

## Testing

Run the test suite before submitting changes:

```bash
pytest
```

## Documentation

Documentation uses MkDocs with the Material theme.

### Preview documentation locally:

```bash
pixi run docs:serve
```

Then open http://127.0.0.1:8000 in your browser.

### Build documentation:

```bash
pixi run docs:build
```

## Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Make your changes
4. Run tests and linting
5. Commit with descriptive messages
6. Push to your fork
7. Open a Pull Request

## Issue Reporting

When reporting issues, please include:

- Python version
- Operating system
- Steps to reproduce
- Expected vs actual behavior
- Relevant error messages or logs

## Questions

For questions about the codebase or development, open a GitHub issue or discussion.
