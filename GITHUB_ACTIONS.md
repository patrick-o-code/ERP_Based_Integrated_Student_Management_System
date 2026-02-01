# GitHub Actions Setup for Cloud_Avengers

This guide explains how to use GitHub Actions to automatically build and package your Cloud_Avengers artifact.

## Workflow Overview

The workflow file (`.github/workflows/build-artifact.yml`) automatically:
1. ✅ Builds minified CSS and JavaScript assets
2. 📦 Creates a deployment-ready ZIP artifact
3. 📤 Uploads artifacts for download
4. 🏷️ Creates releases on tag push

## Quick Start

### 1. Push to GitHub
```bash
git add .git config --global credential.https://github.com.helper wincred
git commit -m "Add GitHub Actions workflow"
git push origin main
```

### 2. Watch the Build
Go to your GitHub repository → **Actions** tab to watch the workflow run in real-time.

## Workflow Triggers

The workflow automatically runs when:

| Event | Trigger |
|-------|---------|
| **Push** | When you push to `main`, `master`, or `develop` branches |
| **Pull Request** | When opening/updating PRs to these branches |
| **Manual Trigger** | Click "Run workflow" in the Actions tab (requires `workflow_dispatch`) |

## Accessing Build Artifacts

### Via GitHub Actions (for all builds)
1. Go to repository **Actions** tab
2. Click on the workflow run
3. Download the artifact under "Artifacts" section
4. Extract `rosariosis-artifact-node{VERSION}.zip`

### Via GitHub Releases (for tagged releases)
1. Create a git tag and push:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
2. Go to **Releases** tab
3. Download `rosariosis-v1.0.0.zip`

## Workflow Configuration

### Branch Protection (Recommended)
To ensure builds succeed before merging:

1. Go to **Settings** → **Branches**
2. Add branch protection rule for `main`
3. Enable "Require status checks to pass before merging"
4. Select "build" as required check

### Node.js Version
The workflow tests on multiple Node versions (16.x, 18.x). Modify in the workflow file:

```yaml
strategy:
  matrix:
    node-version: [16.x, 18.x, 20.x]  # Add or remove versions
```

## Artifact Contents Exclusions

The workflow excludes these to reduce artifact size:
- `node_modules/` - Dev dependencies (excluded)
- `.git/` - Git history (excluded)
- `.github/` - Workflow configs (excluded)
- `.env*` - Environment files (excluded)

To modify, edit the `zip -r` command in the workflow.

## Customization Examples

### Only Build on Release Tags
Replace the `on:` section:
```yaml
on:
  push:
    tags:
      - 'v*'  # Triggers only on version tags like v1.0.0
```

### Upload to Multiple Platforms
Add steps to upload to S3, Azure, or other cloud storage:
```yaml
- name: Upload to S3
  uses: aws-actions/configure-aws-credentials@v1
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1

- name: Copy to S3
  run: aws s3 cp build/rosariosis-artifact.zip s3://my-bucket/
```

### Run Tests Before Build
Add before the build step:
```yaml
- name: Run PHP Tests
  run: php -l **/*.php  # Basic PHP syntax check
  
- name: Run ESLint
  run: npm run lint  # If ESLint is configured
```

### Deploy Automatically
Deploy after successful build:
```yaml
- name: Deploy to Production
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
  run: |
    # Your deployment script here
    # Example: rsync, SSH deploy, etc.
    echo "Deploying to production..."
```

## Environment Variables

Add secrets to GitHub for sensitive data:

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**

Then use in workflow:
```yaml
- name: Deploy
  env:
    DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
    DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
  run: ./deploy.sh
```

## Troubleshooting

### Build Fails: "npm install timeout"
- Increase timeout in workflow or check npm cache
- Try: `npm ci` instead of `npm install`

### Build Fails: "Uglification failed"
- This is expected with some legacy JS files
- The workflow uses `continue-on-error: true` to handle this
- CSS minification still succeeds

### Artifact Not Created
- Check "Artifacts" section in workflow run
- Ensure build directory exists before zipping
- Verify ZIP command syntax for your OS

## Advanced: CI/CD Pipeline

Complete example with testing, building, and deployment:

```yaml
name: Full CI/CD Pipeline

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: 18.x
      - run: npm install
      - run: npm test  # Add test script to package.json

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: 18.x
      - run: npm install
      - run: npm run build
      - uses: actions/upload-artifact@v3
        with:
          name: artifact
          path: build/

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v3
      - name: Deploy to server
        run: echo "Deploying..."
```

## Monitoring & Notifications

### Email Notifications
GitHub automatically notifies on workflow failures. Enable in **Settings** → **Notifications**.

### Slack Integration
Add to your workflow:
```yaml
- name: Notify Slack
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Build completed",
        "status": "${{ job.status }}"
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

## References
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Marketplace Actions](https://github.com/marketplace?type=actions)
