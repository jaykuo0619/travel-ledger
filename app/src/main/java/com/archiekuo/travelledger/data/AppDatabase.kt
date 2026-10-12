package com.archiekuo.travelledger.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        Trip::class, TripCurrencyRate::class, Member::class, Category::class,
        PaymentMethod::class, Expense::class, ExpenseShare::class, Photo::class, PlanItem::class, DayNote::class, PlanPhoto::class,
    ],
    version = 11,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun tripDao(): TripDao
    abstract fun expenseDao(): ExpenseDao
    abstract fun lookupDao(): LookupDao
    abstract fun photoDao(): PhotoDao
    abstract fun planDao(): PlanDao
    abstract fun dayNoteDao(): DayNoteDao
    abstract fun planPhotoDao(): PlanPhotoDao

    companion object {
        /** v2: trip cover photo, category icon and color. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE trip ADD COLUMN coverPath TEXT")
                db.execSQL("ALTER TABLE category ADD COLUMN icon TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE category ADD COLUMN color INTEGER NOT NULL DEFAULT -1")
            }
        }

        /** v3: expense title (old notes become titles), time of day, recognized receipt text. */
        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE expense ADD COLUMN title TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE expense ADD COLUMN minuteOfDay INTEGER")
                db.execSQL("ALTER TABLE expense ADD COLUMN ocrText TEXT NOT NULL DEFAULT ''")
                db.execSQL("UPDATE expense SET title = note, note = ''")
            }
        }

        /** v4: itinerary items, and expenses can point at the item they were spent on. */
        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """CREATE TABLE IF NOT EXISTS `plan_item` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `tripId` INTEGER NOT NULL, `title` TEXT NOT NULL,
                        `categoryId` INTEGER, `date` INTEGER, `minuteOfDay` INTEGER, `status` TEXT NOT NULL,
                        `reservation` TEXT NOT NULL, `reservationNote` TEXT NOT NULL, `location` TEXT NOT NULL,
                        `estCost` REAL, `note` TEXT NOT NULL, `createdAt` INTEGER NOT NULL,
                        FOREIGN KEY(`tripId`) REFERENCES `trip`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)"""
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_plan_item_tripId` ON `plan_item` (`tripId`)")
                db.execSQL("ALTER TABLE expense ADD COLUMN planItemId INTEGER")
            }
        }

        /** v5: hand-picked cover illustration. */
        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE trip ADD COLUMN coverTheme TEXT")
            }
        }

        /** v6: trip identity for sharing, and who shared a read-only copy. */
        val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE trip ADD COLUMN uuid TEXT NOT NULL DEFAULT ''")
                db.execSQL("UPDATE trip SET uuid = lower(hex(randomblob(16))) WHERE uuid = ''")
                db.execSQL("ALTER TABLE trip ADD COLUMN sharedBy TEXT")
                db.execSQL("ALTER TABLE trip ADD COLUMN sharedAt INTEGER")
            }
        }

        /** v7: expenses and plan items get an identity, who suggested them, and a "my addition" flag. */
        val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                for (table in listOf("expense", "plan_item")) {
                    db.execSQL("ALTER TABLE $table ADD COLUMN uuid TEXT NOT NULL DEFAULT ''")
                    db.execSQL("UPDATE $table SET uuid = lower(hex(randomblob(16))) WHERE uuid = ''")
                    db.execSQL("ALTER TABLE $table ADD COLUMN addedBy TEXT")
                    db.execSQL("ALTER TABLE $table ADD COLUMN pending INTEGER NOT NULL DEFAULT 0")
                }
            }
        }

        /** v8: a note for each day of a trip. */
        val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """CREATE TABLE IF NOT EXISTS `day_note` (`tripId` INTEGER NOT NULL, `day` INTEGER NOT NULL, `text` TEXT NOT NULL,
                        `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`tripId`, `day`),
                        FOREIGN KEY(`tripId`) REFERENCES `trip`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)"""
                )
            }
        }

        /** v9: which map app a trip navigates with. */
        val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE trip ADD COLUMN navApp TEXT")
            }
        }

        /** v10: pictures kept with plan items. */
        val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """CREATE TABLE IF NOT EXISTS `plan_photo` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `planItemId` INTEGER NOT NULL,
                        `path` TEXT NOT NULL, `width` INTEGER NOT NULL, `height` INTEGER NOT NULL, `createdAt` INTEGER NOT NULL,
                        FOREIGN KEY(`planItemId`) REFERENCES `plan_item`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE)"""
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_plan_photo_planItemId` ON `plan_photo` (`planItemId`)")
            }
        }

        /** v11: the categories and payment methods the app starts with can be renamed but not deleted. */
        val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(db: SupportSQLiteDatabase) {
                for ((table, names) in listOf("category" to BUILT_IN_CATEGORIES, "payment_method" to BUILT_IN_PAYMENT_METHODS)) {
                    db.execSQL("ALTER TABLE $table ADD COLUMN builtIn TEXT")
                    // The first row with each starting name (a later copy of the same name stays deletable).
                    val list = names.joinToString(",") { "'$it'" }
                    db.execSQL("UPDATE $table SET builtIn = name WHERE name IN ($list) AND id IN (SELECT MIN(id) FROM $table GROUP BY name)")
                }
            }
        }

        val ALL_MIGRATIONS = arrayOf(
            MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10,
            MIGRATION_10_11,
        )

        fun create(context: Context): AppDatabase =
            Room.databaseBuilder(context, AppDatabase::class.java, "travel-ledger.db").setup().build()

        /** Shared setup for the real database and the in-memory one used by tests. */
        fun RoomDatabase.Builder<AppDatabase>.setup(): RoomDatabase.Builder<AppDatabase> =
            addMigrations(*ALL_MIGRATIONS)
                .addCallback(object : Callback() {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        BUILT_IN_CATEGORIES.forEachIndexed { i, n ->
                            db.execSQL("INSERT INTO category (name, sortOrder, icon, color, builtIn) VALUES ('$n', $i, '', -1, '$n')")
                        }
                        BUILT_IN_PAYMENT_METHODS.forEachIndexed { i, n ->
                            db.execSQL("INSERT INTO payment_method (name, sortOrder, builtIn) VALUES ('$n', $i, '$n')")
                        }
                    }
                })
    }
}
