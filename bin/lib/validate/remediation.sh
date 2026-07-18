print_remediation() {
    echo ""
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}  Remediation Steps${C_RESET}"
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

    for layer in $FAILED_LAYERS; do
        case "$layer" in
        P)
            echo ""
            echo -e "  ${C_BOLD}Pre-flight${C_RESET}"
            echo "    • Verify target instance ID is correct and instance is ACTIVE"
            echo "    • Confirm AWS credentials have connect:* permissions on the target"
            echo "    • If users are missing: pre-create via Identity Center or Connect console"
            echo "    • If external deps missing: deploy Lambda/Lex resources to target account first"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/troubleshooting.html"
            ;;
        0)
            echo ""
            echo -e "  ${C_BOLD}Layer 0: External Dependencies${C_RESET}"
            echo "    • Lambda functions: deploy to the target account and region"
            echo "    • Add connect:InvokeFunction resource-based policy to each Lambda:"
            echo "      aws lambda add-permission --function-name <name> \\"
            echo "        --statement-id AllowConnect --action lambda:InvokeFunction \\"
            echo "        --principal connect.amazonaws.com --source-account <target-account>"
            echo "    • Lex bots: create/import in target account and verify status is Available"
            echo "    • Prompts: upload missing audio files via Connect console or API"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/connect-lambda-functions.html"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/amazon-lex.html"
            ;;
        1)
            echo ""
            echo -e "  ${C_BOLD}Layer 1: Instance Foundation${C_RESET}"
            echo "    • Instance attributes: update via UpdateInstanceAttribute API"
            echo "    • Approved origins: add/remove via AssociateApprovedOrigin API"
            echo "    • If instance is not ACTIVE: check AWS Health Dashboard"
            echo "    → https://docs.aws.amazon.com/connect/latest/APIReference/API_UpdateInstanceAttribute.html"
            ;;
        2)
            echo ""
            echo -e "  ${C_BOLD}Layer 2: Hours of Operations${C_RESET}"
            echo "    • Missing hours: re-run connect_restore or create manually in console"
            echo "    • Config mismatch: update timezone/schedule via UpdateHoursOfOperation API"
            echo "    • Override mismatch: create/update via CreateHoursOfOperationOverride API"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/set-hours-operation.html"
            ;;
        3)
            echo ""
            echo -e "  ${C_BOLD}Layer 3: Queues${C_RESET}"
            echo "    • Missing queues: re-run connect_restore --only queues"
            echo "    • Caller config mismatch: update OutboundCallerConfig via UpdateQueueOutboundCallerIdConfig"
            echo "      (requires a claimed phone number on the target instance)"
            echo "    • HoursOfOperation mismatch: update via UpdateQueueHoursOfOperation API"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/create-queue.html"
            ;;
        4)
            echo ""
            echo -e "  ${C_BOLD}Layer 4: Routing Profiles${C_RESET}"
            echo "    • Missing profiles: re-run connect_restore --only routing"
            echo "    • DefaultOutboundQueue/MediaConcurrency mismatch: UpdateRoutingProfileDefaultOutboundQueue,"
            echo "      UpdateRoutingProfileConcurrency APIs"
            echo "    • Queue associations: AssociateRoutingProfileQueues / DisassociateRoutingProfileQueues"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/routing-profiles.html"
            ;;
        5)
            echo ""
            echo -e "  ${C_BOLD}Layer 5: Security Profiles${C_RESET}"
            echo "    • Missing profiles: re-run connect_restore --only instance"
            echo "    • Permission mismatch: manually align in Connect console → Security profiles"
            echo "      (API does not support granular permission update; full recreation may be required)"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/connect-security-profiles.html"
            ;;
        6)
            echo ""
            echo -e "  ${C_BOLD}Layer 6: User Hierarchy${C_RESET}"
            echo "    • Structure mismatch: update via UpdateUserHierarchyStructure API"
            echo "    • Missing groups: create via CreateUserHierarchyGroup API"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/agent-hierarchy.html"
            ;;
        7)
            echo ""
            echo -e "  ${C_BOLD}Layer 7: Users${C_RESET}"
            echo "    • CRITICAL: Users cannot be fully restored by script (password/IdP link unavailable)"
            echo "    • Pre-create users via Identity Center (SSO) or Connect console"
            echo "    • Ensure Username matches exactly (case-sensitive)"
            echo "    • After creation: verify RoutingProfile and SecurityProfile assignments"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/user-management.html"
            echo "    → See DR_OPERATOR_GUIDE.md for user provisioning checklist"
            ;;
        8)
            echo ""
            echo -e "  ${C_BOLD}Layer 8: Quick Connects${C_RESET}"
            echo "    • Missing: re-run connect_restore --only features"
            echo "    • Type mismatch: delete and recreate (type is immutable after creation)"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/quick-connects.html"
            ;;
        9)
            echo ""
            echo -e "  ${C_BOLD}Layer 9: Contact Flow Modules${C_RESET}"
            echo "    • Missing modules: re-run connect_restore --only flows"
            echo "    • Not published: publish via UpdateContactFlowModuleContent API"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/contact-flow-modules.html"
            ;;
        10)
            echo ""
            echo -e "  ${C_BOLD}Layer 10: Contact Flows${C_RESET}"
            echo "    • Missing flows: re-run connect_restore --only flows"
            echo "    • Not ACTIVE: publish via UpdateContactFlowContent or console"
            echo "    • Type mismatch: flows cannot change type — investigate naming collision"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/connect-contact-flows.html"
            ;;
        11)
            echo ""
            echo -e "  ${C_BOLD}Layer 11: Phone Numbers${C_RESET}"
            echo "    • CRITICAL: Phone numbers cannot be restored by script"
            echo "    • Claim new numbers in target instance via console or ClaimPhoneNumber API"
            echo "    • For number porting (keep same DIDs): open AWS Support case"
            echo "    • After claiming: associate each number with the correct contact flow"
            echo "      (see backup phone_flows.json for the original mappings)"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/claim-phone-number.html"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/port-phone-number.html"
            ;;
        12)
            echo ""
            echo -e "  ${C_BOLD}Layer 12: Integration Associations${C_RESET}"
            echo "    • Re-associate Lambdas/Lex bots via AssociateLambdaFunction / AssociateLexBot APIs"
            echo "    • Verify target ARNs point to resources in the correct account/region"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-instances.html"
            ;;
        13)
            echo ""
            echo -e "  ${C_BOLD}Layer 13: Email Channel${C_RESET}"
            echo "    • Create email addresses via Connect console → Channels → Email"
            echo "    • Verify SES domain identity is configured in the target account"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/email.html"
            ;;
        14*)
            echo ""
            echo -e "  ${C_BOLD}Layer 14: Supporting Resources${C_RESET}"
            echo "    • Agent statuses: CreateAgentStatus API"
            echo "    • Predefined attributes: CreatePredefinedAttribute API"
            echo "    • Task templates: CreateTaskTemplate API"
            echo "    • Evaluation forms: CreateEvaluationForm API"
            echo "    • Rules: CreateRule API"
            echo "    • Views: CreateView API"
            echo "    • Most can be fixed by re-running connect_restore --only supporting"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/connect-rules.html"
            ;;
        15)
            echo ""
            echo -e "  ${C_BOLD}Layer 15: Cases Domain${C_RESET}"
            echo "    • Create Cases domain via CreateDomain API or console"
            echo "    • Recreate field templates and layouts manually"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/cases.html"
            ;;
        16)
            echo ""
            echo -e "  ${C_BOLD}Layer 16: Outbound Campaigns${C_RESET}"
            echo "    • Recreate campaigns via CreateCampaign API"
            echo "    • Verify Pinpoint project and Connect queue associations"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/outbound-campaigns.html"
            ;;
        17)
            echo ""
            echo -e "  ${C_BOLD}Layer 17: Cross-Reference Integrity${C_RESET}"
            echo "    • Broken references indicate upstream resources are missing"
            echo "    • Fix the referenced layer first, then re-validate"
            echo "    • Flow → queue: ensure queues from Layer 3 exist"
            echo "    • Flow → flow: ensure all referenced flows/modules are published"
            echo "    • Routing → queue: ensure queue IDs are correct in routing profiles"
            echo "    → Re-run: connect_validate --only 17 after fixing upstream layers"
            ;;
        18)
            echo ""
            echo -e "  ${C_BOLD}Layer 18: Smoke Tests${C_RESET}"
            echo "    • Functional test failure — verify end-to-end flow execution"
            echo "    • Check CloudWatch logs for Lambda/Lex invocation errors"
            echo "    • Verify contact flow is published and phone number is assigned"
            echo "    → https://docs.aws.amazon.com/connect/latest/adminguide/monitoring-cloudwatch.html"
            ;;
        esac
    done

    echo ""
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo "  Fix failures in layer order (lowest first). Re-run:"
    echo "    connect_validate -m full --target <instance-id> <alias>"
    echo -e "${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}
