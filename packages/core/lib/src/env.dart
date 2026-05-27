// Compile-time environment, fed via --dart-define-from-file.
// Never read SUPABASE_SERVICE_ROLE_KEY here — that key must never reach a client.
class Env {
  const Env._();

  static const supabaseUrl     = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const osrmBaseUrl     = String.fromEnvironment('OSRM_BASE_URL',
      defaultValue: 'https://router.project-osrm.org');
  static const osmTileUrl      = String.fromEnvironment('OSM_TILE_URL',
      defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

  static const riderHeartbeatMinIntervalSec = int.fromEnvironment(
      'RIDER_HEARTBEAT_MIN_INTERVAL_SEC', defaultValue: 10);
  static const riderHeartbeatMaxIntervalSec = int.fromEnvironment(
      'RIDER_HEARTBEAT_MAX_INTERVAL_SEC', defaultValue: 30);
  static const riderHeartbeatMinDistanceM = int.fromEnvironment(
      'RIDER_HEARTBEAT_MIN_DISTANCE_M', defaultValue: 20);

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
