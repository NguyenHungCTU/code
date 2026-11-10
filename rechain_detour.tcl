# ============================================================
# reorder_selected_buffers.tcl
#
# Select exactly 10 buffer instances in Innovus GUI.
#
# Original:
#   B1 -> B2 -> B3 -> B4 -> B5 -> B6 -> B7 -> B8 -> B9 -> B10
#
# Reordered:
#   B1 -> B4 -> B2 -> B5 -> B3 -> B6 -> B9 -> B7 -> B10 -> B8
#
# Output:
#   reorder_buffers.eco
#
# Review the ECO file before applying:
#   loadECO reorder_buffers.eco
# ============================================================


# ------------------------------------------------------------
# USER SETTINGS
# ------------------------------------------------------------

# Change these names to match your buffer library cells.
set INPUT_PIN  "A"
set OUTPUT_PIN "Y"

set ECO_FILE "reorder_buffers.eco"


# ------------------------------------------------------------
# Helper: get selected instance pin and its connected net
# ------------------------------------------------------------

proc get_inst_pin_net {inst_ptr inst_name pin_name} {

    set expected_name "${inst_name}/${pin_name}"
    set matching_pins {}

    set inst_terms [dbGet -e ${inst_ptr}.instTerms]

    foreach term_ptr $inst_terms {
        set term_name [dbGet ${term_ptr}.name]

        if {$term_name eq $expected_name} {
            lappend matching_pins $term_ptr
        }
    }

    if {[llength $matching_pins] != 1} {
        error "Cannot find exactly one pin '$expected_name'. Check INPUT_PIN/OUTPUT_PIN."
    }

    set term_ptr [lindex $matching_pins 0]
    set net_name [dbGet -e ${term_ptr}.net.name]

    if {[llength $net_name] != 1 || $net_name eq "" || $net_name eq "0x0"} {
        error "Pin '$expected_name' does not have exactly one connected net."
    }

    return $net_name
}


# ------------------------------------------------------------
# Main procedure
# ------------------------------------------------------------

proc reorder_selected_buffers {input_pin output_pin eco_file} {

    set selected [dbGet -e selected]

    if {[llength $selected] != 10} {
        error "Please select exactly 10 buffer instances. Current selection: [llength $selected]"
    }

    # Store information for each selected instance.
    array set in_net  {}
    array set out_net {}
    array set inst_seen {}
    array set out_owner {}

    set instances {}

    foreach inst_ptr $selected {

        set obj_type [dbGet ${inst_ptr}.objType]

        if {$obj_type ne "inst"} {
            error "Selection contains an object of type '$obj_type'. Select buffer instances only."
        }

        set inst_name [dbGet ${inst_ptr}.name]

        # ECO directives below use whitespace-separated names.
        if {[regexp {\s} $inst_name]} {
            error "Instance name contains whitespace: '$inst_name'"
        }

        if {[info exists inst_seen($inst_name)]} {
            error "Duplicate instance in selection: $inst_name"
        }

        set inst_seen($inst_name) 1

        set in_net($inst_name) \
            [get_inst_pin_net $inst_ptr $inst_name $input_pin]

        set out_net($inst_name) \
            [get_inst_pin_net $inst_ptr $inst_name $output_pin]

        foreach net_name [list $in_net($inst_name) $out_net($inst_name)] {
            if {[regexp {\s} $net_name]} {
                error "Net name contains whitespace: '$net_name'"
            }
        }

        # Each selected buffer must have a distinct output net.
        if {[info exists out_owner($out_net($inst_name))]} {
            error "Multiple selected buffers share output net '$out_net($inst_name)'."
        }

        set out_owner($out_net($inst_name)) $inst_name
        lappend instances $inst_name
    }

    # Find B1: its input net is not driven by an output of
    # another selected buffer.
    set roots {}

    foreach inst_name $instances {
        if {![info exists out_owner($in_net($inst_name))]} {
            lappend roots $inst_name
        }
    }

    if {[llength $roots] != 1} {
        error "Expected one chain start, but found [llength $roots]: $roots"
    }

    # Build the original chain by following output-net -> input-net.
    set original_order [list [lindex $roots 0]]
    array set visited {}
    set visited([lindex $roots 0]) 1

    while {[llength $original_order] < 10} {

        set current [lindex $original_order end]
        set current_output_net $out_net($current)

        set next_candidates {}

        foreach inst_name $instances {
            if {$in_net($inst_name) eq $current_output_net} {
                lappend next_candidates $inst_name
            }
        }

        if {[llength $next_candidates] != 1} {
            error "Expected one selected successor after '$current' on net '$current_output_net'; found [llength $next_candidates]: $next_candidates"
        }

        set next [lindex $next_candidates 0]

        if {[info exists visited($next)]} {
            error "Loop detected at '$next'."
        }

        set visited($next) 1
        lappend original_order $next
    }

    # B10 output must not feed the input of a selected buffer.
    set last [lindex $original_order end]

    foreach inst_name $instances {
        if {$in_net($inst_name) eq $out_net($last)} {
            error "The last selected buffer output feeds selected buffer '$inst_name'; chain is not linear."
        }
    }

    # Tcl indices: B1=0, B2=1, ..., B10=9
    #
    # New order:
    # B1 B4 B2 B5 B3 B6 B9 B7 B10 B8
    set new_indices {0 3 1 4 2 5 8 6 9 7}

    set new_order {}

    foreach idx $new_indices {
        lappend new_order [lindex $original_order $idx]
    }

    puts "\n========== ORIGINAL ORDER =========="
    for {set i 0} {$i < 10} {incr i} {
        set inst_name [lindex $original_order $i]
        puts [format "B%-2d %-50s IN=%s  OUT=%s" \
            [expr {$i + 1}] \
            $inst_name \
            $in_net($inst_name) \
            $out_net($inst_name)]
    }

    puts "\n========== NEW ORDER ==============="
    puts [join $new_order " -> "]

    set final_net $out_net([lindex $original_order 9])
    puts "\nFinal output net: $final_net"

    # Build the complete ECO in memory before writing the file.
    set eco_lines {}

    lappend eco_lines "# Generated buffer reorder ECO"
    lappend eco_lines "# Review connectivity and branch conditions before loadECO."
    lappend eco_lines ""

    # Disconnect the nine inputs that will be reconnected.
    # Keep the first buffer's input unchanged.
    lappend eco_lines "# 1. Detach selected buffer inputs"

    for {set i 1} {$i < 10} {incr i} {
        set inst_name [lindex $original_order $i]

        lappend eco_lines \
            "DETACHTERM $inst_name $input_pin $in_net($inst_name)"
    }

    lappend eco_lines ""
    lappend eco_lines "# 2. Assign buffer outputs to the original chain nets"

    # At position i in the new chain, connect its output to
    # the output net of position i in the original chain.
    #
    # The original B10 output net remains the final output net.
    for {set i 0} {$i < 10} {incr i} {

        set new_inst [lindex $new_order $i]
        set old_inst_at_position [lindex $original_order $i]
        set target_net $out_net($old_inst_at_position)

        # ATTACHTERM automatically detaches an existing connection.
        if {$out_net($new_inst) ne $target_net} {
            lappend eco_lines \
                "ATTACHTERM $new_inst $output_pin $target_net"
        }
    }

    lappend eco_lines ""
    lappend eco_lines "# 3. Connect each input to the preceding output net"

    for {set i 1} {$i < 10} {incr i} {

        set new_inst [lindex $new_order $i]

        # Edge i-1 uses the original output net at position i-1.
        set original_prev [lindex $original_order [expr {$i - 1}]]
        set target_net $out_net($original_prev)

        lappend eco_lines \
            "ATTACHTERM $new_inst $input_pin $target_net"
    }

    set fp [open $eco_file w]
    puts $fp [join $eco_lines "\n"]
    close $fp

    puts "\nECO file created: $eco_file"
    puts "Review the file and connectivity before running:"
    puts "    loadECO $eco_file"
}


# ------------------------------------------------------------
# Run
# ------------------------------------------------------------

reorder_selected_buffers $INPUT_PIN $OUTPUT_PIN $ECO_FILE
