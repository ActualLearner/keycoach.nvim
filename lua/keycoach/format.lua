local M = {}

function M.recommendation_title(recommendation)
  if recommendation.kind == "existing_mapping" then
    return "Use existing mapping  " .. recommendation.mapping.lhs
  end
  if recommendation.kind == "native_action" then
    return "Use native action  " .. recommendation.native_action.keys
  end
  return "Add mapping  " .. (recommendation.mapping and recommendation.mapping.lhs or "")
end

function M.evidence_summary(evidence)
  evidence = evidence or {}
  return string.format(
    "%d uses across %d sessions · ~%d keys saved",
    evidence.occurrences or 0,
    evidence.sessions or 0,
    evidence.estimated_keystrokes_saved or 0
  )
end

return M
