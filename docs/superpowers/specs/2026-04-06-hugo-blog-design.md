# Hugo Blog Design — low-level-luke.me

## Overview

Personal technical blog built with Hugo and the PaperMod theme. Serves as both a learning journal and professional portfolio. Deployed to a VPS via git push with a post-receive hook.

## Project Structure

```
blog/
├── hugo.toml
├── content/
│   └── posts/
│       └── finding-the-cost-of-a-tlb-miss/
│           ├── index.md
│           └── diagrams/
│               ├── pointer-chase.png
│               ├── pointer-chase.svg
│               ├── sequential-access.png
│               ├── sequential-access.svg
│               ├── shuffled-values.png
│               └── shuffled-values.svg
├── themes/
│   └── PaperMod/          (git submodule)
└── deploy/
    └── post-receive        (git hook script for VPS)
```

Existing content (the TLB miss post and its diagrams) is migrated into Hugo's page bundle format. Diagrams are referenced with relative paths from the post's `index.md`.

## Hugo Configuration

File: `hugo.toml`

- **baseURL**: `https://low-level-luke.me/`
- **title**: `low-level-luke`
- **theme**: PaperMod
- **Default color scheme**: dark
- **Syntax highlighting**: enabled, dark theme (monokai or dracula)
- **Taxonomies**: tags and categories (Hugo defaults)
- **Menu items**: Home, Tags, Archive
- **Post features**: table of contents, reading time, code copy buttons

## Post Front Matter

Each post uses YAML front matter:

```yaml
---
title: "Post Title"
date: YYYY-MM-DD
tags: ["tag1", "tag2"]
summary: "One-line description"
---
```

The existing TLB miss post will be tagged with `operating-systems`, `performance`, `hardware`.

## Deployment

### Local workflow

1. Write/edit posts in `content/posts/`
2. Preview locally with `hugo server -D`
3. Publish with `git push deploy main`

### VPS setup (manual, not automated by this project)

1. Bare git repo at `/opt/blog.git`
2. Post-receive hook checks out code, inits submodules, runs `hugo --minify`, copies `public/` to `/var/www/low-level-luke.me/`
3. Web server (nginx or caddy) serves static files from the web root

### post-receive hook behavior

1. Check out pushed code to a temp directory
2. Initialize and update git submodules (PaperMod theme)
3. Run `hugo --minify` to build the site
4. Copy contents of `public/` to `/var/www/low-level-luke.me/`
5. Clean up temp directory
6. Print success/failure message

### Out of scope

- SSL/TLS certificate setup
- DNS configuration
- Web server (nginx/caddy) installation and config
- Domain registrar settings

## Decisions

- **PaperMod over alternatives**: battle-tested, actively maintained, built-in dark mode/syntax highlighting/tags, easy to customize
- **Page bundles over flat files**: keeps each post's assets co-located, relative paths just work
- **Git submodule for theme**: standard Hugo practice, pins to a specific version, easy to update
- **Dark mode default**: fits the low-level systems programming aesthetic
- **post-receive hook over CI/CD**: simpler, no third-party dependency, appropriate for a personal blog on a VPS
