# Deployment

## Supabase

Project ref: `sknofcwxqjtlgjztjqhf` (URL: https://sknofcwxqjtlgjztjqhf.supabase.co).

### Branch workflow

1. Create a branch (`la10-phase1`, `la10-feature-x`, etc.) via `mcp__supabase__create_branch`. Branches are isolated Postgres instances that inherit migrations from main.
2. Author migrations under `supabase/migrations/` and apply each with `mcp__supabase__apply_migration` targeting the branch project_ref.
3. Deploy edge functions to the branch via `mcp__supabase__deploy_edge_function`.
4. Run `mcp__supabase__get_advisors` (security + performance) on the branch; fix issues.
5. Merge to main via `mcp__supabase__merge_branch` once tests pass.

### Storage buckets (Phase 1)

Created manually via Dashboard (no MCP tool for bucket create yet):
- `business_assets` — private, owner can read.
- `rider_avatars` — private, owner-readable.

## Flutter apps

```powershell
# Mobile
cd apps/mobile
flutter run --dart-define-from-file=../../.env

# Web (Chrome)
cd apps/web_desktop
flutter run -d chrome --dart-define-from-file=../../.env

# Windows
cd apps/web_desktop
flutter run -d windows --dart-define-from-file=../../.env

# Production builds
flutter build apk --release --dart-define-from-file=../../.env
flutter build web --release --dart-define-from-file=../../.env
flutter build windows --release --dart-define-from-file=../../.env
```

CI/CD is **out of scope for Phase 1** — added in Phase 2.
