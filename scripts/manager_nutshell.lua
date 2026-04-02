local SKILLS = {
  "closecombat", "rangedcombat", "perception", "survival", "endurance",
  "fitness", "persuasion", "expertise", "power", "skulduggery", "operate"
}
local RANDOMSEEDED = false

function onInit()
  if not RANDOMSEEDED then
    math.randomseed(os.time())
    RANDOMSEEDED = true
  end

  ActionsManager.registerResultHandler("nutshellskill", onSkillRoll)
  ActionsManager.registerResultHandler("nutshellattack", onAttackRoll)

  if Session and Session.IsHost and Session.IsHost() then
    DB.setPublic("campaign.tnset", true)
  end

  if DB.getValue("campaign.tnset", 0) == 0 then
    DB.setValue("campaign.tnset", "number", 8)
  end
end

function initRecord(nodeRecord, bNPC)
  if not nodeRecord then
    return
  end

  for _, sSkill in ipairs(SKILLS) do
    if DB.getValue(nodeRecord, sSkill, nil) == nil then
      DB.setValue(nodeRecord, sSkill, "number", 0)
    end
  end

  if DB.getValue(nodeRecord, "strikestaken", nil) == nil then
    DB.setValue(nodeRecord, "strikestaken", "number", 0)
  end
  if DB.getValue(nodeRecord, "straintaken", nil) == nil then
    DB.setValue(nodeRecord, "straintaken", "number", 0)
  end
  if DB.getValue(nodeRecord, "powertheme", nil) == nil then
    DB.setValue(nodeRecord, "powertheme", "string", "")
  end
  if DB.getValue(nodeRecord, "gear", nil) == nil then
    DB.setValue(nodeRecord, "gear", "formattedtext", "")
  end
  if bNPC and DB.getValue(nodeRecord, "nonid_name", nil) == nil then
    DB.setValue(nodeRecord, "nonid_name", "string", "")
  end

  updateDerived(nodeRecord)
end

function resetSkills(nodeRecord)
  if not nodeRecord then
    return
  end

  for _, sSkill in ipairs(SKILLS) do
    DB.setValue(nodeRecord, sSkill, "number", 0)
  end

  updateDerived(nodeRecord)
end

function randomizeSkills(nodeRecord)
  if not nodeRecord then
    return
  end

  local tValues = {}
  for _, sSkill in ipairs(SKILLS) do
    tValues[sSkill] = 0
  end

  local nNegativeBudget = math.random(0, 3)
  local nNegativeAssigned = 0
  while nNegativeAssigned < nNegativeBudget do
    local aChoices = {}
    for _, sSkill in ipairs(SKILLS) do
      if tValues[sSkill] > -2 then
        table.insert(aChoices, sSkill)
      end
    end
    if #aChoices == 0 then
      break
    end

    local sPick = aChoices[math.random(#aChoices)]
    tValues[sPick] = tValues[sPick] - 1
    nNegativeAssigned = nNegativeAssigned + 1
  end

  local nPositiveBudget = 5 + nNegativeAssigned
  local nPositiveAssigned = 0
  while nPositiveAssigned < nPositiveBudget do
    local aChoices = {}
    for _, sSkill in ipairs(SKILLS) do
      if tValues[sSkill] < 3 then
        table.insert(aChoices, sSkill)
      end
    end
    if #aChoices == 0 then
      break
    end

    local sPick = aChoices[math.random(#aChoices)]
    tValues[sPick] = tValues[sPick] + 1
    nPositiveAssigned = nPositiveAssigned + 1
  end

  for _, sSkill in ipairs(SKILLS) do
    DB.setValue(nodeRecord, sSkill, "number", tValues[sSkill])
  end

  updateDerived(nodeRecord)
end

function updateDerived(nodeRecord)
  if not nodeRecord then
    return
  end

  local nEndurance = tonumber(DB.getValue(nodeRecord, "endurance", 0)) or 0
  local nPower = tonumber(DB.getValue(nodeRecord, "power", 0)) or 0
  local nStrikesTaken = math.max(0, tonumber(DB.getValue(nodeRecord, "strikestaken", 0)) or 0)
  local nStrainTaken = math.max(0, tonumber(DB.getValue(nodeRecord, "straintaken", 0)) or 0)

  local nStrikesMax = math.max(0, 4 + nEndurance)
  local nStrainMax = math.max(0, 4 + nPower)
  local nStrikesLeft = math.max(0, nStrikesMax - nStrikesTaken)
  local nStrainLeft = math.max(0, nStrainMax - nStrainTaken)

  DB.setValue(nodeRecord, "strikesmax", "number", nStrikesMax)
  DB.setValue(nodeRecord, "strikesleft", "number", nStrikesLeft)
  DB.setValue(nodeRecord, "strainmax", "number", nStrainMax)
  DB.setValue(nodeRecord, "strainleft", "number", nStrainLeft)
end

function getTargetNumber()
  local nTN = tonumber(DB.getValue("campaign.tnset", 8)) or 8
  if nTN < 1 then
    nTN = 1
  end
  return nTN
end

function formatSigned(nValue)
  if nValue >= 0 then
    return "+" .. nValue
  end
  return tostring(nValue)
end

function strikesFromDifference(nDiff)
  if nDiff >= 8 then
    return 4
  elseif nDiff >= 5 then
    return 3
  elseif nDiff >= 2 then
    return 2
  elseif nDiff >= 0 then
    return 1
  end
  return 0
end

function getDiceResults(rRoll)
  local aResults = {}
  for _, vDie in ipairs(rRoll.aDice or {}) do
    local nResult = 0
    if type(vDie) == "table" then
      nResult = vDie.result or vDie.value or 0
    end
    table.insert(aResults, tostring(nResult))
  end
  return "[" .. table.concat(aResults, ", ") .. "]"
end

function buildDescWithModStack(sBaseDesc, nBaseMod)
  local sDesc = sBaseDesc
  local nTotalMod = nBaseMod or 0

  if ModifierStack and not ModifierStack.isEmpty() then
    local sStackDesc, nStackMod = ModifierStack.getStack(true)
    nTotalMod = nTotalMod + nStackMod
    if sStackDesc and sStackDesc ~= "" then
      sDesc = sDesc .. " [" .. sStackDesc .. "]"
    end
  end

  return sDesc, nTotalMod
end

function performSkillRoll(nodeRecord, sSkill, sLabel)
  if not nodeRecord then
    return
  end

  updateDerived(nodeRecord)

  local rActor = ActorManager.resolveActor(nodeRecord)
  local nSkill = tonumber(DB.getValue(nodeRecord, sSkill, 0)) or 0
  local sDesc, nMod = buildDescWithModStack("[SKILL] " .. sLabel, nSkill)

  local rRoll = {
    sType = "nutshellskill",
    sDesc = sDesc,
    aDice = { "d6", "d6" },
    nMod = nMod,
    nTN = getTargetNumber(),
    sSkill = sSkill,
    sLabel = sLabel,
    sNode = nodeRecord.getPath(),
  }

  ActionsManager.performAction(nil, rActor, rRoll)
end

function performAttackRoll(nodeRecord, sSkill, sLabel)
  if not nodeRecord then
    return
  end

  updateDerived(nodeRecord)

  local rActor = ActorManager.resolveActor(nodeRecord)
  local nSkill = tonumber(DB.getValue(nodeRecord, sSkill, 0)) or 0
  local sDesc, nMod = buildDescWithModStack("[ATTACK] " .. sLabel, nSkill)

  local rRoll = {
    sType = "nutshellattack",
    sDesc = sDesc,
    aDice = { "d6", "d6" },
    nMod = nMod,
    nTN = getTargetNumber(),
    sSkill = sSkill,
    sLabel = sLabel,
    sNode = nodeRecord.getPath(),
  }

  ActionsManager.performAction(nil, rActor, rRoll)
end

function onSkillRoll(rSource, rTarget, rRoll)
  local nTotal = ActionsManager.total(rRoll)
  local nTN
  if Session and Session.IsHost and Session.IsHost() then
    nTN = getTargetNumber()
  else
    nTN = tonumber(rRoll.nTN) or getTargetNumber()
  end
  local nDiff = nTotal - nTN
  local bSuccess = nDiff >= 0

  local rMessage = ActionsManager.createActionMessage(rSource, rRoll)
  rMessage.text = string.format("%s\nDice: %s\nModifier: %s\nTotal: %d vs TN %d\nResult: %s (%s)",
    rRoll.sDesc,
    getDiceResults(rRoll),
    formatSigned(rRoll.nMod or 0),
    nTotal,
    nTN,
    bSuccess and "SUCCESS" or "FAILURE",
    formatSigned(nDiff)
  )
  Comm.deliverChatMessage(rMessage)
end

function onAttackRoll(rSource, rTarget, rRoll)
  local nTotal = ActionsManager.total(rRoll)
  local nTN
  if Session and Session.IsHost and Session.IsHost() then
    nTN = getTargetNumber()
  else
    nTN = tonumber(rRoll.nTN) or getTargetNumber()
  end
  local nDiff = nTotal - nTN
  local bSuccess = nDiff >= 0
  local nStrikes = strikesFromDifference(nDiff)

  local rMessage = ActionsManager.createActionMessage(rSource, rRoll)
  rMessage.text = string.format("%s\nDice: %s\nModifier: %s\nTotal: %d vs TN %d\nResult: %s (%s)\nStrikes: %d",
    rRoll.sDesc,
    getDiceResults(rRoll),
    formatSigned(rRoll.nMod or 0),
    nTotal,
    nTN,
    bSuccess and "SUCCESS" or "FAILURE",
    formatSigned(nDiff),
    nStrikes
  )
  Comm.deliverChatMessage(rMessage)
end
