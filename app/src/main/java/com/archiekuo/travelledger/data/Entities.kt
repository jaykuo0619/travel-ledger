package com.archiekuo.travelledger.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/** All totals are reported in this currency; expenses may use any currency. */
const val HOME_CURRENCY = "TWD"

/** Dates are stored as epoch days (LocalDate.toEpochDay). */
@Entity(tableName = "trip")
data class Trip(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val startDate: Long,
    val endDate: Long,
    val homeCurrency: String = HOME_CURRENCY,
    val budget: Double? = null,
    val splitEnabled: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
    val archived: Boolean = false,
    /** Absolute path of the cover image in app-private storage, or null for a generated cover. */
    val coverPath: String? = null,
    /** Illustration chosen by hand (CoverTheme name), or null to pick it from the trip name. */
    val coverTheme: String? = null,
    /** Stable identity across phones, so a re-shared trip updates the copy instead of duplicating it. */
    @ColumnInfo(defaultValue = "") val uuid: String = java.util.UUID.randomUUID().toString(),
    /** Who shared this trip with us; non-null means it is a read-only copy. */
    val sharedBy: String? = null,
    /** When the shared copy was made (epoch millis). */
    val sharedAt: Long? = null,
    /** Map app for 導航 on this trip ("google", "naver", "kakao"); null asks each time. */
    val navApp: String? = null,
) {
    val readOnly: Boolean get() = sharedBy != null
}

@Entity(
    tableName = "trip_currency_rate",
    primaryKeys = ["tripId", "currency"],
    foreignKeys = [ForeignKey(Trip::class, ["id"], ["tripId"], onDelete = ForeignKey.CASCADE)],
)
data class TripCurrencyRate(
    val tripId: Long,
    val currency: String,
    /** 1 unit of [currency] in TWD. */
    val rate: Double,
    val updatedAt: Long = System.currentTimeMillis(),
    val source: String = "manual",
)

@Entity(
    tableName = "member",
    foreignKeys = [ForeignKey(Trip::class, ["id"], ["tripId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("tripId")],
)
data class Member(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val tripId: Long,
    val name: String,
)

@Entity(tableName = "category")
data class Category(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val sortOrder: Int = 0,
    /** Icon key (see CategoryStyle); empty means "guess from the name". */
    @ColumnInfo(defaultValue = "") val icon: String = "",
    /** Palette index (see CategoryStyle); -1 means "guess from the name". */
    @ColumnInfo(defaultValue = "-1") val color: Int = -1,
    /** For the categories the app starts with: which one it was (its first name), so it can be renamed but not deleted. */
    val builtIn: String? = null,
)

/** The category a deleted one falls back to. */
const val FALLBACK_CATEGORY = "其他"
val BUILT_IN_CATEGORIES = listOf("吃", "交通", "購物", "住宿", "景點", FALLBACK_CATEGORY)
val BUILT_IN_PAYMENT_METHODS = listOf("現金", "信用卡", "行動支付")

@Entity(tableName = "payment_method")
data class PaymentMethod(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val sortOrder: Int = 0,
    /** For the payment methods the app starts with (its first name): can be renamed but not deleted. */
    val builtIn: String? = null,
)

@Entity(
    tableName = "expense",
    foreignKeys = [ForeignKey(Trip::class, ["id"], ["tripId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("tripId")],
)
data class Expense(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val tripId: Long,
    val date: Long,
    val amount: Double,
    val currency: String,
    val rate: Double,
    val homeAmount: Double,
    val categoryId: Long?,
    val paymentMethodId: Long?,
    val payerId: Long?,
    val note: String = "",
    val createdAt: Long = System.currentTimeMillis(),
    /** Shop or item name, shown as the expense title. */
    @ColumnInfo(defaultValue = "") val title: String = "",
    /** Local time of the expense in minutes after midnight, or null if unknown. */
    val minuteOfDay: Int? = null,
    /** Text recognized from receipt photos, kept for search. */
    @ColumnInfo(defaultValue = "") val ocrText: String = "",
    /** The itinerary item this expense was recorded for, if any. */
    val planItemId: Long? = null,
    /** Stable identity across phones, so an addition sent twice is only added once. */
    @ColumnInfo(defaultValue = "") val uuid: String = java.util.UUID.randomUUID().toString(),
    /** The companion who suggested this item, once the organizer accepted it. */
    val addedBy: String? = null,
    /** Added by us on a trip someone shared (read-only): ours to change, waiting to be sent to the organizer. */
    @ColumnInfo(defaultValue = "0") val pending: Boolean = false,
)

@Entity(
    tableName = "expense_share",
    primaryKeys = ["expenseId", "memberId"],
    foreignKeys = [ForeignKey(Expense::class, ["id"], ["expenseId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("memberId")],
)
data class ExpenseShare(val expenseId: Long, val memberId: Long)

@Entity(
    tableName = "photo",
    foreignKeys = [ForeignKey(Expense::class, ["id"], ["expenseId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("expenseId")],
)
data class Photo(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val expenseId: Long,
    val type: String, // PhotoType.RECEIPT / PhotoType.MEMORY
    val path: String,
    val width: Int = 0,
    val height: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val savedToGallery: Boolean = false,
)

object PhotoType {
    const val RECEIPT = "RECEIPT"
    const val MEMORY = "MEMORY"
}

/** A place or activity planned for the trip: scheduled on a day, or unscheduled ("待排") when [date] is null. */
@Entity(
    tableName = "plan_item",
    foreignKeys = [ForeignKey(Trip::class, ["id"], ["tripId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("tripId")],
)
data class PlanItem(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val tripId: Long,
    val title: String,
    /** Shares the expense categories so one-tap recording files it correctly. */
    val categoryId: Long? = null,
    val date: Long? = null,
    val minuteOfDay: Int? = null,
    val status: String = PlanStatus.TODO,
    val reservation: String = Reservation.NONE,
    /** Booking time, party size, confirmation number… */
    val reservationNote: String = "",
    /** Address or a map link. */
    val location: String = "",
    /** Estimated cost in TWD. */
    val estCost: Double? = null,
    val note: String = "",
    val createdAt: Long = System.currentTimeMillis(),
    /** Stable identity across phones, so an addition sent twice is only added once. */
    @ColumnInfo(defaultValue = "") val uuid: String = java.util.UUID.randomUUID().toString(),
    /** The companion who suggested this item, once the organizer accepted it. */
    val addedBy: String? = null,
    /** Added by us on a trip someone shared (read-only): ours to change, waiting to be sent to the organizer. */
    @ColumnInfo(defaultValue = "0") val pending: Boolean = false,
)

object PlanStatus {
    const val TODO = "TODO"
    const val DONE = "DONE"
    const val SKIPPED = "SKIPPED"
}

object Reservation {
    const val NONE = "NONE"
    const val NEEDED = "NEEDED"
    const val BOOKED = "BOOKED"
}

/** Free text for one day of a trip ("記得帶護照", or a whole day's notes moved here after splitting them into plans). */
@Entity(
    tableName = "day_note",
    primaryKeys = ["tripId", "day"],
    foreignKeys = [ForeignKey(Trip::class, ["id"], ["tripId"], onDelete = ForeignKey.CASCADE)],
)
data class DayNote(
    val tripId: Long,
    /** Epoch day, or [UNSCHEDULED_DAY] for the 待排 list. */
    val day: Long,
    val text: String,
    val updatedAt: Long = System.currentTimeMillis(),
)

/** The 待排 list has no date; its note is stored under this day. */
const val UNSCHEDULED_DAY = Long.MIN_VALUE

/** A picture kept with a plan item: a screenshot of the menu, opening hours, a route… */
@Entity(
    tableName = "plan_photo",
    foreignKeys = [ForeignKey(PlanItem::class, ["id"], ["planItemId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("planItemId")],
)
data class PlanPhoto(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val planItemId: Long,
    val path: String,
    val width: Int = 0,
    val height: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
)
