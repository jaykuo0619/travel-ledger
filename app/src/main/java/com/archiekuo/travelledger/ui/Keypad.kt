package com.archiekuo.travelledger.ui

import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Backspace
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.archiekuo.travelledger.data.HOME_CURRENCY

private const val MAX_INT_DIGITS = 9
private const val MAX_DECIMALS = 2

/** Calculator operators as shown on the keys. */
const val OPERATORS = "+−×÷"

private fun isOp(c: Char) = c in OPERATORS

/** The number being typed: everything after the last operator. */
private fun lastNumber(expr: String): String = expr.substring(expr.indexOfLast(::isOp) + 1)

/**
 * Pure reducer for the calculator: digits, "00", ".", operators (+ − × ÷), "=", "⌫" and "C" (clear).
 * The text is the expression as typed, e.g. "1200+350×2"; a plain number is just a number.
 */
fun applyKey(current: String, key: String): String = when {
    key == "C" -> ""
    key == "⌫" -> current.dropLast(1)
    key == "=" -> evaluate(current)?.let(::plainNumber) ?: current
    key.length == 1 && isOp(key[0]) -> when {
        current.isEmpty() -> current // nothing to work on yet
        isOp(current.last()) -> current.dropLast(1) + key // changed my mind about the operator
        current.last() == '.' -> current.dropLast(1) + key
        else -> current + key
    }
    else -> {
        val head = current.dropLast(lastNumber(current).length)
        head + typeDigit(lastNumber(current), key)
    }
}

/** Digits, "00" and "." within one number (at most 9 digits before the point and 2 after). */
private fun typeDigit(current: String, key: String): String = when (key) {
    "." -> when {
        '.' in current -> current
        current.isEmpty() -> "0."
        else -> "$current."
    }
    "00" -> if (current.isEmpty() || current == "0") current else typeDigit(typeDigit(current, "0"), "0")
    else -> {
        val dot = current.indexOf('.')
        when {
            dot >= 0 && current.length - dot - 1 >= MAX_DECIMALS -> current
            dot < 0 && current.length >= MAX_INT_DIGITS -> current
            current == "0" -> key
            else -> current + key
        }
    }
}

/** Whether [expr] has an operation in it (rather than being a single number). */
fun isExpression(expr: String): Boolean = expr.any(::isOp)

/**
 * The value of [expr], × and ÷ before + and −, rounded to 2 decimals; a trailing operator is ignored.
 * Null when there is nothing to compute or it divides by zero.
 */
fun evaluate(expr: String): Double? {
    val text = expr.trimEnd { isOp(it) || it == '.' }
    if (text.isEmpty()) return null
    val numbers = mutableListOf<java.math.BigDecimal>()
    val ops = mutableListOf<Char>()
    var start = 0
    for ((i, c) in text.withIndex()) {
        if (isOp(c)) {
            numbers += text.substring(start, i).toBigDecimalOrNull() ?: return null
            ops += c
            start = i + 1
        }
    }
    numbers += text.substring(start).toBigDecimalOrNull() ?: return null
    // × and ÷ first, left to right.
    val terms = mutableListOf(numbers[0])
    val addOps = mutableListOf<Char>()
    for ((i, op) in ops.withIndex()) {
        val n = numbers[i + 1]
        when (op) {
            '×' -> terms[terms.lastIndex] = terms.last().multiply(n)
            '÷' -> {
                if (n.signum() == 0) return null
                terms[terms.lastIndex] = terms.last().divide(n, 10, java.math.RoundingMode.HALF_UP)
            }
            else -> { addOps += op; terms += n }
        }
    }
    var total = terms[0]
    for ((i, op) in addOps.withIndex()) total = if (op == '+') total.add(terms[i + 1]) else total.subtract(terms[i + 1])
    return total.setScale(MAX_DECIMALS, java.math.RoundingMode.HALF_UP).toDouble()
}

/** A result as keypad text: "1900", "12.5" (no trailing zeros, no grouping). */
private fun plainNumber(v: Double): String =
    java.math.BigDecimal(v.toString()).stripTrailingZeros().toPlainString()

/** The expression for display, numbers grouped: "1,200 + 350 × 2". */
fun fmtExpression(expr: String): String = buildString {
    var start = 0
    for ((i, c) in expr.withIndex()) {
        if (isOp(c)) {
            append(fmtTyped(expr.substring(start, i))).append(' ').append(c).append(' ')
            start = i + 1
        }
    }
    if (start < expr.length) append(fmtTyped(expr.substring(start)))
}.trimEnd()

/**
 * Bottom calculator (about half the screen): currency switch + amount, conversion line, keys and Save.
 * Tapping the currency opens the trip's currencies; tapping the conversion line edits the rate.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun KeypadPanel(
    amount: String,
    currency: String,
    currencies: List<String>,
    rate: String,
    homeAmount: Double?,
    canSave: Boolean,
    onKey: (String) -> Unit,
    onCurrency: (String) -> Unit,
    onOtherCurrency: () -> Unit,
    onEditRate: () -> Unit,
    onSave: () -> Unit,
    modifier: Modifier = Modifier,
    /** Height of one key; the handle on top changes it (five rows, so dragging by d moves each key by d/5). */
    keyHeight: Dp = KEY_HEIGHT_DEFAULT.dp,
    onKeyHeight: ((Dp) -> Unit)? = null,
    onKeyHeightDone: () -> Unit = {},
) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    val density = LocalDensity.current
    val latest by rememberUpdatedState(keyHeight)
    var menu by remember { mutableStateOf(false) }
    Column(
        modifier.fillMaxWidth().shadow(16.dp, shape).clip(shape)
            .background(cs.surfaceContainerLowest)
            .navigationBarsPadding()
            .padding(start = 14.dp, end = 14.dp, top = if (onKeyHeight != null) 0.dp else 12.dp, bottom = 10.dp),
    ) {
        if (onKeyHeight != null) {
            // Drag handle: pull up for bigger keys, push down for more room above.
            Box(
                Modifier.fillMaxWidth().height(22.dp)
                    .draggable(
                        rememberDraggableState { px ->
                            val d = with(density) { px.toDp() }
                            onKeyHeight((latest - d / 5).coerceIn(KEY_HEIGHT_MIN.dp, KEY_HEIGHT_MAX.dp))
                        },
                        Orientation.Vertical,
                        onDragStopped = { onKeyHeightDone() },
                    )
                    .semantics { contentDescription = "拖曳調整計算機高度" },
                contentAlignment = Alignment.Center,
            ) { Box(Modifier.size(width = 44.dp, height = 5.dp).clip(RoundedCornerShape(50)).background(cs.outline)) }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box {
                Row(
                    Modifier.clip(RoundedCornerShape(12.dp)).background(cs.primaryContainer)
                        .clickable { menu = true }.padding(start = 12.dp, end = 6.dp, top = 8.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(currency, style = MaterialTheme.typography.titleSmall, color = cs.onPrimaryContainer)
                    Icon(Icons.Rounded.ExpandMore, "選擇幣別", Modifier.size(20.dp), tint = cs.onPrimaryContainer)
                }
                DropdownMenu(menu, { menu = false }) {
                    currencies.forEach { c ->
                        DropdownMenuItem(
                            text = { Text(currencyLabel(c), style = MaterialTheme.typography.bodyLarge) },
                            onClick = { menu = false; onCurrency(c) },
                            trailingIcon = { if (c == currency) Text("✓", color = cs.primary) },
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(text = { Text("其他幣別…") }, onClick = { menu = false; onOtherCurrency() })
                }
            }
            Column(Modifier.weight(1f).padding(start = 12.dp), horizontalAlignment = Alignment.End) {
                if (isExpression(amount)) {
                    // The sum as typed, and its result underneath as you go.
                    Text(
                        fmtExpression(amount), style = MaterialTheme.typography.titleMedium, color = cs.onSurfaceVariant,
                        textAlign = TextAlign.End, maxLines = 2,
                    )
                    val result = evaluate(amount)
                    Text(
                        if (result != null) "= " + fmtPlain(result) else "無法計算",
                        style = MaterialTheme.typography.displaySmall.copy(fontSize = 34.sp),
                        color = if (result != null) cs.onSurface else cs.error, textAlign = TextAlign.End, maxLines = 1,
                    )
                } else {
                    Text(
                        fmtTyped(amount),
                        style = MaterialTheme.typography.displaySmall.copy(fontSize = 38.sp),
                        color = if (amount.isEmpty()) ledger.textMuted else cs.onSurface,
                        textAlign = TextAlign.End, maxLines = 1,
                    )
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(top = 2.dp, bottom = 8.dp),
            horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically,
        ) {
            if (currency != HOME_CURRENCY) {
                Row(
                    Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onEditRate).padding(horizontal = 6.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val rateOk = rate.toDoubleOrNull()?.let { it > 0 } == true
                    Text(
                        if (rateOk) "匯率 $rate" else "請設定匯率",
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (rateOk) cs.onSurfaceVariant else cs.error,
                    )
                    Spacer(Modifier.width(4.dp))
                    Icon(Icons.Rounded.Edit, "修改匯率", Modifier.size(15.dp), tint = cs.onSurfaceVariant)
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    "≈ ${fmtMoney(homeAmount ?: 0.0)}",
                    style = MaterialTheme.typography.titleSmall, color = cs.primary,
                )
            } else {
                Text("新台幣", style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
            }
        }
        val gap = 8.dp
        val keyH = keyHeight
        // Five rows of four, like a phone calculator: clear/back/÷/× on top, − + = down the right, 儲存 bottom right.
        Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                Key("C", keyH, Modifier.weight(1f), muted = true) { onKey("C") }
                Box(
                    Modifier.weight(1f).height(keyH).clip(RoundedCornerShape(16.dp)).background(cs.surfaceVariant)
                        .combinedClickable(onClick = { onKey("⌫") }, onLongClick = { onKey("C") }),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.AutoMirrored.Rounded.Backspace, "刪除(長按清除)", Modifier.size(24.dp)) }
                OpKey("÷", keyH, Modifier.weight(1f)) { onKey("÷") }
                OpKey("×", keyH, Modifier.weight(1f)) { onKey("×") }
            }
            listOf(listOf("7", "8", "9") to "−", listOf("4", "5", "6") to "+", listOf("1", "2", "3") to "=").forEach { (digits, op) ->
                Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                    digits.forEach { k -> Key(k, keyH, Modifier.weight(1f)) { onKey(k) } }
                    OpKey(op, keyH, Modifier.weight(1f)) { onKey(op) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                listOf("00", "0", ".").forEach { k -> Key(k, keyH, Modifier.weight(1f)) { onKey(k) } }
                Box(
                    Modifier.weight(1f).height(keyH).clip(RoundedCornerShape(16.dp))
                        .background(if (canSave) cs.primary else cs.surfaceVariant)
                        .clickable(enabled = canSave, onClick = onSave),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "儲存", fontSize = 19.sp, fontWeight = FontWeight.Bold,
                        color = if (canSave) cs.onPrimary else ledger.textMuted,
                    )
                }
            }
        }
    }
}

const val KEY_HEIGHT_DEFAULT = 52f
const val KEY_HEIGHT_MIN = 40f
const val KEY_HEIGHT_MAX = 80f

/** An operator key (+ − × ÷ =), tinted so it stands apart from the digits. */
@Composable
private fun OpKey(label: String, height: Dp, modifier: Modifier, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Box(
        modifier.height(height).clip(RoundedCornerShape(16.dp)).background(cs.primaryContainer).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(label, fontSize = 26.sp, fontWeight = FontWeight.Medium, color = cs.onPrimaryContainer) }
}

@Composable
private fun Key(label: String, height: Dp, modifier: Modifier, muted: Boolean = false, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Box(
        modifier.height(height).clip(RoundedCornerShape(16.dp))
            .background(if (muted) cs.surfaceVariant else cs.background)
            .border(1.dp, ledger.hairline, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label, fontSize = if (muted) 18.sp else 24.sp, fontWeight = FontWeight.Medium,
            color = if (muted) cs.onSurfaceVariant else cs.onSurface,
        )
    }
}
