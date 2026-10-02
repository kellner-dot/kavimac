#!/bin/bash
#===============================================================================
# lib/maintenance.sh — KaviGuard on-demand maintenance runner
# Runs macOS periodic scripts and optionally rebuilds system databases.
# Every step is individually confirmed; nothing runs automatically and
# nothing is scheduled. DB rebuilds happen only when symptomatic.
#===============================================================================

# --- Step 1: macOS periodic scripts (daily/weekly/monthly) ---
_maintenance_periodic() {
    echo ""
    echo "--- Step 1: Periodic maintenance scripts ---"
    echo "  Runs 'sudo periodic daily weekly monthly' (log rotation, cleanup of"
    echo "  /tmp, whatis DB rebuild, etc.). It can take a few minutes."
    if confirm "Run the macOS periodic scripts now?"; then
        if sudo periodic daily weekly monthly; then
            echo "  Periodic scripts completed."
            echo "PERIODIC_DONE=1"
            klog "Maintenance: ran periodic daily weekly monthly"
        else
            echo "  Periodic scripts reported an error — check output above."
            echo "PERIODIC_DONE=0"
            klog "Maintenance: periodic scripts failed"
        fi
    else
        echo "  Skipped."
        echo "PERIODIC_DONE=0"
    fi
}

# --- Step 2: verify startup disk (report-only; never auto-repairs) ---
_maintenance_verify_disk() {
    echo ""
    echo "--- Step 2: Verify startup disk ---"
    echo "  Runs 'diskutil verifyVolume /' — read-only, safe."
    if confirm "Verify the startup disk now?"; then
        local out
        if out=$(diskutil verifyVolume / 2>&1); then
            echo "$out" | tail -5 | sed 's/^/  /'
            echo "DISK_VERIFY_OK=1"
            klog "Maintenance: diskutil verifyVolume / OK"
        else
            echo "$out" | tail -10 | sed 's/^/  /'
            echo "DISK_VERIFY_OK=0"
            klog "Maintenance: diskutil verifyVolume / reported problems"
        fi
        echo ""
        echo "  If the output above suggests a repair, run this yourself:"
        echo "    sudo diskutil repairVolume /"
        echo "  KaviGuard never runs repairVolume automatically."
    else
        echo "  Skipped."
        echo "DISK_VERIFY_OK=0"
    fi
}

# --- Step 3: Spotlight reindex (warns about CPU on 8GB machines) ---
_maintenance_spotlight() {
    echo ""
    echo "--- Step 3: Spotlight reindex ---"
    echo "  WARNING: this pegs the CPU on an 8GB machine until the reindex"
    echo "  finishes. Only do this if Spotlight search is broken or missing files."
    if confirm "Erase and rebuild the Spotlight index now?"; then
        if sudo mdutil -E /; then
            echo "  Spotlight reindex started — give it time to finish."
            echo "SPOTLIGHT_REINDEXED=1"
            klog "Maintenance: sudo mdutil -E / (Spotlight reindex started)"
        else
            echo "  mdutil failed — check output above."
            echo "SPOTLIGHT_REINDEXED=0"
            klog "Maintenance: mdutil -E failed"
        fi
    else
        echo "  Skipped."
        echo "SPOTLIGHT_REINDEXED=0"
    fi
}

# --- Step 4: LaunchServices database rebuild ---
_maintenance_launchservices() {
    echo ""
    echo "--- Step 4: LaunchServices rebuild ---"
    echo "  Rebuilds the 'Open with' database. Only do this if 'Open with' shows"
    echo "  duplicate or stale app entries."
    if confirm "Rebuild the LaunchServices database now?"; then
        local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if "$lsregister" -kill -r -domain local -domain system -domain user; then
            echo "  LaunchServices database rebuilt."
            echo "LAUNCHSERVICES_REBUILT=1"
            klog "Maintenance: rebuilt LaunchServices database"
        else
            echo "  lsregister failed — check output above."
            echo "LAUNCHSERVICES_REBUILT=0"
            klog "Maintenance: lsregister rebuild failed"
        fi
    else
        echo "  Skipped."
        echo "LAUNCHSERVICES_REBUILT=0"
    fi
}

# --- Step 5: Mail (never auto-rebuilt; manual step only) ---
_maintenance_mail() {
    echo ""
    echo "--- Step 5: Mail database ---"
    echo "  KaviGuard does NOT rebuild the Mail database automatically."
    echo "  The Envelope Index lives at:"
    echo "    ~/Library/Mail/V10/MailData/Envelope Index"
    echo "  Manual step (only if Mail search is broken): quit Mail, move"
    echo "  'Envelope Index' (and 'Envelope Index-wal'/'-shm' if present) to the"
    echo "  Trash, reopen Mail, and let it reindex on its own."
    echo "MAIL_DB_TOUCHED=0"
    klog "Maintenance: Mail Envelope Index left untouched (manual step printed)"
}

# --- Run all maintenance steps, each individually confirmed ---
run_maintenance() {
    echo "=== KaviGuard Maintenance ==="
    echo "  On-demand only: nothing here is scheduled or automatic."
    echo "  Database rebuilds (Spotlight, LaunchServices) should only run"
    echo "  when something is actually broken."
    _maintenance_periodic
    _maintenance_verify_disk
    _maintenance_spotlight
    _maintenance_launchservices
    _maintenance_mail
    echo ""
    echo "MAINTENANCE_DONE=1"
    echo "  Maintenance pass finished."
    klog "Maintenance: run complete"
}
