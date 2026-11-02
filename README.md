# publish-marketplace

A GitHub Action to publish **Visual Studio** (the IDE) extensions (.vsix) to the [Visual Studio Marketplace](https://marketplace.visualstudio.com).

Requires a **Windows** runner. The action downloads the latest `Microsoft.VSSDK.BuildTools` package from NuGet on every run to get a current `VsixPublisher.exe` — no Visual Studio installation required on the runner. Drop-in replacement for [VsixPublisherAction](https://github.com/cezarypiatek/VsixPublisherAction) using the same input names and secret.

On a successful publish the action writes a summary card to the workflow run with the extension name, version, and a link to the Marketplace listing.

## Usage

```yaml
- name: Publish to VS Marketplace
  uses: madskristensen/publish-marketplace@v2
  with:
    extension-file: MyExtension.vsix
    publish-manifest-file: vs-publish.json
    personal-access-code: ${{ secrets.VS_PUBLISHER_ACCESS_TOKEN }}
```

## Inputs

| Input | Description |
|-------|-------------|
| `extension-file` | Path to the `.vsix` file to publish |
| `publish-manifest-file` | Path to the `publishManifest.json` file |
| `personal-access-code` | Personal Access Token with Marketplace (Acquire + Manage) permission. **Optional** if using `oidc`. |
| `oidc` | Use GitHub OIDC trusted publishing instead of `personal-access-code`. Defaults to `false`. Requires job permission `id-token: write`. |

### Authentication

**Option 1: Personal Access Token (PAT)**

Store your PAT as a secret named `VS_PUBLISHER_ACCESS_TOKEN`. The token must have **Marketplace → Acquire + Manage** permissions with **All accessible organizations** scope.

```yaml
- name: Publish to VS Marketplace
  uses: madskristensen/publish-marketplace@v2
  with:
    extension-file: MyExtension.vsix
    publish-manifest-file: vs-publish.json
    personal-access-code: ${{ secrets.VS_PUBLISHER_ACCESS_TOKEN }}
```

**Option 2: OIDC (Trusted Publishing)**

For trusted publishing without a stored PAT:

> OIDC requires a `VsixPublisher.exe` with `-oidc` support, verified in `Microsoft.VSSDK.BuildTools` **18.12.465**. At the time of this release, that package is awaiting publication on nuget.org, expected **November 10, 2026**. Until an OIDC-capable package is published there, use PAT authentication. The action downloads the latest stable package on every run, so no workflow change is needed once it becomes available.

1. Open your publisher in [Marketplace publisher management](https://marketplace.visualstudio.com/manage) and create a **Trusted Publishing** policy. Specify the exact repository owner, repository name, and workflow filename (for example, `publish.yml`). If the publishing job uses a GitHub environment, specify that exact environment name in the policy too; otherwise leave it empty.
2. Ensure the `publisher` property in your publish manifest matches the Marketplace publisher that owns the policy.
3. Grant the publishing job `id-token: write` permission, set `oidc: true`, and omit `personal-access-code`. The action cannot grant this permission itself.
4. For a private repository, run the workflow within 48 hours of creating the policy. The first successful token exchange permanently activates it; an expired policy must be reopened before retrying.

The following job assumes the extension has already been built and uploaded as an artifact named `MyExtension.vsix`, and the publish manifest, overview, and referenced assets are in the repository:

```yaml
jobs:
  publish:
    runs-on: windows-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: MyExtension.vsix
      - name: Publish to VS Marketplace
        uses: madskristensen/publish-marketplace@v2
        with:
          extension-file: MyExtension.vsix
          publish-manifest-file: vs-publish.json
          oidc: true
```

The action passes `-oidc` to `VsixPublisher.exe`, which requests a GitHub OIDC token for audience `marketplace.visualstudio.com` and exchanges it for a Marketplace credential valid for 15 minutes. No separate login or PAT is required. Authentication failures stop publishing; there is no fallback to a stored PAT.

Keep your existing PAT secret until the first OIDC publish succeeds, but do not pass it to the OIDC publishing step. After verification, remove the unused secret.

See Microsoft's [Trusted Publishing announcement](https://developer.microsoft.com/blog/trusted-publishing-visual-studio-marketplace/) and [GitHub Actions publishing guide](https://learn.microsoft.com/visualstudio/extensibility/walkthrough-publishing-a-visual-studio-extension-via-command-line#publish-from-github-actions-with-trusted-publishing) for details. This action supports Visual Studio IDE extensions on GitHub Actions, not VS Code extensions or Azure Pipelines.

Use `@v2` for automatic updates within v2, or `@v2.2.0` to pin this release. The action always downloads the latest BuildTools package, even when the action itself is pinned.

## Example workflow

```yaml
jobs:
  publish:
    runs-on: windows-latest
    needs: build
    steps:
      - uses: actions/checkout@v4

      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: MyExtension.vsix

      - name: Publish to VS Marketplace
        if: github.event_name == 'workflow_dispatch' || contains(github.event.head_commit.message, '[release]')
        uses: madskristensen/publish-marketplace@v2
        with:
          extension-file: MyExtension.vsix
          publish-manifest-file: vs-publish.json
          personal-access-code: ${{ secrets.VS_PUBLISHER_ACCESS_TOKEN }}
```

## Tests

Run the dependency-free regression tests on Windows with PowerShell 7:

```powershell
.\tests\action.Tests.ps1
```

The tests execute the action's PowerShell script with mocked downloads and publisher calls; they do not publish an extension or request real credentials.
