# Contributing to Remote Linux Desktop Deployment

Thank you for your interest in contributing! This guide covers how to submit contributions to this project.

## Ways to Contribute

- **Bug reports** — Found an issue? Open a GitHub issue with details.
- **Feature requests** — Suggest new functionality via GitHub discussions or issues.
- **Pull requests** — Fix bugs, add features, or improve documentation.
- **Documentation** — Improve guides, add examples, fix typos.

## Getting Started

1. **Fork** the repository
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/desktop-seed.git
   cd desktop-seed
   ```
3. **Create a branch** for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Workflow

### Testing Changes

Before deploying, validate script syntax:
```bash
bash -n deploy-desktop.sh
```

### Testing Changes

When making changes:
1. Test locally with `bash -n` to validate syntax
2. Deploy to a test server and verify functionality
3. Commit only after confirming the fix works

### Coding Standards

This project follows the standards in [CLAUDE.md](CLAUDE.md):
- Bash scripts use `set -euo pipefail`
- Functions use lowercase with underscores: `install_vscode()`
- 4-space indentation (no tabs)
- Quote all variables: `"$var"` not `$var`

## Submitting Pull Requests

1. Push your branch:
   ```bash
   git push origin your-branch-name
   ```
2. Open a Pull Request against `main`
3. Describe your changes clearly:
   - What does it fix or add?
   - How did you test it?
   - Any known limitations?

## Commit Messages

Use imperative mood:
```
feat: add Cascade Windows GNOME extension
fix: resolve keyring daemon initialization order
docs: update quick-start guide for Ubuntu 24.04
```

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md). We expect all contributors to maintain a respectful and inclusive environment.

## Questions?

Open a GitHub discussion for general questions. Issues are for bugs and specific feature requests.
