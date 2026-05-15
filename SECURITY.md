# Security Policy

## Supported Versions

Only the latest version of Peak Sprays is supported for security updates.

| Version | Supported          |
| ------- | ------------------ |
| v0.2.1  | :white_check_mark: |
| < v0.2.1| :x:                |

## Reporting a Vulnerability

We take the security of our tools seriously. If you find a security vulnerability, please do not report it via public issues. Instead, please follow these steps:

1. **Email**: Send a detailed report to `abdelkarim.contact1@gmail.com` (or the appropriate contact).
2. **Discord**: Contact a Lead Developer in the [Peak Studios Discord](https://dsc.gg/peakstudios).

We will acknowledge your report within 48 hours and provide a timeline for a fix. Please give us reasonable time to resolve the issue before making any information public.

## Image Spray Safety

Image sprays load remote HTTPS images inside DUI/NUI. Keep `Config.ImageAllowedHosts` limited to trusted hosts, because remote images can be removed, replaced, used for tracking, or blocked by CORS. Do not allow arbitrary hosts on public servers unless you also add your own moderation and caching/proxy layer.
