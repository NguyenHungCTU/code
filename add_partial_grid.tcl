# Innovus legacy Tcl: create a grid of partial placement blockages over the core.
# Units: microns. Density: maximum placement density allowed, in percent.
# Example:
#   source add_partial_grid.tcl
#   add_partial_grid 50 70
# Optional: add_partial_grid <box_um> <density_pct> <gap_um> <name_prefix>
# Edge boxes are clipped to the rectangular core bounding box.
# This script creates blockages; it does not move existing cells or run placement.

proc add_partial_grid {{box_um 50.0} {density_pct 70} {gap_um 0.0} {prefix AUTO_PARTIAL}} {
    foreach cmd {dbGet createPlaceBlockage} {
        if {![llength [info commands $cmd]]} {
            error "Run this script inside Innovus legacy Tcl with a loaded design: missing $cmd"
        }
    }
    if {![string is double -strict $box_um] ||
        !($box_um > 0.0 && $box_um < Inf)} {
        error "box_um must be a finite positive number"
    }
    if {![string is double -strict $gap_um] ||
        !($gap_um >= 0.0 && $gap_um < Inf)} {
        error "gap_um must be a finite nonnegative number"
    }
    if {![string is integer -strict $density_pct] ||
        $density_pct <= 0 || $density_pct > 100} {
        error "density_pct must be an integer in (0, 100]"
    }
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $prefix]} {
        error "prefix must use letters, digits and underscores, starting with a letter or underscore"
    }

    set core [dbGet top.fPlan.coreBox]
    if {[llength $core] == 1} {set core [lindex $core 0]}
    if {[llength $core] != 4} {error "Cannot read a rectangular core bounding box: $core"}
    foreach coordinate $core {
        if {![string is double -strict $coordinate] ||
            !($coordinate > -Inf && $coordinate < Inf)} {
            error "Invalid core coordinate: $coordinate"
        }
    }
    lassign $core llx lly urx ury
    if {$urx <= $llx || $ury <= $lly} {error "Core has zero or negative area: $core"}

    # Check once before mutation; existing blockages are never deleted or changed.
    foreach name [dbGet top.fPlan.pBlkgs.name] {
        if {[string match "${prefix}_*" $name]} {
            error "Blockages with prefix ${prefix}_ already exist; use another prefix or remove that grid first"
        }
    }

    set pitch [expr {double($box_um) + $gap_um}]
    set nx [expr {int(ceil(($urx - $llx) / $pitch))}]
    set ny [expr {int(ceil(($ury - $lly) / $pitch))}]
    set count 0
    for {set ix 0} {$ix < $nx} {incr ix} {
        set x1 [expr {$llx + $ix * $pitch}]
        set x2 [expr {min($x1 + $box_um, $urx)}]
        for {set iy 0} {$iy < $ny} {incr iy} {
            set y1 [expr {$lly + $iy * $pitch}]
            set y2 [expr {min($y1 + $box_um, $ury)}]
            if {$x2 <= $x1 || $y2 <= $y1} {continue}
            createPlaceBlockage -name ${prefix}_${ix}_${iy} \
                -type partial -density $density_pct \
                -box [list $x1 $y1 $x2 $y2]
            incr count
        }
    }
    puts "Created $count partial placement blockages: box=${box_um}um, gap=${gap_um}um, allowed_density=${density_pct}%"
    return $count
}
