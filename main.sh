#!/bin/bash

# Optional inputs
if [[ -n "$INPUT_PLAN" ]]; then
    if [[ ! -f "$INPUT_PLAN" ]]; then
        echo "Terraform Apply | Error | Plan file \"$INPUT_PLAN\" does not exist."
        ExitCode=1
    else
        # Gather the output of `terraform apply`.
        echo "Terraform Apply | INFO  | Apply the terraform plan $INPUT_PLAN."
        Output=$(terraform apply -input=false -no-color -auto-approve -lock-timeout=300s $INPUT_PLAN ${*} 2>&1)
        ExitCode=${?}
    fi
fi

# Exit Code: 0
# Meaning: 0 = Terraform apply applied
# Actions: Strip out the refresh section, ignore everything after the 72 dashes, format, colourise and build PR comment.
if [[ $ExitCode -eq 0 ]]; then
    if echo "${Output}" | egrep '^-{72}$' &> /dev/null; then
        Output=$(echo "${Output}" | sed -n -r '/-{72}/,/-{72}/{ /-{72}/d; p }')
        echo "egrep"
    fi
    Output=$(echo "${Output}" | tail -c 65300) # GitHub has a 65535-char comment limit - truncate output, leaving space for comment wrapper
    Output=$(echo "${Output}" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line
    Output=$(echo "${Output}" | sed -r 's/~/!/g') # Replace ~ with ! to colourise the diff in GitHub comments
    Pr_Comment="### ${GITHUB_WORKFLOW} - Terraform apply Succeeded
<details><summary>Show Output</summary>
<p>

\`\`\`diff
$Output
\`\`\`

</p>
</details>"
fi

# Exit Code: 1
# Meaning: Terraform apply failed.
# Actions: Build PR comment.
if [[ $ExitCode -eq 1 ]]; then
    Pr_Comment="### ${GITHUB_WORKFLOW} - Terraform apply Failed
<details><summary>Show Output</summary>
<p>
$Output
</p>
</details>"
fi

if [[ "$GITHUB_EVENT_NAME" != "push" && "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "issue_comment" && "$GITHUB_EVENT_NAME" != "pull_request_review_comment" && "$GITHUB_EVENT_NAME" != "pull_request_target" && "$GITHUB_EVENT_NAME" != "pull_request_review"  ]]; then

    echo "Terraform Apply | INFO  | $GITHUB_EVENT_NAME event does not relate to a pull request."

else

    Accept_Header="Accept: application/vnd.github.v3+json"
    Auth_Header="Authorization: token $INPUT_GITHUB_TOKEN"
    Content_Header="Content-Type: application/json"

    if [[ "$GITHUB_EVENT_NAME" == "issue_comment" ]]; then
        Pr_Comments_Url=$(jq -r ".issue.comments_url" "$GITHUB_EVENT_PATH")
    else
        Pr_Comments_Url=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
    fi
    Pr_Comment_Uri=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")

    # Add apply comment to PR.
    Pr_Payload=$(echo '{}' | jq --arg body "$Pr_Comment" '.body = $body')
    echo "Terraform Apply | INFO  | Adding apply comment to PR."
    {
        curl -sS -X POST -H "$Auth_Header" -H "$Accept_Header" -H "$Content_Header" -d "$Pr_Payload" -L "$Pr_Comments_Url" > /dev/null
    } ||
    {
        echo "Terraform Apply | ERROR    | Unable to add apply comment to PR."
    }

fi

exit $ExitCode
