package com.archiekuo.travelledger.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Luggage
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** Flat top bar on the page background: back/close, title + optional subtitle, actions. */
@Composable
fun AppTopBar(
    title: String,
    subtitle: String? = null,
    onBack: (() -> Unit)? = null,
    closeIcon: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().heightIn(min = 60.dp).padding(horizontal = 4.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onBack) {
                Icon(if (closeIcon) Icons.Rounded.Close else Icons.AutoMirrored.Rounded.ArrowBack, if (closeIcon) "關閉" else "返回")
            }
        } else {
            Spacer(Modifier.width(12.dp))
        }
        Column(Modifier.weight(1f).padding(horizontal = 4.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, content = actions)
        Spacer(Modifier.width(4.dp))
    }
}

/**
 * Round primary "confirm" button used in editor top bars. With [ready] false it looks unavailable but can still be
 * tapped, so the screen can say what is missing instead of silently doing nothing.
 */
@Composable
fun ConfirmButton(enabled: Boolean, ready: Boolean = true, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    FilledIconButton(
        onClick, enabled = enabled, modifier = Modifier.padding(end = 8.dp).size(42.dp),
        colors = if (ready) IconButtonDefaults.filledIconButtonColors()
        else IconButtonDefaults.filledIconButtonColors(containerColor = cs.onSurface.copy(alpha = 0.12f), contentColor = cs.onSurface.copy(alpha = 0.38f)),
    ) { Icon(Icons.Rounded.Check, "儲存") }
}

/** White rounded card with a hairline border. */
@Composable
fun LedgerCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    padding: PaddingValues = PaddingValues(16.dp),
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = MaterialTheme.shapes.large
    Column(
        modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerLowest)
            .border(1.dp, ledger.hairline, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(padding),
        content = content,
    )
}

/** Tinted rounded-square icon used for categories and payment methods. */
@Composable
fun IconTile(icon: ImageVector, color: Color, size: Dp = 40.dp, corner: Dp = 12.dp) {
    Box(
        Modifier.size(size).clip(RoundedCornerShape(corner)).background(color.copy(alpha = if (ledger.dark) 0.22f else 0.13f)),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = color, modifier = Modifier.size(size * 0.52f)) }
}

/** Labeled input box: small caption on top, content below, on a soft field background. */
@Composable
fun FieldBox(
    label: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val shape = MaterialTheme.shapes.medium
    Row(
        modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerLowest)
            .border(1.dp, ledger.hairline, shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, style = CaptionStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            content()
        }
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            trailing()
        }
    }
}

@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

/** Full-width pill primary button. */
@Composable
fun PillButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: ImageVector? = null,
    height: Dp = 52.dp,
) {
    Button(
        onClick, modifier.fillMaxWidth().heightIn(min = height), enabled = enabled,
        shape = RoundedCornerShape(16.dp),
        elevation = ButtonDefaults.buttonElevation(0.dp, 0.dp, 0.dp),
    ) {
        if (icon != null) {
            Icon(icon, null, Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, style = MaterialTheme.typography.labelLarge.copy(fontSize = 16.sp))
    }
}

/** Budget usage bar: green, amber past 80%, red past 100%. */
@Composable
fun BudgetBar(fraction: Double, modifier: Modifier = Modifier) {
    val color = when {
        fraction > 1.0 -> ledger.danger
        fraction > 0.8 -> ledger.warning
        else -> ledger.success
    }
    Box(modifier.fillMaxWidth().height(8.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant)) {
        Box(
            Modifier.fillMaxHeight().fillMaxWidth(fraction.toFloat().coerceIn(0f, 1f))
                .clip(CircleShape).background(color),
        )
    }
}

@Composable
fun budgetColor(fraction: Double): Color = when {
    fraction > 1.0 -> ledger.danger
    fraction > 0.8 -> ledger.warning
    else -> ledger.success
}

/** Initial-letter avatar for trip members. */
@Composable
fun Avatar(name: String, size: Dp = 32.dp) {
    val c = avatarColor(name)
    Box(
        Modifier.size(size).clip(CircleShape).background(c.copy(alpha = if (ledger.dark) 0.3f else 0.16f)),
        contentAlignment = Alignment.Center,
    ) {
        // Sized from the circle, not the font setting, so the initial always fits inside it.
        Text(name.take(1), color = c, fontWeight = FontWeight.Bold, fontSize = with(androidx.compose.ui.platform.LocalDensity.current) { (size * 0.42f).toSp() }, maxLines = 1, softWrap = false,
            lineHeight = 1.1.em)
    }
}

/** Trip cover: the photo if any, otherwise an illustration picked from the trip name. */
@Composable
fun TripCover(path: String?, seed: String, modifier: Modifier = Modifier, startDate: Long? = null, theme: String? = null) {
    val image by rememberLocalImage(path)
    Box(modifier.clipToBounds()) {
        val img = image
        if (img != null) {
            Image(img, null, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
        } else {
            // No photo chosen: an illustration matching the trip name and season.
            CoverArtwork(seed, startDate, theme, Modifier.matchParentSize())
        }
    }
}

/** Small translucent badge placed on top of a cover. */
@Composable
fun CoverBadge(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.38f))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        color = Color.White,
        style = MaterialTheme.typography.labelMedium,
    )
}

/** Muted inline meta item: small icon + text. */
@Composable
fun MetaItem(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(15.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(4.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, softWrap = false)
    }
}

/** Selectable pill used for filters and option rows. */
@Composable
fun SelectPill(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
) {
    val shape = RoundedCornerShape(12.dp)
    val cs = MaterialTheme.colorScheme
    Row(
        modifier
            .clip(shape)
            .background(if (selected) cs.primaryContainer else cs.surfaceContainerLowest)
            .border(1.dp, if (selected) cs.primary else ledger.hairline, shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(6.dp))
        }
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            color = if (selected) cs.onPrimaryContainer else cs.onSurface,
        )
    }
}
