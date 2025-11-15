# Announcement Builder - Tag Reference

The Announcement Builder supports tag-based text replacement to dynamically insert role and player information into raid announcements.

## Tag Format

Tags use the format `[Rx.TYPE]` where:
- `R` = Role indicator
- `x` = Role number (1-based index based on role order)
- `TYPE` = The type of information to display

## Available Tags

### Role Title: `[Rx.T]`
Displays the name/title of the role.

**Example:**
```
[R1.T] will tank the boss
```
**Output:**
```
Main Tank will tank the boss
```

### Player Name: `[Rx.Py]`
Displays the name of player `y` in role `x`.

**Example:**
```
[R1.P1] is main tank
```
**Output:**
```
Tankmedady is main tank
```

### All Players in Role: `[Rx.P]`
Displays all assigned players in role `x`, space-delimited with class colors.

**Example:**
```
[R2.T]: [R2.P]
```
**Output:**
```
Off Tanks: Gnuzmas Zanthor Tankthree
```
**Note:** Players are listed in slot assignment order.

### All Players with Assignments: `[Rx.PA]`
Displays all assigned players in role `x` with their assignment numbers, space-delimited with class colors.

**Example:**
```
[R2.T]: [R2.PA]
```
**Output:**
```
Off Tanks: Gnuzmas (1) Zanthor (2) Tankthree
```
**Note:** Assignment numbers are shown in parentheses. Players without assignment numbers are shown without parentheses. Players are listed in slot assignment order.

### Raid Mark: `[Rx.My]`
Displays the raid mark assigned to player `y` in role `x`.

**Example:**
```
[R2.P1] has [R2.M1]
```
**Output:**
```
Gnuzmas has {Star}
```

### Assignment Number: `[Rx.Ay]`
Displays the assignment number for player `y` in role `x`. Assignment numbers are 1-9 or 0 (shown as empty).

**Example:**
```
[R1.P1] is assignment [R1.A1]
```
**Output:**
```
Tankmedady is assignment 1
```

### Players with Assignment Number: `[Rx.A=y]`
Displays all players in role `x` who have assignment number `y`, space-delimited with class colors.

**Example:**
```
Group 1: [R2.A=1]
Group 2: [R2.A=2]
```
**Output:**
```
Group 1: Gnuzmas Healer1
Group 2: Zanthor Healer2
```
**Note:** Shows only players whose assignment number matches the specified value.

## Raid Mark Symbols

When using `[Rx.My]` tags, the following symbols are returned:
- `{Star}` - Yellow Star (1)
- `{Circle}` - Orange Circle (2)
- `{Diamond}` - Purple Diamond (3)
- `{Triangle}` - Green Triangle (4)
- `{Moon}` - Silver Moon (5)
- `{Square}` - Blue Square (6)
- `{Cross}` - Red Cross (7)
- `{Skull}` - White Skull (8)

## Assignment Numbers

When using `[Rx.Ay]` tags, numbers 1-9 are displayed. 0 is treated as "not set" and displays as empty.
- Enable assignment numbers by checking "Show Assignment" in the Role Edit window
- Click the assignment button next to each player to set their number (left-click increments, right-click decrements)
- Use assignment numbers for grouping, priorities, or any custom ordering system

## Complete Example

**Example:**
```
Line 1: [R1.T]: [R1.P1]
Line 2: [R2.T]: [R2.P]
Line 3: [R5.T]: [R5.P1] and [R5.P2]
Line 4: Kill priority: [R3.M1] then [R3.M2]
Line 5: Group 1: [R2.A=1] | Group 2: [R2.A=2]
```

**Actual Output (when Announce is clicked):**
```
Main Tank: Tankmedady
Off Tanks: Gnuzmas Zanthor Tankthree
Healers: Fatherkaii and Lightbringer
Kill priority: {Skull} then {Cross}
Group 1: Gnuzmas Healer1 | Group 2: Zanthor Healer2
```

## Role Numbering

Roles are numbered sequentially based on their column layout:
- All roles in the **left column** (top to bottom) are numbered first
- Then all roles in the **right column** (top to bottom)

**Example Layout:**
```
Left Column          Right Column
R1: Main Tank        R4: Orb Controller
R2: Near Tanks       R5: Far Tanks
R3: Healers
```

This ordering matches the visual display and ensures consistent tag mapping across announcements, tooltips, and raid marks.

## Conditional Blocks

Conditional blocks allow you to show or hide text based on whether tags have assigned values.

### OR Logic (Default)

Wrap text in square brackets `[content with [tags]]`. The block will:
- **Show** if ANY tag inside has a value
- **Hide** if ALL tags inside are unassigned
- **Remove** unassigned tags from the displayed content

**Example:**
```
[R3.T] [R3.M1] [R3.P1][, [R3.M2] [R3.P2]] healed by [R5.P1]
```

**Outputs:**
- If only R3.P1 assigned: `Near Side Tanks {Cross} Tankmedady healed by Gnuzmas`
- If both R3.P1 and R3.P2 assigned: `Near Side Tanks {Cross} Tankmedady, {Skull} Zanthor healed by Gnuzmas`

### AND Logic (& Prefix)

Start the block with `&` to use AND logic `[&content with [tags]]`. The block will:
- **Show** only if ALL tags inside have values
- **Hide** if ANY tag is unassigned
- **Keep** all content when shown (no tag removal)

**Example:**
```
[R3.T] [R3.M1] [R3.P1][&, [R3.M2] [R3.P2]] healed by [R5.P1]
```

**Outputs:**
- If only R3.P1 assigned: `Near Side Tanks {Cross} Tankmedady healed by Gnuzmas` (entire `, [R3.M2] [R3.P2]` block removed)
- If both R3.P1 and R3.P2 assigned: `Near Side Tanks {Cross} Tankmedady, {Skull} Zanthor healed by Gnuzmas`

### Nested Conditionals

You can nest conditional blocks for complex logic:

**Example:**
```
[R1.T] [R1.P1][ with [R2.P1][ and [R2.P2]]]
```

This creates three levels:
1. Main text (always shown)
2. "with [R2.P1]" (shown if R2.P1 assigned)
3. "and [R2.P2]" (shown if both R2.P1 AND R2.P2 assigned)

## Notes

- Tags that reference non-existent roles or players will remain unchanged (shown as-is)
- Empty announcement lines are not sent to raid chat
- You must have Auto Assign run (or manually assign players) before tags will be replaced with actual names
- Raid marks must be set using the icon buttons next to player names
- Announcements are sent to raid chat when the "Announce" button is clicked
- Conditional blocks are processed from innermost to outermost
- OR blocks automatically clean up unassigned tags for cleaner output
- The `&` prefix goes at the start of the block content: `[&...]` not inside individual tags
