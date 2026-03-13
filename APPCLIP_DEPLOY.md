# FluxFocus App Clip deployment

## What is already in this repo

- App and App Clip use `fluxfocusclip.lraitech.com` as the associated domain.
- GitHub Pages content lives in `docs/`.
- The Apple App Site Association file is published at:
  - `/.well-known/apple-app-site-association`
  - `/apple-app-site-association`
- GitHub Actions workflow for Pages deployment lives at `.github/workflows/pages.yml`.

## Files that must be reachable in production

- `https://fluxfocusclip.lraitech.com/.well-known/apple-app-site-association`
- `https://fluxfocusclip.lraitech.com/apple-app-site-association`

## Required manual configuration

### 1. GitHub

1. Push this repository to GitHub.
2. Open the repository on GitHub.
3. Go to `Settings` -> `Pages`.
4. Under `Source`, select `GitHub Actions`.
5. Under `Custom domain`, set `fluxfocusclip.lraitech.com`.
6. Wait for the `Deploy GitHub Pages` workflow to complete.
7. After GitHub finishes issuing the certificate, enable `Enforce HTTPS`.

Note:

- This repository still includes `docs/CNAME` for portability, but GitHub documents that a custom GitHub Actions Pages workflow ignores the file. The effective custom domain is the one you save in the GitHub Pages settings UI.

### 2. Cloudflare DNS

1. Open the `lraitech.com` zone in Cloudflare.
2. Create a `CNAME` record:
   - Name: `fluxfocusclip`
   - Target: `<your-github-username>.github.io`
3. Keep the record `DNS only` first.
4. After the GitHub Pages custom domain is verified and HTTPS works, you can switch to proxied mode if you want Cloudflare in front of the site.

### 3. Cloudflare response header safeguard

GitHub Pages usually serves the extensionless AASA file correctly enough for Apple to fetch it, but the exact `Content-Type` can vary depending on the path and cache layer. To make this deterministic, add a Cloudflare Transform Rule that sets the response header for the two AASA paths.

Create a `Transform Rules` -> `Modify Response Header` rule:

- Expression:

  ```
  http.host eq "fluxfocusclip.lraitech.com" and (
    http.request.uri.path eq "/.well-known/apple-app-site-association" or
    http.request.uri.path eq "/apple-app-site-association"
  )
  ```

- Operation:
  - Header name: `Content-Type`
  - Set static value: `application/json`

### 4. Apple Developer / App Store Connect

1. In Xcode target `Signing & Capabilities`, ensure both the app and the App Clip still contain:
   - `Associated Domains`
2. Confirm the entries are:
   - `appclips:fluxfocusclip.lraitech.com`
   - `applinks:fluxfocusclip.lraitech.com`
3. In App Store Connect, configure the App Clip Experience to use:
   - Domain: `fluxfocusclip.lraitech.com`
   - Invocation path prefix: `/i/`
4. Rebuild and install the app after the AASA file is publicly reachable.

## Validation checklist

Run these commands after DNS and Pages are live:

```bash
curl -i https://fluxfocusclip.lraitech.com/.well-known/apple-app-site-association
curl -i https://fluxfocusclip.lraitech.com/apple-app-site-association
```

Expected:

- HTTP status `200`
- `content-type: application/json`
- body contains:
  - `RZD9M68FZ9.studio.lrai.fluxfocus`
  - `RZD9M68FZ9.studio.lrai.fluxfocus.Clip`

You can also verify DNS:

```bash
dig fluxfocusclip.lraitech.com +nostats +nocomments +nocmd
```
