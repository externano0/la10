# La 10

Realtime local-delivery platform. Flutter monorepo (mobile + web/desktop), Supabase backend (Postgres + Realtime + Edge Functions), OSM/OSRM routing.

Phase 1 surfaces:
- **Mobile (Android/iOS)** — riders and business owners.
- **Web/Desktop (Chrome, Windows, macOS)** — dispatchers and admins.

## Quick start

```powershell
# 1. Activate melos
dart pub global activate melos

# 2. Bootstrap workspace
melos bootstrap

# 3. Configure env
copy .env.example .env
# fill SUPABASE_URL, SUPABASE_ANON_KEY

# 4. Run mobile (Android emulator running)
./scripts/run_mobile.ps1

# 5. Run web/desktop (Chrome)
./scripts/run_web.ps1
```

See [ARCHITECTURE.md](ARCHITECTURE.md), [DATABASE.md](DATABASE.md), [API.md](API.md), [SECURITY.md](SECURITY.md), [DEPLOYMENT.md](DEPLOYMENT.md), [CONTRIBUTING.md](CONTRIBUTING.md), [ENVIRONMENT.md](ENVIRONMENT.md).
