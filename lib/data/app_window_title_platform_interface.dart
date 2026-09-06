abstract interface class AppWindowTitlePlatform {
  Future<void> update({required String title, required bool alert});
  Future<void> dispose();
}
