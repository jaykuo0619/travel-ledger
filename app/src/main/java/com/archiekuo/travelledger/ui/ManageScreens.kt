@file:OptIn(ExperimentalLayoutApi::class)

package com.archiekuo.travelledger.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

data class ManageItem(
    val id: Long,
    val name: String,
    val icon: ImageVector,
    val color: Color,
    val iconKey: String = "",
    val colorIdx: Int = -1,
    /** Only what the user added can be deleted; the app's own items can be renamed. */
    val deletable: Boolean = true,
)

/** Editable, reorderable list used for categories (with icon/color) and payment methods. */
@Composable
fun ManageListScreen(
    title: String,
    items: List<ManageItem>,
    styleEditable: Boolean,
    /** e.g. "基礎分類不能刪除,可以改名。" */
    builtInNote: String,
    /** What deleting this item would change, worked out when the user asks to delete it. */
    deleteHint: suspend (id: Long) -> String,
    onBack: () -> Unit,
    onAdd: (name: String, icon: String, color: Int) -> Unit,
    onUpdate: (id: Long, name: String, icon: String, color: Int) -> Unit,
    onDelete: (Long) -> Unit,
    onMove: (Int, Int) -> Unit,
) {
    var editing by remember { mutableStateOf<ManageItem?>(null) }
    var adding by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<ManageItem?>(null) }
    var hint by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(deleting) { hint = deleting?.let { deleteHint(it.id) } }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            AppTopBar(title, onBack = onBack, actions = {
                Button(
                    { adding = true }, shape = RoundedCornerShape(50),
                    contentPadding = PaddingValues(horizontal = 14.dp), modifier = Modifier.padding(end = 8.dp).heightIn(min = 38.dp),
                ) {
                    Icon(Icons.Rounded.Add, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("新增")
                }
            })
        },
    ) { pad ->
        LazyColumn(
            Modifier.padding(top = pad.calculateTopPadding()).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
        ) {
            item {
                LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(vertical = 4.dp)) {
                    items.forEachIndexed { index, item ->
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 68.dp), color = ledger.hairline)
                        Row(
                            Modifier.fillMaxWidth().clickable { editing = item }.padding(start = 14.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            IconTile(item.icon, item.color, size = 40.dp)
                            Spacer(Modifier.width(14.dp))
                            Text(item.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                            SmallIcon(Icons.Rounded.KeyboardArrowUp, "上移", index > 0) { onMove(index, index - 1) }
                            SmallIcon(Icons.Rounded.KeyboardArrowDown, "下移", index < items.lastIndex) { onMove(index, index + 1) }
                            if (item.deletable) SmallIcon(Icons.Rounded.DeleteOutline, "刪除", true) { deleting = item }
                            else Spacer(Modifier.width(40.dp))
                        }
                    }
                }
            }
            item {
                Text(
                    "點項目可修改名稱${if (styleEditable) "、圖示與顏色" else ""}。$builtInNote",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 12.dp, start = 4.dp),
                )
            }
        }
    }

    if (adding || editing != null) {
        val e = editing
        ItemDialog(
            title = if (e == null) "新增" else "編輯",
            initial = e,
            styleEditable = styleEditable,
            onDismiss = { adding = false; editing = null },
            onConfirm = { name, icon, color ->
                if (e == null) onAdd(name, icon, color) else onUpdate(e.id, name, icon, color)
                adding = false; editing = null
            },
        )
    }
    deleting?.let { item ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            icon = { Icon(Icons.Rounded.DeleteOutline, null) },
            title = { Text("刪除「${item.name}」?") },
            text = { Text(hint ?: "") },
            confirmButton = { TextButton({ onDelete(item.id); deleting = null }) { Text("刪除", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton({ deleting = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun SmallIcon(icon: ImageVector, desc: String, enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick, enabled = enabled, modifier = Modifier.size(40.dp)) {
        Icon(icon, desc, Modifier.size(20.dp), tint = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else ledger.hairline)
    }
}

@Composable
private fun ItemDialog(
    title: String,
    initial: ManageItem?,
    styleEditable: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (String, String, Int) -> Unit,
) {
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var iconKey by remember { mutableStateOf(initial?.iconKey ?: "") }
    var colorIdx by remember { mutableIntStateOf(initial?.colorIdx ?: -1) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("名稱") }, singleLine = true, shape = MaterialTheme.shapes.medium)
                if (styleEditable) {
                    val preview = categoryStyle(name.ifBlank { "其他" }, iconKey, colorIdx)
                    Text("顏色", style = CaptionStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Palette.forEachIndexed { i, c ->
                            val on = c == preview.color
                            Box(
                                Modifier.size(30.dp).clip(CircleShape).background(c)
                                    .border(3.dp, if (on) MaterialTheme.colorScheme.onSurface else Color.Transparent, CircleShape)
                                    .clickable { colorIdx = i },
                            )
                        }
                    }
                    Text("圖示", style = CaptionStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        CategoryIcons.forEach { (key, icon) ->
                            val on = icon == preview.icon
                            Box(
                                Modifier.clip(RoundedCornerShape(12.dp))
                                    .border(2.dp, if (on) preview.color else Color.Transparent, RoundedCornerShape(12.dp))
                                    .clickable { iconKey = key },
                            ) { IconTile(icon, if (on) preview.color else MaterialTheme.colorScheme.onSurfaceVariant, size = 38.dp) }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton({ onConfirm(name.trim(), iconKey, colorIdx) }, enabled = name.isNotBlank()) { Text("確定") } },
        dismissButton = { TextButton(onDismiss) { Text("取消") } },
    )
}
