# API Versioning and Deprecation Policy

## Current Version
- Current public API version: `v1`
- Versioned base path: `/v1`
- Every API response includes header `x-api-version: v1`

## Compatibility Rules
- Backward-compatible changes are allowed within `v1`:
  - new optional request fields
  - new response fields
  - new endpoints
- Breaking changes require a new major path version (for example `/v2`).

## Deprecation Lifecycle
1. Mark endpoint/field as deprecated in OpenAPI output.
2. Announce deprecation in release notes and changelog.
3. Emit deprecation headers for affected endpoints:
   - `deprecation: true`
   - `sunset: <RFC 1123 date>`
   - `link: <policy/changelog URL>; rel="deprecation"`
4. Keep deprecated behavior available for at least 90 days.
5. Remove only after the sunset date in the next major API version.

## OpenAPI Output
- Generated file: `priv/static/openapi/v1.json`
- Generation command:

```bash
mix edoc_api.openapi.generate
```

- Custom output path:

```bash
mix edoc_api.openapi.generate --output /tmp/edoc-v1.json
```
