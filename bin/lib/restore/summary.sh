############################################################
#
# Conclusion
#

num_actions=$(echo $(egrep "^$actionLead" "$helper_log" | wc -l))
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Restore Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Automated actions : $num_actions"

if [ "$num_actions" -eq 0 ]; then
    echo "  Target instance is the same as the source. No updates required."
fi

echo "  AWS CLI log       : $helper_log"
echo ""

if [ -n "$dryrun" ]; then
    echo "  Mode: DRY RUN — no changes were made to the target instance."
    echo ""
fi

############################################################
#
# Manual Actions Required
#

num_manual=$(wc -l < "$TEMPMANUAL" 2>/dev/null | tr -d ' ')
num_manual=${num_manual:-0}

if [ "$num_manual" -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ⚠ MANUAL ACTIONS REQUIRED ($num_manual items)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  The following items could not be automated and require"
    echo "  operator intervention before the instance is fully operational:"
    echo ""

    # Group by category
    local_categories=$(cut -d']' -f1 "$TEMPMANUAL" | sed 's/^\[//' | sort -u)
    while IFS= read -r category; do
        [ -z "$category" ] && continue
        echo "  [$category]"
        grep "^\[$category\]" "$TEMPMANUAL" | sed "s/^\[$category\] /    • /" 
        echo ""
    done <<< "$local_categories"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Complete the manual actions above, then run:"
    echo "    connect_validate -m full -p <profile> $instance_alias_dir_a"
    echo "  to verify the instance is ready for live traffic."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✓ No manual actions required."
    echo "  Run connect_validate -m full to confirm readiness."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

