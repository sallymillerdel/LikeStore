# WorkManager (UpdateCheckWorker) creates its Room database by reflection
# (WorkDatabase_Impl.<init>()). R8 full mode, the AGP 9 default, does not keep
# the no-arg constructor of a class kept only by name, and Room 2.6's own rule
# keeps just the class: without this the app crashes at startup in
# androidx.startup.InitializationProvider.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
