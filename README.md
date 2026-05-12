# publish-marketplace

A GitHub Action to publish **Visual Studio** (the IDE) extensions (.vsix) to the [Visual Studio Marketplace](https://marketplace.visualstudio.com).

Requires a **Windows** runner. Uses `VsixPublisher.exe` from the Visual Studio installation (already present on `windows-latest` runners) — no extra tools or dependencies required. Drop-in replacement for [VsixPublisherAction](https://github.com/cezarypiatek/VsixPublisherAction) using the same input names and secret.

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
| `personal-access-code` | Personal Access Token with Marketplace (Acquire + Manage) permission |

Store your PAT as a secret named `VS_PUBLISHER_ACCESS_TOKEN`. The token must have **Marketplace → Acquire + Manage** permissions with **All accessible organizations** scope.

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