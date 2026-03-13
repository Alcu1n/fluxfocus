# FluxFocus App Clip Deployment / FluxFocus App Clip 部署

## What Is Already In This Repo / 仓库内已完成内容

- App and App Clip use `fluxfocusclip.lraitech.com` as the associated domain.  
  App 与 App Clip 已使用 `fluxfocusclip.lraitech.com` 作为关联域名。
- GitHub Pages content lives in `docs/`.  
  GitHub Pages 站点内容位于 `docs/`。
- The Apple App Site Association file is published at:
  Apple App Site Association 文件发布在：
  - `/.well-known/apple-app-site-association`
  - `/apple-app-site-association`
- GitHub Actions workflow for Pages deployment lives at `.github/workflows/pages.yml`.  
  GitHub Actions 的 Pages 部署工作流位于 `.github/workflows/pages.yml`。

## Files That Must Be Reachable / 生产环境必须可访问的文件

- `https://fluxfocusclip.lraitech.com/.well-known/apple-app-site-association`
- `https://fluxfocusclip.lraitech.com/apple-app-site-association`

## URL Strategy / URL 方案

- App Store Connect should register a short App Clip Experience URL such as `https://fluxfocusclip.lraitech.com`.  
  App Store Connect 应注册短 App Clip Experience URL，例如 `https://fluxfocusclip.lraitech.com`。
- Each physical NFC tag should store its own invocation URL under `/i/<tagPublicId>`.  
  每张物理 NFC 标签应写入各自的 `/i/<tagPublicId>` invocation URL。
- Do not append long signature hashes to the public invocation URL.  
  不要在公开 invocation URL 上追加长签名哈希。
- For side-loaded development builds, the App Clip can hand off to the full app via `fluxfocus://focus/<tagPublicId>`.  
  对于侧载开发构建，App Clip 可通过 `fluxfocus://focus/<tagPublicId>` 移交到完整 App。

Example / 示例:

```text
Experience URL: https://fluxfocusclip.lraitech.com
NFC tag URL:    https://fluxfocusclip.lraitech.com/i/desk-altar-001
```

## Required Manual Configuration / 必须手动完成的配置

### 1. GitHub

1. Push this repository to GitHub.  
   将仓库推送到 GitHub。
2. Open the repository on GitHub.  
   打开 GitHub 仓库页面。
3. Go to `Settings` -> `Pages`.  
   进入 `Settings` -> `Pages`。
4. Under `Source`, select `GitHub Actions`.  
   在 `Source` 中选择 `GitHub Actions`。
5. Under `Custom domain`, set `fluxfocusclip.lraitech.com`.  
   在 `Custom domain` 中填写 `fluxfocusclip.lraitech.com`。
6. Wait for the `Deploy GitHub Pages` workflow to complete.  
   等待 `Deploy GitHub Pages` 工作流完成。
7. After GitHub finishes issuing the certificate, enable `Enforce HTTPS`.  
   GitHub 签发证书完成后，启用 `Enforce HTTPS`。

Note / 说明:

- This repository still includes `docs/CNAME` for portability, but a custom GitHub Actions Pages workflow uses the domain saved in the GitHub Pages settings UI.  
  仓库仍保留 `docs/CNAME` 以便迁移，但使用自定义 GitHub Actions Pages 工作流时，以 GitHub Pages 设置页保存的域名为准。

### 2. Cloudflare DNS

1. Open the `lraitech.com` zone in Cloudflare.  
   打开 Cloudflare 中的 `lraitech.com` 区域。
2. Create a `CNAME` record:
   创建 `CNAME` 记录：
   - Name: `fluxfocusclip`
   - Target: `<your-github-username>.github.io`
3. Keep the record `DNS only` first.  
   先保持为 `DNS only`。
4. After the GitHub Pages custom domain is verified and HTTPS works, you can switch to proxied mode if you want Cloudflare in front of the site.  
   等 GitHub Pages 自定义域名验证通过且 HTTPS 正常后，如需让 Cloudflare 代理流量，再切换为代理模式。

### 3. Cloudflare Response Header Safeguard

GitHub Pages usually serves the extensionless AASA file correctly enough for Apple to fetch it, but the exact `Content-Type` can vary depending on the path and cache layer. To make this deterministic, add a Cloudflare Transform Rule that sets the response header for the two AASA paths.  
GitHub Pages 通常能把无扩展名的 AASA 文件正确提供给 Apple 抓取，但不同路径和缓存层返回的 `Content-Type` 可能不稳定。为避免随机性，建议通过 Cloudflare Transform Rule 固定两个 AASA 路径的响应头。

Create a `Transform Rules` -> `Modify Response Header` rule:  
创建 `Transform Rules` -> `Modify Response Header` 规则：

- Expression / 表达式:

  ```
  http.host eq "fluxfocusclip.lraitech.com" and (
    http.request.uri.path eq "/.well-known/apple-app-site-association" or
    http.request.uri.path eq "/apple-app-site-association"
  )
  ```

- Operation / 操作:
  - Header name: `Content-Type`
  - Set static value: `application/json`

### 4. Apple Developer / App Store Connect

1. In Xcode target `Signing & Capabilities`, ensure both the app and the App Clip still contain `Associated Domains`.  
   在 Xcode target 的 `Signing & Capabilities` 中，确认 App 与 App Clip 都保留 `Associated Domains`。
2. Confirm the entries are:
   确认条目为：
   - `appclips:fluxfocusclip.lraitech.com`
   - `applinks:fluxfocusclip.lraitech.com`
3. In App Store Connect, configure the App Clip Experience to use:
   在 App Store Connect 中，将 App Clip Experience 配置为：
   - Experience URL: `https://fluxfocusclip.lraitech.com`
   - Invocation path prefix handled by the app: `/i/`
4. Rebuild and install the app after the AASA file is publicly reachable.  
   在 AASA 文件可被公网访问后重新构建并安装 App。

## Validation Checklist / 验收清单

Run these commands after DNS and Pages are live:  
在 DNS 与 Pages 生效后运行：

```bash
curl -i https://fluxfocusclip.lraitech.com/.well-known/apple-app-site-association
curl -i https://fluxfocusclip.lraitech.com/apple-app-site-association
```

Expected / 预期结果:

- HTTP status `200`
- `content-type: application/json`
- body contains / 响应体包含：
  - `RZD9M68FZ9.studio.lrai.fluxfocus`
  - `RZD9M68FZ9.studio.lrai.fluxfocus.Clip`

You can also verify DNS / 也可以验证 DNS：

```bash
dig fluxfocusclip.lraitech.com +nostats +nocomments +nocmd
```
